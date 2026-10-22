#!/bin/bash
# ============================================================
#  modules/nginx-extra/main.sh — Main Router Nginx Extra
# ============================================================
[[ -n "${_NGINX_EXTRA_MAIN_LOADED:-}" ]] && return 0
_NGINX_EXTRA_MAIN_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Shared Libraries
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/cloudflare.sh
source "${REPO_ROOT}/lib/cloudflare.sh"
# shellcheck source=lib/ssl.sh
source "${REPO_ROOT}/lib/ssl.sh"

NGINX_CONF="/etc/nginx/nginx.conf"
STREAMS_AVAILABLE="/etc/nginx/streams-available"
STREAMS_ENABLED="/etc/nginx/streams-enabled"
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
RENEW_HOOK_DIR="/etc/letsencrypt/renewal-hooks/deploy"
RENEW_HOOK="$RENEW_HOOK_DIR/reload-services.sh"

# Submodules
# shellcheck source=modules/nginx-extra/wss.sh
source "${SCRIPT_DIR}/wss.sh"
# shellcheck source=modules/nginx-extra/mqtt.sh
source "${SCRIPT_DIR}/mqtt.sh"
# shellcheck source=modules/nginx-extra/hook.sh
source "${SCRIPT_DIR}/hook.sh"
# shellcheck source=modules/nginx-extra/manage.sh
source "${SCRIPT_DIR}/manage.sh"

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
    local choice=""
    while true; do
        show_nginx_extra_menu
        read -rp "Pilih sub-menu (1-6): " choice
        echo ""
        case "$choice" in
            1) nx_setup_wss ;;
            2) nx_setup_mqtt_tls ;;
            3) nx_setup_renew_hook ;;
            4) nx_list ;;
            5) nx_delete ;;
            6) return 0 ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root "$@"
    nginx_extra_main
fi
