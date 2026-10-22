#!/bin/bash
# ============================================================
#  modules/hosting/main.sh — Main Router Hosting Module
# ============================================================
[[ -n "${_HOSTING_MAIN_LOADED:-}" ]] && return 0
_HOSTING_MAIN_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Shared Libraries
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/cloudflare.sh
source "${REPO_ROOT}/lib/cloudflare.sh"
# shellcheck source=lib/ssl.sh
source "${REPO_ROOT}/lib/ssl.sh"

# Hosting Submodules
# shellcheck source=modules/hosting/deps.sh
source "${SCRIPT_DIR}/deps.sh"
# shellcheck source=modules/hosting/vsftpd.sh
source "${SCRIPT_DIR}/vsftpd.sh"
# shellcheck source=modules/hosting/site.sh
source "${SCRIPT_DIR}/site.sh"
# shellcheck source=modules/hosting/ssl.sh
source "${SCRIPT_DIR}/ssl.sh"

show_main_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         PANEL MANAJEMEN HOSTING LINUX                         ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo " 1. Cek & Install Dependensi"
    echo " 2. Setup Cloudflare API Token"
    echo " 3. Konfigurasi vsftpd Server (sekali saja)"
    echo " 4. Manage Website & FTP"
    echo " 5. Manage SSL"
    echo " 6. Keluar"
    echo -e "${CYAN}================================================================${NC}"
}

hosting_main() {
    local choice=""
    while true; do
        show_main_menu
        read -rp "Pilih menu (1-6): " choice
        echo ""
        case "$choice" in
            1) check_deps ;;
            2) setup_cloudflare_creds ;;
            3) setup_vsftpd_global ;;
            4) manage_menu ;;
            5) ssl_menu ;;
            6) echo -e "${GREEN}Keluar. Sampai jumpa!${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root "$@"
    hosting_main
fi
