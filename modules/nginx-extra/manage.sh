#!/bin/bash
# ============================================================
#  modules/nginx-extra/manage.sh — List & Purge Configs
# ============================================================
[[ -n "${_NGINX_EXTRA_MANAGE_LOADED:-}" ]] && return 0
_NGINX_EXTRA_MANAGE_LOADED=1

nx_list() {
    clear
    echo -e "${CYAN}--- DAFTAR KONFIGURASI NGINX EXTRA ---${NC}\n"

    echo -e "   ${CYAN}WSS / HTTPS sites (sites-enabled):${NC}"
    local any=0 f="" n=""
    for f in "$SITES_ENABLED"/*; do
        [[ -e "$f" ]] || continue
        n=$(basename "$f")
        [[ "$n" == "default" ]] && continue
        if grep -q 'Upgrade' "$f" 2>/dev/null && grep -q 'listen 443' "$f" 2>/dev/null; then
            echo "     - $n"
            any=1
        fi
    done
    [[ $any -eq 0 ]] && echo "     (tidak ada site WSS terdeteksi)"

    echo -e "\n   ${CYAN}MQTT TLS streams (streams-enabled):${NC}"
    any=0
    for f in "$STREAMS_ENABLED"/*; do
        [[ -e "$f" ]] || continue
        n=$(basename "$f")
        local lp; lp=$(grep -oP '(?<=listen )\d+' "$f" 2>/dev/null | head -1)
        local pp; pp=$(grep -oP '(?<=proxy_pass )\S+' "$f" 2>/dev/null | head -1 | tr -d ';')
        echo "     - $n  (listen $lp -> $pp)"
        any=1
    done
    [[ $any -eq 0 ]] && echo "     (tidak ada stream MQTT terdeteksi)"

    echo -e "\n   ${CYAN}Auto-renew deploy-hook:${NC}"
    if [[ -f "$RENEW_HOOK" ]]; then
        echo -e "     ${GREEN}terpasang${NC}: $RENEW_HOOK"
    else
        echo -e "     ${YELLOW}belum dipasang${NC}"
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

nx_delete() {
    clear
    echo -e "${RED}--- HAPUS KONFIGURASI NGINX EXTRA ---${NC}\n"
    echo "   [1] Hapus stream MQTT TLS"
    echo "   [2] Hapus site WSS"
    echo "   [3] Kembali\n"
    local del_ch=""
    read -rp "   Pilih [1/2/3]: " del_ch

    case "$del_ch" in
        1)
            local streams=() f=""
            for f in "$STREAMS_ENABLED"/*; do [[ -e "$f" ]] && streams+=("$f"); done
            if [[ ${#streams[@]} -eq 0 ]]; then
                log_warn "Tidak ada stream MQTT."; read -rp "   Enter..."; return 0
            fi
            local i=0
            for i in "${!streams[@]}"; do echo "     [$i] $(basename "${streams[$i]}")"; done
            local s=""
            read -rp "   Nomor yang dihapus: " s
            if [[ "$s" =~ ^[0-9]+$ && "$s" -lt ${#streams[@]} ]]; then
                local name; name=$(basename "${streams[$s]}")
                confirm "Hapus stream '$name'?" || return 0
                sudo rm -f "$STREAMS_ENABLED/$name" "$STREAMS_AVAILABLE/$name"
                sudo nginx -t &>/dev/null && sudo systemctl reload nginx
                log_ok "Stream '$name' dihapus & Nginx direload."
            fi
            ;;
        2)
            local d=""
            read -rp "   Domain WSS yang dihapus: " d
            [[ -z "$d" ]] && return 0
            confirm "Hapus site '$d'?" || return 0
            sudo rm -f "$SITES_ENABLED/$d" "$SITES_AVAILABLE/$d"
            sudo nginx -t &>/dev/null && sudo systemctl reload nginx
            log_ok "Site '$d' dihapus & Nginx direload."
            ;;
        *) return 0 ;;
    esac
    echo ""; read -rp "   Tekan Enter untuk kembali..." _
}
