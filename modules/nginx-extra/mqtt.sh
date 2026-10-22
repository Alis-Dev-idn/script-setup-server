#!/bin/bash
# ============================================================
#  modules/nginx-extra/mqtt.sh — MQTT TLS Stream Proxy
# ============================================================
[[ -n "${_NGINX_EXTRA_MQTT_LOADED:-}" ]] && return 0
_NGINX_EXTRA_MQTT_LOADED=1

DEFAULT_MQTT_TLS_PORT="8883"
DEFAULT_MQTT_BACKEND_HOST="127.0.0.1"
DEFAULT_MQTT_BACKEND_PORT="1883"

_ensure_stream_support() {
    sudo mkdir -p "$STREAMS_AVAILABLE" "$STREAMS_ENABLED"
    local v; v="$(nginx -V 2>&1)"
    local ok=0
    if grep -qE -- '--with-stream(=static)?([[:space:]]|$)' <<< "$v"; then
        ok=1
    elif grep -q -- '--with-stream=dynamic' <<< "$v" \
         && { ls /etc/nginx/modules-enabled/*stream*.conf &>/dev/null \
              || grep -rqs 'ngx_stream_module' /etc/nginx/modules-enabled/ 2>/dev/null; }; then
        ok=1
    fi

    if [[ $ok -eq 0 ]]; then
        log_warn "Modul Nginx 'stream' belum aktif."
        if confirm "Install & aktifkan libnginx-mod-stream sekarang?"; then
            sudo apt-get update -qq && sudo apt-get install -y libnginx-mod-stream &>/dev/null \
                && log_ok "libnginx-mod-stream terinstall." || { log_err "Gagal install libnginx-mod-stream."; return 1; }
        else
            return 1
        fi
    fi

    if ! grep -qE 'include\s+/etc/nginx/streams-enabled/\*\.conf;' "$NGINX_CONF"; then
        if grep -qE '^\s*stream\s*\{' "$NGINX_CONF"; then
            log_warn "Blok 'stream {' ada di $NGINX_CONF tapi belum include streams-enabled."
            return 1
        fi
        sudo cp "$NGINX_CONF" "${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        sudo tee -a "$NGINX_CONF" > /dev/null << 'EOF'

# --- ditambahkan oleh script-setup-server (nginx-extra) ---
stream {
    include /etc/nginx/streams-enabled/*.conf;
}
EOF
        log_ok "Blok stream{} + include ditambahkan ke nginx.conf."
    fi
    return 0
}

_require_cert() {
    local domain="$1"
    resolve_ssl_cert "$domain" || return 1
    if [[ -z "$SSL_CERT" || -z "$SSL_KEY" ]]; then
        log_err "Fitur ini butuh sertifikat TLS. Tidak ada cert yang dipilih."
        return 1
    fi
    if ! sudo test -f "$SSL_CERT" || ! sudo test -f "$SSL_KEY"; then
        log_err "File sertifikat tidak ditemukan: $SSL_CERT | $SSL_KEY"
        return 1
    fi
    return 0
}

nx_setup_mqtt_tls() {
    clear
    echo -e "${CYAN}--- SETUP MQTT TLS (Nginx Stream Termination) ---${NC}"
    echo -e "   ${YELLOW}TLS diterminasi Nginx, lalu di-forward plain ke broker lokal.${NC}\n"

    _ensure_stream_support || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    local mqtt_domain="" tls_port="" backend_host="" backend_port=""
    while true; do
        read -rp "   Domain untuk sertifikat (contoh: mqtt.example.com): " mqtt_domain
        [[ -n "$mqtt_domain" ]] && break; log_err "Domain tidak boleh kosong."
    done

    read -rp "   Port TLS publik (Enter = $DEFAULT_MQTT_TLS_PORT): " tls_port
    [[ -z "$tls_port" ]] && tls_port="$DEFAULT_MQTT_TLS_PORT"

    read -rp "   Host broker lokal (Enter = $DEFAULT_MQTT_BACKEND_HOST): " backend_host
    [[ -z "$backend_host" ]] && backend_host="$DEFAULT_MQTT_BACKEND_HOST"

    read -rp "   Port broker lokal plain (Enter = $DEFAULT_MQTT_BACKEND_PORT): " backend_port
    [[ -z "$backend_port" ]] && backend_port="$DEFAULT_MQTT_BACKEND_PORT"

    _require_cert "$mqtt_domain" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    echo -e "\n   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Cert domain : $mqtt_domain  |  Listen TLS: 0.0.0.0:$tls_port  |  Forward: $backend_host:$backend_port\n"
    confirm "Tulis konfigurasi stream MQTT TLS?" || { read -rp "   Tekan Enter..."; return 0; }

    local slug; slug=$(echo "$mqtt_domain" | tr '.' '_')
    local conf="$STREAMS_AVAILABLE/mqtt-${slug}.conf"
    [[ -f "$conf" ]] && sudo cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"

    sudo tee "$conf" > /dev/null << STREAMEOF
# MQTT over TLS (stream termination) - dikelola oleh script-setup-server
server {
    listen $tls_port ssl;
    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    proxy_pass            $backend_host:$backend_port;
    proxy_connect_timeout 5s;
    proxy_timeout         300s;
}
STREAMEOF

    sudo ln -sf "$conf" "$STREAMS_ENABLED/mqtt-${slug}.conf"
    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        command -v ufw &>/dev/null && sudo ufw allow "$tls_port/tcp" comment "MQTT TLS" &>/dev/null
        _display_mqtt_summary "$mqtt_domain" "$tls_port" "$backend_host" "$backend_port" "$conf"
    else
        log_err "Nginx config error! Rollback stream..."
        sudo rm -f "$STREAMS_ENABLED/mqtt-${slug}.conf"
    fi
    read -rp "   Tekan Enter untuk kembali..." _
}

_display_mqtt_summary() {
    local domain="$1" tls_port="$2" b_host="$3" b_port="$4" conf="$5"
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN} RINGKASAN - MQTT TLS BERHASIL DIBUAT                       ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo "  Cert domain : $domain"
    echo -e "  Endpoint    : ${GREEN}mqtts://$domain:$tls_port${NC}"
    echo "  Forward ke  : $b_host:$b_port (plain)"
    echo "  Config      : $conf"
    echo -e "${CYAN}============================================================${NC}\n"
}
