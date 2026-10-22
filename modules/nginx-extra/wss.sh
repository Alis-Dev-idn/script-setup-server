#!/bin/bash
# ============================================================
#  modules/nginx-extra/wss.sh — WSS Reverse Proxy Manager
# ============================================================
[[ -n "${_NGINX_EXTRA_WSS_LOADED:-}" ]] && return 0
_NGINX_EXTRA_WSS_LOADED=1

DEFAULT_WS_PORT="3001"
DEFAULT_WS_PATH="/ws"

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

nx_setup_wss() {
    clear
    echo -e "${CYAN}--- SETUP WSS REVERSE PROXY (Backend App) ---${NC}"
    echo -e "   ${YELLOW}Terminasi TLS di Nginx (443) lalu proxy ke ws:// app lokal.${NC}\n"
    echo "   Mode:"
    echo "   [1] Tambahkan path WSS ke domain yang SUDAH ADA  (wss://<domain>$DEFAULT_WS_PATH)"
    echo "   [2] Buat domain KHUSUS baru untuk WSS\n"
    local wss_mode="1"
    read -rp "   Pilih [1/2, default 1]: " wss_mode
    [[ -z "$wss_mode" ]] && wss_mode="1"

    case "$wss_mode" in
        1) _nx_wss_existing ;;
        2) _nx_wss_new ;;
        *) log_err "Pilihan tidak valid."; sleep 1 ;;
    esac
}

_nx_wss_existing() {
    echo ""
    local sites=() f="" n=""
    for f in "$SITES_AVAILABLE"/*; do
        [[ -f "$f" ]] || continue
        n=$(basename "$f")
        [[ "$n" == "default" ]] && continue
        grep -q "listen 443" "$f" 2>/dev/null && sites+=("$f")
    done

    if [[ ${#sites[@]} -eq 0 ]]; then
        log_warn "Tidak ada domain HTTPS (listen 443) yang bisa ditempeli WSS."
        read -rp "   Tekan Enter untuk kembali..." _; return 0
    fi

    echo "   Domain HTTPS yang tersedia:"
    local i=0
    for i in "${!sites[@]}"; do echo "     [$i] $(basename "${sites[$i]}")"; done
    local sel=""
    read -rp "   Pilih nomor domain: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ && "$sel" -lt ${#sites[@]} ]]; then
        log_err "Pilihan tidak valid."; read -rp "   Enter..."; return 0
    fi

    local conf="${sites[$sel]}"
    local domain; domain=$(grep -oP '(?<=server_name )[^;]+' "$conf" 2>/dev/null | head -1 | awk '{print $1}')
    [[ -z "$domain" ]] && domain="$(basename "$conf")"

    local ws_path="" ws_port=""
    read -rp "   Path WSS (Enter = $DEFAULT_WS_PATH): " ws_path
    [[ -z "$ws_path" ]] && ws_path="$DEFAULT_WS_PATH"
    [[ "$ws_path" != /* ]] && ws_path="/$ws_path"

    while true; do
        read -rp "   Port backend app lokal (Enter = $DEFAULT_WS_PORT): " ws_port
        [[ -z "$ws_port" ]] && ws_port="$DEFAULT_WS_PORT"
        [[ "$ws_port" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    if grep -qE "location[[:space:]]+$ws_path([[:space:]/]|\{)" "$conf" 2>/dev/null; then
        log_warn "Location '$ws_path' sudah ada di config."; read -rp "   Enter..."; return 0
    fi

    echo -e "\n   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain   : $domain  |  Endpoint : wss://$domain$ws_path  |  Backend: 127.0.0.1:$ws_port\n"
    confirm "Sisipkan blok WSS ke config ini?" || { read -rp "   Enter..."; return 0; }

    local block; block="$(_wss_location_block "$ws_path" "$ws_port")"
    _inject_location "$conf" "$block"

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        _nx_wss_resume "$domain" "$ws_path" "$ws_port" "$conf" "existing"
    else
        log_err "Nginx config error! Mengembalikan backup..."
        local last_bak; last_bak=$(ls -t "${conf}".bak.* 2>/dev/null | head -1)
        [[ -n "$last_bak" ]] && sudo cp "$last_bak" "$conf"
        read -rp "   Enter..." _
    fi
}

_nx_wss_new() {
    echo ""
    local wss_domain="" ws_port="" ws_path=""
    while true; do
        read -rp "   Domain WSS baru (contoh: ws.example.com): " wss_domain
        [[ -n "$wss_domain" ]] && break; log_err "Domain tidak boleh kosong."
    done

    read -rp "   Path WSS (Enter = /): " ws_path
    [[ -z "$ws_path" ]] && ws_path="/"
    [[ "$ws_path" != /* ]] && ws_path="/$ws_path"

    while true; do
        read -rp "   Port backend app lokal (Enter = $DEFAULT_WS_PORT): " ws_port
        [[ -z "$ws_port" ]] && ws_port="$DEFAULT_WS_PORT"
        [[ "$ws_port" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    _require_cert "$wss_domain" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    echo -e "\n   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain WSS : $wss_domain  |  Endpoint: wss://$wss_domain$ws_path  |  Backend: 127.0.0.1:$ws_port\n"
    confirm "Tulis konfigurasi Nginx WSS?" || { read -rp "   Enter..."; return 0; }

    local conf="$SITES_AVAILABLE/$wss_domain"
    [[ -f "$conf" ]] && sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"

    local block; block="$(_wss_location_block "$ws_path" "$ws_port")"
    sudo tee "$conf" > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $wss_domain;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $wss_domain;
    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
$block
}
NGINXEOF

    sudo ln -sf "$conf" "$SITES_ENABLED/$wss_domain"
    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        command -v ufw &>/dev/null && sudo ufw allow 443/tcp comment "HTTPS/WSS" &>/dev/null
        _nx_wss_resume "$wss_domain" "$ws_path" "$ws_port" "$conf" "new"
    else
        log_err "Nginx config error! Cek: sudo nginx -t"
        read -rp "   Enter..." _
    fi
}

_nx_wss_resume() {
    local domain="$1" path="$2" port="$3" conf="$4" mode="$5"
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN} RINGKASAN - WSS BERHASIL DIBUAT                            ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo "  Mode        : $([ "$mode" == "new" ] && echo "Domain khusus baru" || echo "Domain existing")"
    echo "  Domain      : $domain"
    echo -e "  Endpoint    : ${GREEN}wss://$domain$path${NC}"
    echo "  Backend app : http://127.0.0.1:$port"
    echo "  Config      : $conf"
    echo -e "${CYAN}============================================================${NC}\n"
    read -rp "   Tekan Enter untuk kembali..." _
}
