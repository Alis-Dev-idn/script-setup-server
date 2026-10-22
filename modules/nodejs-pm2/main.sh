#!/bin/bash
# ============================================================
#  modules/nodejs-pm2/main.sh — Main Router Node.js & PM2
# ============================================================
[[ -n "${_NODEJS_PM2_MAIN_LOADED:-}" ]] && return 0
_NODEJS_PM2_MAIN_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Shared Libraries
# shellcheck source=lib/common.sh
source "${REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/cloudflare.sh
source "${REPO_ROOT}/lib/cloudflare.sh"
# shellcheck source=lib/ssl.sh
source "${REPO_ROOT}/lib/ssl.sh"

CONF_FILE="$HOME/.nodejs_pm2_manager.conf"
NODEJS_MAJOR_DEFAULT=20

load_conf() {
    if [[ -f "$CONF_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONF_FILE"
    fi
    NODEJS_MAJOR="${NODEJS_MAJOR:-$NODEJS_MAJOR_DEFAULT}"
    PM2_INSTALL_DIR="${PM2_INSTALL_DIR:-$HOME}"
}

save_conf() {
    cat > "$CONF_FILE" <<CONF
# Node.js & PM2 Manager Config
NODEJS_MAJOR=${NODEJS_MAJOR}
PM2_INSTALL_DIR=${PM2_INSTALL_DIR}
CONF
    success "Konfigurasi tersimpan ke $CONF_FILE"
}

cmd_exists() {
    command -v "$1" &>/dev/null
}

# Submodules
# shellcheck source=modules/nodejs-pm2/nodejs.sh
source "${SCRIPT_DIR}/nodejs.sh"
# shellcheck source=modules/nodejs-pm2/pm2.sh
source "${SCRIPT_DIR}/pm2.sh"
# shellcheck source=modules/nodejs-pm2/app.sh
source "${SCRIPT_DIR}/app.sh"
# shellcheck source=modules/nodejs-pm2/uninstall.sh
source "${SCRIPT_DIR}/uninstall.sh"

_nodejs_show_banner() {
    clear
    echo -e "${BLD}${BLU}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     Node.js & PM2 Manager v1.1          ║"
    echo "  ║     Ubuntu / Debian                      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_status_summary() {
    local node_ver="-" pm2_ver="-"
    local node_status="${RED}✗ Not Installed${NC}"
    local pm2_status="${RED}✗ Not Installed${NC}"

    if cmd_exists node; then
        node_ver="$(get_installed_node_version)"
        node_status="${GREEN}✓ Installed${NC}"
    fi
    if cmd_exists pm2; then
        pm2_ver="$(get_installed_pm2_version)"
        pm2_status="${GREEN}✓ Installed${NC}"
    fi

    echo -e "  ${CYAN}┌─ Status Sistem ─────────────────────────┐${NC}"
    echo -e "  │ Node.js : ${node_status}  (v${node_ver:-N/A})"
    echo -e "  │ PM2     : ${pm2_status}  (v${pm2_ver:-N/A})"
    echo -e "  ${CYAN}└─────────────────────────────────────────┘${NC}\n"
}

show_detail_status() {
    clear
    echo -e "${CYAN}--- STATUS NODE.JS & PM2 ---${NC}\n"

    echo -e "${BLD}${CYAN}=== Node.js ===${NC}"
    if cmd_exists node; then
        success "Node.js installed: $(node --version 2>/dev/null)"
        echo -e "  npm  : ${GREEN}$(npm --version 2>/dev/null)${NC}"
        echo -e "  Path : $(which node 2>/dev/null)\n"
        info "Global packages:"
        npm list -g --depth=0 2>/dev/null | sed 's/^/  /'
    else
        error "Node.js tidak terinstall."
    fi
    echo ""

    echo -e "${BLD}${CYAN}=== PM2 ===${NC}"
    if cmd_exists pm2; then
        success "PM2 installed: v$(get_installed_pm2_version)"
        echo -e "  Path : $(which pm2 2>/dev/null)\n"
        info "Daftar aplikasi PM2:\n"
        pm2 list 2>/dev/null
    else
        error "PM2 tidak terinstall."
    fi
    echo ""

    echo -e "${BLD}${CYAN}=== Sistem ===${NC}"
    echo "  Uptime : $(uptime -p 2>/dev/null || uptime)"
    echo "  Load   : $(awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null)"
    echo "  RAM    :"
    free -h 2>/dev/null | sed 's/^/  /'
    echo ""; pause
}

show_menu() {
    _nodejs_show_banner
    show_status_summary
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
    echo " 1. Install / Reinstall Node.js"
    echo " 2. Install / Reinstall PM2"
    echo " 3. Update Node.js"
    echo " 4. Update PM2 & Process"
    echo " 5. Status Node.js & PM2"
    echo " 6. Manage Aplikasi (PM2)"
    echo " 7. Konfigurasi"
    echo " 8. Keluar"
    echo -e "${CYAN}════════════════════════════════════════════${NC}"
}

nodejs_pm2_main() {
    load_conf
    local choice=""
    while true; do
        show_menu
        read -rp "Pilih menu (1-8): " choice
        echo ""
        case "$choice" in
            1) install_nodejs ;;
            2) install_pm2 ;;
            3) update_nodejs ;;
            4) update_pm2 ;;
            5) show_detail_status ;;
            6) pm2_app_menu ;;
            7) show_config_menu ;;
            8) echo -e "${GREEN}Keluar. Sampai jumpa!${NC}"; exit 0 ;;
            *) error "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    require_root "$@"
    nodejs_pm2_main
fi
