#!/bin/bash

# ================================================================
#   NGINX EXTRA - WSS Reverse Proxy + MQTT TLS (stream) + Auto-Renew
#   - WSS  : terminasi TLS di Nginx (443) -> proxy ws:// backend lokal
#            bisa menempel ke domain yang SUDAH ADA (wss://<domain>/ws)
#            atau membuat domain khusus baru.
#   - MQTT : terminasi TLS di Nginx (stream, mis. 8883) -> broker plain
#   - Renew: certbot deploy-hook yang reload Nginx/Mosquitto otomatis
#            mengikuti sertifikat utama (Let's Encrypt)
#   Ubuntu/Debian
# ================================================================

# ---------- Library bersama ----------
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$_MODULE_DIR/../lib"
# shellcheck source=../lib/common.sh
source "$_LIB_DIR/common.sh"      # warna, log_*, confirm, normalize_path
# shellcheck source=../lib/cloudflare.sh
source "$_LIB_DIR/cloudflare.sh"  # CF_CRED_FILE
# shellcheck source=../lib/ssl.sh
source "$_LIB_DIR/ssl.sh"         # resolve_ssl_cert -> SSL_CERT, SSL_KEY

# ---------- Variabel khusus modul ----------
NGINX_CONF="/etc/nginx/nginx.conf"
STREAMS_AVAILABLE="/etc/nginx/streams-available"
STREAMS_ENABLED="/etc/nginx/streams-enabled"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
RENEW_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
RENEW_HOOK="$RENEW_HOOK_DIR/reload-services.sh"

# ---------- Default yang bisa diubah user ----------
DEFAULT_WS_PORT="3001"      # port backend app (Node/PM2) untuk WSS
DEFAULT_WS_PATH="/ws"       # path WSS pada domain existing
DEFAULT_MQTT_TLS_PORT="8883"
DEFAULT_MQTT_BACKEND_HOST="127.0.0.1"
DEFAULT_MQTT_BACKEND_PORT="1883"

# ================================================================
# HELPER: pastikan modul stream Nginx tersedia & ter-include
# ================================================================
_ensure_stream_support() {
    sudo mkdir -p "$STREAMS_AVAILABLE" "$STREAMS_ENABLED"

    # --- Pastikan modul 'stream' benar-benar AKTIF (bukan sekadar dynamic tak di-load) ---
    local v; v="$(nginx -V 2>&1)"
    local ok=0
    if grep -qE -- '--with-stream(=static)?([[:space:]]|$)' <<< "$v"; then
        ok=1   # stream built-in statis, selalu tersedia
    elif grep -q -- '--with-stream=dynamic' <<< "$v" \
         && { ls /etc/nginx/modules-enabled/*stream*.conf &>/dev/null \
              || grep -rqs 'ngx_stream_module' /etc/nginx/modules-enabled/ 2>/dev/null; }; then
        ok=1   # dynamic & modulnya sudah di-load
    fi

    if [[ $ok -eq 0 ]]; then
        log_warn "Modul Nginx 'stream' belum aktif (dynamic tapi belum di-load / belum terpasang)."
        if confirm "Install & aktifkan libnginx-mod-stream sekarang?"; then
            sudo apt update -qq
            sudo apt install -y libnginx-mod-stream &>/dev/null \
                && log_ok "libnginx-mod-stream terinstall & diaktifkan." \
                || { log_err "Gagal install libnginx-mod-stream."; return 1; }
        else
            log_warn "Tanpa modul stream aktif, 'stream {}' akan ditolak nginx -t."
            return 1
        fi
    fi

    # --- Pastikan blok stream{} + include ada di nginx.conf ---
    if ! grep -qE 'include\s+/etc/nginx/streams-enabled/\*\.conf;' "$NGINX_CONF"; then
        if grep -qE '^\s*stream\s*\{' "$NGINX_CONF"; then
            log_warn "Sudah ada blok 'stream {' di $NGINX_CONF tanpa include streams-enabled."
            log_warn "Tambahkan baris ini ke dalam blok stream tsb secara manual, lalu ulangi:"
            echo    "      include /etc/nginx/streams-enabled/*.conf;"
            return 1
        fi
        sudo cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        sudo tee -a "$NGINX_CONF" > /dev/null << 'EOF'

# --- ditambahkan oleh setup-server (nginx-extra) ---
stream {
    include /etc/nginx/streams-enabled/*.conf;
}
EOF
        log_ok "Blok stream{} + include ditambahkan ke nginx.conf."
    fi
    return 0
}

# ================================================================
# HELPER: minta sertifikat (wajib ada) lewat resolve_ssl_cert
# ================================================================
_require_cert() {
    local domain="$1"
    resolve_ssl_cert "$domain" || return 1
    if [[ -z "$SSL_CERT" || -z "$SSL_KEY" ]]; then
        log_err "Fitur ini butuh sertifikat TLS. Tidak ada cert yang dipilih."
        return 1
    fi
    if ! sudo test -f "$SSL_CERT" || ! sudo test -f "$SSL_KEY"; then
        log_err "File sertifikat tidak ditemukan:"
        log_err "  cert: $SSL_CERT"
        log_err "  key : $SSL_KEY"
        return 1
    fi
    return 0
}

# ================================================================
# HELPER: blok location WSS (dipakai mode existing & baru)
# ================================================================
_wss_location_block() {
    local path="$1" port="$2"
    cat << BLOCK

    location $path {
        proxy_pass         http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout  3600s;
        proxy_send_timeout  3600s;
        proxy_cache_bypass  \$http_upgrade;
    }
BLOCK
}

# ================================================================
# HELPER: sisipkan blok location sebelum '}' penutup terakhir file
# ================================================================
_inject_location() {
    local conf="$1" block="$2"
    sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
    local tmp; tmp="$(mktemp)"
    awk -v block="$block" '
        { lines[NR]=$0 }
        END {
            last=0
            for (i=1;i<=NR;i++) if (lines[i] ~ /^[[:space:]]*}[[:space:]]*$/) last=i
            for (i=1;i<=NR;i++) {
                if (i==last) printf "%s\n", block
                print lines[i]
            }
        }' "$conf" > "$tmp"
    sudo cp "$tmp" "$conf"
    rm -f "$tmp"
}

# ================================================================
# MENU 1: SETUP WSS REVERSE PROXY
# ================================================================
nx_setup_wss() {
    clear
    echo -e "${CYAN}--- SETUP WSS REVERSE PROXY (Backend App) ---${NC}"
    echo -e "   ${YELLOW}Terminasi TLS di Nginx (443) lalu proxy ke ws:// app lokal.${NC}"
    echo ""
    echo "   Mode:"
    echo "   [1] Tambahkan path WSS ke domain yang SUDAH ADA  (wss://<domain>$DEFAULT_WS_PATH)"
    echo "   [2] Buat domain KHUSUS baru untuk WSS"
    echo ""
    read -rp "   Pilih [1/2, default 1]: " WSS_MODE
    [[ -z "$WSS_MODE" ]] && WSS_MODE="1"

    case "$WSS_MODE" in
        1) _nx_wss_existing ;;
        2) _nx_wss_new ;;
        *) log_err "Pilihan tidak valid."; sleep 1 ;;
    esac
}

# ----------------------------------------------------------------
# WSS pada domain yang sudah ada (sisipkan location)
# ----------------------------------------------------------------
_nx_wss_existing() {
    echo ""
    # Kumpulkan site yang sudah HTTPS (punya listen 443)
    local sites=()
    for f in "$SITES_AVAILABLE"/*; do
        [[ -f "$f" ]] || continue
        local n; n=$(basename "$f")
        [[ "$n" == "default" ]] && continue
        grep -q "listen 443" "$f" 2>/dev/null && sites+=("$f")
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        log_warn "Tidak ada domain HTTPS (listen 443) yang bisa ditempeli WSS."
        log_info "Buat domain dulu (Hosting > Manage Website) / pasang SSL, atau pakai mode [2]."
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    echo "   Domain HTTPS yang tersedia:"
    for i in "${!sites[@]}"; do
        echo "     [$i] $(basename "${sites[$i]}")"
    done
    echo ""
    read -rp "   Pilih nomor domain: " SEL
    if ! [[ "$SEL" =~ ^[0-9]+$ && "$SEL" -lt ${#sites[@]} ]]; then
        log_err "Pilihan tidak valid."; read -rp "   Enter untuk kembali..." _; return
    fi

    local conf="${sites[$SEL]}"
    local domain; domain=$(grep -oP '(?<=server_name )[^;]+' "$conf" 2>/dev/null | head -1 | awk '{print $1}')
    [[ -z "$domain" ]] && domain="$(basename "$conf")"

    local WS_PATH WS_PORT
    read -rp "   Path WSS (Enter = $DEFAULT_WS_PATH): " WS_PATH
    [[ -z "$WS_PATH" ]] && WS_PATH="$DEFAULT_WS_PATH"
    [[ "$WS_PATH" != /* ]] && WS_PATH="/$WS_PATH"

    while true; do
        read -rp "   Port backend app lokal (Enter = $DEFAULT_WS_PORT): " WS_PORT
        [[ -z "$WS_PORT" ]] && WS_PORT="$DEFAULT_WS_PORT"
        [[ "$WS_PORT" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    # Cegah duplikasi path
    if grep -qE "location[[:space:]]+$WS_PATH([[:space:]/]|\{)" "$conf" 2>/dev/null; then
        log_warn "Location '$WS_PATH' sepertinya sudah ada di config. Dibatalkan agar tidak bentrok."
        read -rp "   Enter untuk kembali..." _; return
    fi

    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain   : $domain (config: $(basename "$conf"))"
    echo "   Endpoint : wss://$domain$WS_PATH"
    echo "   Backend  : 127.0.0.1:$WS_PORT"
    echo ""
    confirm "Sisipkan blok WSS ke config ini?" || { read -rp "   Enter untuk kembali..." _; return; }

    local block; block="$(_wss_location_block "$WS_PATH" "$WS_PORT")"
    _inject_location "$conf" "$block"

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        _nx_wss_resume "$domain" "$WS_PATH" "$WS_PORT" "$conf" "existing"
    else
        log_err "Nginx config error! Mengembalikan dari backup..."
        local last_bak; last_bak=$(ls -t "${conf}".bak.* 2>/dev/null | head -1)
        [[ -n "$last_bak" ]] && { sudo cp "$last_bak" "$conf"; log_ok "Config dipulihkan dari $last_bak"; }
        log_warn "Cek manual: sudo nginx -t"
        read -rp "   Enter untuk kembali..." _
    fi
}

# ----------------------------------------------------------------
# WSS domain khusus baru (server block sendiri)
# ----------------------------------------------------------------
_nx_wss_new() {
    echo ""
    local WSS_DOMAIN WS_PORT WS_PATH
    while true; do
        read -rp "   Domain WSS baru (contoh: ws.example.com): " WSS_DOMAIN
        [[ -n "$WSS_DOMAIN" ]] && break; log_err "Domain tidak boleh kosong."
    done

    read -rp "   Path WSS (Enter = / , contoh: /socket.io/): " WS_PATH
    [[ -z "$WS_PATH" ]] && WS_PATH="/"
    [[ "$WS_PATH" != /* ]] && WS_PATH="/$WS_PATH"

    while true; do
        read -rp "   Port backend app lokal (Enter = $DEFAULT_WS_PORT): " WS_PORT
        [[ -z "$WS_PORT" ]] && WS_PORT="$DEFAULT_WS_PORT"
        [[ "$WS_PORT" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    echo ""
    _require_cert "$WSS_DOMAIN" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain WSS : $WSS_DOMAIN"
    echo "   Endpoint   : wss://$WSS_DOMAIN$WS_PATH"
    echo "   Backend    : 127.0.0.1:$WS_PORT"
    echo "   Cert       : $SSL_CERT"
    echo ""
    confirm "Tulis konfigurasi Nginx WSS?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    local conf="$SITES_AVAILABLE/$WSS_DOMAIN"
    [[ -f "$conf" ]] && {
        sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
        log_warn "Config lama '$WSS_DOMAIN' dibackup & akan ditimpa."
    }

    local block; block="$(_wss_location_block "$WS_PATH" "$WS_PORT")"
    sudo tee "$conf" > /dev/null << NGINXEOF
# WSS reverse proxy - dikelola oleh setup-server (nginx-extra)
server {
    listen 80;
    server_name $WSS_DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $WSS_DOMAIN;

    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
$block
}
NGINXEOF

    sudo ln -sf "$conf" "$SITES_ENABLED/$WSS_DOMAIN"

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        command -v ufw &>/dev/null && sudo ufw allow 443/tcp comment "HTTPS/WSS" &>/dev/null
        _nx_wss_resume "$WSS_DOMAIN" "$WS_PATH" "$WS_PORT" "$conf" "new"
    else
        log_err "Nginx config error! Cek: sudo nginx -t"
        log_warn "Backup (jika ada) tersedia di ${conf}.bak.*"
        read -rp "   Enter untuk kembali..." _
    fi
}

# ----------------------------------------------------------------
# Resume WSS
# ----------------------------------------------------------------
_nx_wss_resume() {
    local domain="$1" path="$2" port="$3" conf="$4" mode="$5"
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} RINGKASAN - WSS BERHASIL DIBUAT                            ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo "  Mode        : $([ "$mode" == "new" ] && echo "Domain khusus baru" || echo "Domain existing")"
    echo "  Domain      : $domain"
    echo -e "  Endpoint    : ${GREEN}wss://$domain$path${NC}"
    echo "  Backend app : http://127.0.0.1:$port  (protokol ws:// di app)"
    echo "  Config      : $conf"
    [[ "$mode" == "new" ]] && echo "  DNS         : pastikan A/AAAA '$domain' mengarah ke server ini."
    echo ""
    echo "  Uji koneksi (butuh websocat/wscat):"
    echo "    wscat -c wss://$domain$path"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# MENU 2: SETUP MQTT TLS (Nginx stream termination)
# ================================================================
nx_setup_mqtt_tls() {
    clear
    echo -e "${CYAN}--- SETUP MQTT TLS (Nginx Stream Termination) ---${NC}"
    echo -e "   ${YELLOW}TLS diterminasi Nginx, lalu di-forward plain ke broker lokal.${NC}"
    echo ""

    _ensure_stream_support || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    local MQTT_DOMAIN TLS_PORT BACKEND_HOST BACKEND_PORT
    while true; do
        read -rp "   Domain untuk sertifikat (contoh: mqtt.example.com): " MQTT_DOMAIN
        [[ -n "$MQTT_DOMAIN" ]] && break; log_err "Domain tidak boleh kosong."
    done

    read -rp "   Port TLS publik (Enter = $DEFAULT_MQTT_TLS_PORT): " TLS_PORT
    [[ -z "$TLS_PORT" ]] && TLS_PORT="$DEFAULT_MQTT_TLS_PORT"

    read -rp "   Host broker lokal (Enter = $DEFAULT_MQTT_BACKEND_HOST): " BACKEND_HOST
    [[ -z "$BACKEND_HOST" ]] && BACKEND_HOST="$DEFAULT_MQTT_BACKEND_HOST"

    read -rp "   Port broker lokal plain (Enter = $DEFAULT_MQTT_BACKEND_PORT): " BACKEND_PORT
    [[ -z "$BACKEND_PORT" ]] && BACKEND_PORT="$DEFAULT_MQTT_BACKEND_PORT"

    echo ""
    _require_cert "$MQTT_DOMAIN" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Cert domain : $MQTT_DOMAIN"
    echo "   Listen TLS  : 0.0.0.0:$TLS_PORT  (mqtts)"
    echo "   Forward ke  : $BACKEND_HOST:$BACKEND_PORT  (plain MQTT)"
    echo "   Cert        : $SSL_CERT"
    echo ""
    echo -e "   ${YELLOW}Catatan:${NC} broker (mis. Mosquitto) cukup listen plain di"
    echo "   $BACKEND_HOST:$BACKEND_PORT dan sebaiknya hanya bind ke localhost."
    echo ""
    confirm "Tulis konfigurasi stream MQTT TLS?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    local slug; slug=$(echo "$MQTT_DOMAIN" | tr '.' '_')
    local conf="$STREAMS_AVAILABLE/mqtt-${slug}.conf"
    [[ -f "$conf" ]] && {
        sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
        log_warn "Config stream lama dibackup & akan ditimpa."
    }

    sudo tee "$conf" > /dev/null << STREAMEOF
# MQTT over TLS (stream termination) - dikelola oleh setup-server (nginx-extra)
# CATATAN: file ini di-include DI DALAM blok 'stream {}' pada nginx.conf
#          (include /etc/nginx/streams-enabled/*.conf;), sehingga 'server {}'
#          di bawah adalah STREAM server (TCP), BUKAN HTTP server.
server {
    listen $TLS_PORT ssl;

    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    proxy_pass            $BACKEND_HOST:$BACKEND_PORT;
    proxy_connect_timeout 5s;
    proxy_timeout         300s;
}
STREAMEOF

    sudo ln -sf "$conf" "$STREAMS_ENABLED/mqtt-${slug}.conf"

    local _test_out
    _test_out="$(sudo nginx -t 2>&1)"
    if [[ $? -eq 0 ]]; then
        sudo systemctl reload nginx
        command -v ufw &>/dev/null && sudo ufw allow "$TLS_PORT/tcp" comment "MQTT TLS" &>/dev/null

        # Diagnostik: pastikan port TLS listen & broker backend punya listener
        local _tls_state="tidak diketahui" _be_state="tidak diketahui"
        if command -v ss &>/dev/null; then
            sudo ss -ltn 2>/dev/null | grep -q ":$TLS_PORT " \
                && _tls_state="LISTEN" || _tls_state="BELUM listen"
            sudo ss -ltn 2>/dev/null | grep -q ":$BACKEND_PORT " \
                && _be_state="LISTEN" || _be_state="TIDAK ada listener"
        fi

        echo ""
        echo -e "${CYAN}============================================================${NC}"
        echo -e "${CYAN} RINGKASAN - MQTT TLS BERHASIL DIBUAT                       ${NC}"
        echo -e "${CYAN}============================================================${NC}"
        echo "  Cert domain : $MQTT_DOMAIN"
        echo -e "  Endpoint    : ${GREEN}mqtts://$MQTT_DOMAIN:$TLS_PORT${NC}"
        echo "  Forward ke  : $BACKEND_HOST:$BACKEND_PORT (plain)"
        echo "  Config      : $conf"
        echo "                (STREAM server, di-include di dalam stream{} nginx.conf)"
        echo "  Port TLS    : $_tls_state    |    Broker backend: $_be_state"
        echo "  Firewall    : buka TCP $TLS_PORT di UFW & cloud security group."
        echo ""
        if [[ "$_be_state" != "LISTEN" ]]; then
            log_warn "Broker tidak terdeteksi listen di $BACKEND_HOST:$BACKEND_PORT."
            log_warn "Koneksi mqtts akan gagal walau TLS-nya benar. Pastikan broker"
            log_warn "(Mosquitto) listen plain di port itu (default Mosquitto = 1883)."
            log_info "Cek broker: sudo ss -ltnp | grep mosquitto"
            echo ""
        fi
        if [[ "$_tls_state" != "LISTEN" ]]; then
            log_warn "Port $TLS_PORT belum listen. Pastikan blok stream{} ter-include:"
            log_info "  sudo nginx -T 2>/dev/null | grep -n 'streams-enabled'"
            echo ""
        fi
        echo "  Uji koneksi (butuh mosquitto-clients):"
        echo "    mosquitto_pub -h $MQTT_DOMAIN -p $TLS_PORT --capath /etc/ssl/certs \\"
        echo "                  -t test -m hello"
        echo -e "${CYAN}============================================================${NC}"
    else
        log_err "Nginx config error! Output 'nginx -t':"
        echo "$_test_out" | sed 's/^/     /'
        echo ""
        # Rollback: nonaktifkan stream ini agar konfigurasi Nginx tetap valid
        sudo rm -f "$STREAMS_ENABLED/mqtt-${slug}.conf"
        log_warn "Stream dinonaktifkan (symlink streams-enabled dihapus)."
        log_info "File config tetap ada di: $conf (+ backup ${conf}.bak.*)"
        log_info "Perbaiki penyebab di atas, lalu jalankan menu ini lagi."
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# MENU 3: SETUP / REFRESH AUTO-RENEW DEPLOY-HOOK
# ================================================================
nx_setup_renew_hook() {
    clear
    echo -e "${CYAN}--- AUTO-RENEW DEPLOY-HOOK ---${NC}"
    echo -e "   ${YELLOW}Reload Nginx (& Mosquitto) otomatis tiap sertifikat utama diperbarui.${NC}"
    echo ""
    echo "   Nginx membaca cert langsung dari /etc/letsencrypt/live/, jadi saat"
    echo "   certbot renew berhasil, hook ini cukup me-reload service terkait."
    echo ""

    confirm "Pasang/replace deploy-hook di $RENEW_HOOK?" \
        || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    sudo mkdir -p "$RENEW_HOOK_DIR"
    sudo tee "$RENEW_HOOK" > /dev/null << 'HOOKEOF'
#!/bin/bash
# Auto-generated by setup-server (nginx-extra).
# Dijalankan certbot SETELAH sertifikat berhasil diperbarui.
# Reload service yang memakai sertifikat utama Let's Encrypt.

log() { logger -t certbot-deploy-hook "$*"; echo "[deploy-hook] $*"; }

if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
        systemctl reload nginx && log "nginx reloaded"
    else
        log "nginx config test gagal, reload dilewati"
    fi
fi

if systemctl is-active --quiet mosquitto 2>/dev/null; then
    systemctl reload mosquitto 2>/dev/null \
        || systemctl restart mosquitto 2>/dev/null
    log "mosquitto reloaded/restarted"
fi

exit 0
HOOKEOF

    sudo chmod +x "$RENEW_HOOK"
    log_ok "Deploy-hook dipasang: $RENEW_HOOK"

    echo ""
    if systemctl list-timers 2>/dev/null | grep -q certbot; then
        log_ok "Timer certbot aktif (renew otomatis terjadwal)."
    elif systemctl list-unit-files 2>/dev/null | grep -q 'certbot.timer'; then
        sudo systemctl enable --now certbot.timer &>/dev/null \
            && log_ok "certbot.timer diaktifkan." \
            || log_warn "Gagal enable certbot.timer. Cek manual."
    else
        log_warn "Timer certbot tidak ditemukan. Pastikan certbot terpasang via apt/snap."
    fi

    echo ""
    log_info "Uji tanpa mengubah apa pun: sudo certbot renew --dry-run --run-deploy-hooks"
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# MENU 4: LIST KONFIGURASI
# ================================================================
nx_list() {
    clear
    echo -e "${CYAN}--- DAFTAR KONFIGURASI NGINX EXTRA ---${NC}"
    echo ""

    echo -e "   ${CYAN}WSS / HTTPS sites (sites-enabled):${NC}"
    local any=0
    for f in "$SITES_ENABLED"/*; do
        [[ -e "$f" ]] || continue
        local n; n=$(basename "$f")
        [[ "$n" == "default" ]] && continue
        if grep -q 'Upgrade' "$f" 2>/dev/null && grep -q 'listen 443' "$f" 2>/dev/null; then
            echo "     - $n"
            any=1
        fi
    done
    [[ $any -eq 0 ]] && echo "     (tidak ada site WSS terdeteksi)"

    echo ""
    echo -e "   ${CYAN}MQTT TLS streams (streams-enabled):${NC}"
    any=0
    for f in "$STREAMS_ENABLED"/*; do
        [[ -e "$f" ]] || continue
        local n; n=$(basename "$f")
        local lp; lp=$(grep -oP '(?<=listen )\d+' "$f" 2>/dev/null | head -1)
        local pp; pp=$(grep -oP '(?<=proxy_pass )\S+' "$f" 2>/dev/null | head -1 | tr -d ';')
        echo "     - $n  (listen $lp -> $pp)"
        any=1
    done
    [[ $any -eq 0 ]] && echo "     (tidak ada stream MQTT terdeteksi)"

    echo ""
    echo -e "   ${CYAN}Auto-renew deploy-hook:${NC}"
    if [[ -f "$RENEW_HOOK" ]]; then
        echo -e "     ${GREEN}terpasang${NC}: $RENEW_HOOK"
    else
        echo -e "     ${YELLOW}belum dipasang${NC}"
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# MENU 5: HAPUS KONFIGURASI
# ================================================================
nx_delete() {
    clear
    echo -e "${RED}--- HAPUS KONFIGURASI NGINX EXTRA ---${NC}"
    echo ""
    echo "   [1] Hapus stream MQTT TLS"
    echo "   [2] Hapus site WSS"
    echo "   [3] Kembali"
    echo ""
    read -rp "   Pilih [1/2/3]: " DEL_CH

    case "$DEL_CH" in
        1)
            local streams=()
            for f in "$STREAMS_ENABLED"/*; do [[ -e "$f" ]] && streams+=("$f"); done
            if [[ ${#streams[@]} -eq 0 ]]; then
                log_warn "Tidak ada stream MQTT."; read -rp "   Enter untuk kembali..." _; return
            fi
            for i in "${!streams[@]}"; do echo "     [$i] $(basename "${streams[$i]}")"; done
            read -rp "   Nomor yang dihapus: " s
            if [[ "$s" =~ ^[0-9]+$ && "$s" -lt ${#streams[@]} ]]; then
                local name; name=$(basename "${streams[$s]}")
                confirm "Hapus stream '$name'?" || return
                sudo rm -f "$STREAMS_ENABLED/$name" "$STREAMS_AVAILABLE/$name"
                sudo nginx -t &>/dev/null && sudo systemctl reload nginx
                log_ok "Stream '$name' dihapus & Nginx direload."
            else
                log_err "Pilihan tidak valid."
            fi
            ;;
        2)
            read -rp "   Domain WSS yang dihapus: " d
            [[ -z "$d" ]] && return
            confirm "Hapus site '$d'?" || return
            sudo rm -f "$SITES_ENABLED/$d" "$SITES_AVAILABLE/$d"
            sudo nginx -t &>/dev/null && sudo systemctl reload nginx
            log_ok "Site '$d' dihapus & Nginx direload."
            ;;
        *)
            return ;;
    esac

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# MENU UTAMA MODUL
# ================================================================
show_nginx_extra_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         NGINX EXTRA - WSS + MQTT TLS + AUTO-RENEW             ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo " 1. Setup WSS Reverse Proxy (domain existing / domain baru)"
    echo " 2. Setup MQTT TLS (Nginx stream termination)"
    echo " 3. Setup/Refresh Auto-Renew Deploy-Hook"
    echo " 4. List Konfigurasi"
    echo " 5. Hapus Konfigurasi"
    echo " 6. Kembali ke menu utama"
    echo -e "${CYAN}================================================================${NC}"
}

nginx_extra_main() {
    while true; do
        show_nginx_extra_menu
        read -rp "Pilih sub-menu (1-6): " CH
        echo ""
        case "$CH" in
            1) nx_setup_wss ;;
            2) nx_setup_mqtt_tls ;;
            3) nx_setup_renew_hook ;;
            4) nx_list ;;
            5) nx_delete ;;
            6) return ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

# Jalankan hanya jika file ini dieksekusi langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${YELLOW}Script membutuhkan root. Menjalankan ulang dengan sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi
    nginx_extra_main
fi
