#!/bin/bash
# ============================================================
#  Setup Server - Panel Terpadu
#  Menggabungkan modul Hosting (vsftpd+Nginx+SSL), MongoDB,
#  Node.js/PM2, & Nginx Extra
# ============================================================
_SELF="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    _SELF="$(readlink -f "$_SELF" 2>/dev/null || echo "$_SELF")"
fi
ROOT_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
export ROOT_DIR

# Shared Libraries
# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/cloudflare.sh
source "$ROOT_DIR/lib/cloudflare.sh"
# shellcheck source=lib/ssl.sh
source "$ROOT_DIR/lib/ssl.sh"

# Domain Modules (Router submodules)
# shellcheck source=modules/hosting/main.sh
source "$ROOT_DIR/modules/hosting/main.sh"
# shellcheck source=modules/mongodb/main.sh
source "$ROOT_DIR/modules/mongodb/main.sh"
# shellcheck source=modules/nodejs-pm2/main.sh
source "$ROOT_DIR/modules/nodejs-pm2/main.sh"
# shellcheck source=modules/nginx-extra/main.sh
source "$ROOT_DIR/modules/nginx-extra/main.sh"

server_main_menu() {
    local mod_choice=""
    while true; do
        clear
        if command -v ui_header &>/dev/null; then
            ui_header "SETUP SERVER - PANEL TERPADU"
        else
            echo -e "${CYAN}================================================================${NC}"
            echo -e "${CYAN}          SETUP SERVER - PANEL TERPADU                          ${NC}"
            echo -e "${CYAN}================================================================${NC}\n"
        fi

        echo "  [1]  Hosting Panel       (vsftpd + Nginx + SSL + Deploy User)"
        echo "  [2]  MongoDB Manager     (setup, user, DB, backup, service)"
        echo "  [3]  Node.js & PM2       (install, update, manage aplikasi)"
        echo "  [4]  Nginx Extra         (WSS + MQTT TLS + Auto-Renew)"
        echo "  [5]  Keluar"
        echo ""

        if command -v ui_prompt_choice &>/dev/null; then
            ui_prompt_choice "Pilih modul" 1 5 mod_choice
        else
            read -rp "Pilih modul (1-5): " mod_choice
        fi
        echo ""

        case "$mod_choice" in
            1) hosting_main ;;
            2) mongodb_main ;;
            3) nodejs_pm2_main ;;
            4) nginx_extra_main ;;
            5|0) echo -e "${GREEN}Keluar. Sampai jumpa!${NC}"; exit 0 ;;
            *) error "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root "$@"
    server_main_menu
fi
