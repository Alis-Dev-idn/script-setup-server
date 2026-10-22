#!/bin/bash
# ============================================================
#  modules/nodejs-pm2/uninstall.sh — Configuration & Uninstall
# ============================================================
[[ -n "${_NODEJS_PM2_UNINSTALL_LOADED:-}" ]] && return 0
_NODEJS_PM2_UNINSTALL_LOADED=1

show_config_menu() {
    clear
    echo -e "${CYAN}--- KONFIGURASI ---${NC}\n"
    echo "  Konfigurasi saat ini:"
    echo -e "  - Node.js major  : ${GREEN}${NODEJS_MAJOR}${NC}"
    echo -e "  - Config file    : ${GREEN}${CONF_FILE}${NC}\n"

    echo "  1) Pilih versi Node.js default (untuk install baru)"
    echo "  2) Setup alias/shortcut"
    echo "  3) Setup PM2 startup (systemd)"
    echo "  4) Hapus Node.js & PM2 (uninstall total)"
    echo "  5) Kembali\n"

    local cfg_choice=""
    read -rp "Pilihan (1-5): " cfg_choice
    case "$cfg_choice" in
        1) _select_default_node_major ;;
        2) _setup_node_aliases ;;
        3) _setup_pm2_startup ;;
        4) _uninstall_nodejs_pm2 ;;
        5|"") return 0 ;;
        *) error "Pilihan tidak valid."; sleep 1 ;;
    esac
    echo ""; pause
}

_select_default_node_major() {
    echo -e "\nDefault Node.js version untuk install baru:\n  1) Node.js 18\n  2) Node.js 20\n  3) Node.js 22\n"
    local default_ver="2"
    read -rp "Pilihan (1-3): " default_ver
    case "$default_ver" in
        1) NODEJS_MAJOR=18 ;;
        2) NODEJS_MAJOR=20 ;;
        3) NODEJS_MAJOR=22 ;;
        *) error "Pilihan tidak valid."; sleep 1; return 1 ;;
    esac
    save_conf
}

_setup_node_aliases() {
    echo -e "\n"
    info "Membuat alias shortcut shell..."
    local shell_rc="$HOME/.bashrc"
    [[ "$SHELL" == *"zsh"* ]] && shell_rc="$HOME/.zshrc"

    local aliases=(
        "alias pm2logs='pm2 logs --lines 100'"
        "alias pm2list='pm2 list'"
        "alias pm2monit='pm2 monit'"
        "alias nodever='node --version && npm --version'"
    )

    local alias_line=""
    for alias_line in "${aliases[@]}"; do
        if ! grep -qF "$alias_line" "$shell_rc" 2>/dev/null; then
            echo "$alias_line" >> "$shell_rc"
            echo -e "  ${GREEN}+${NC} $alias_line"
        fi
    done
    success "Alias ditambahkan ke $shell_rc"
}

_setup_pm2_startup() {
    echo -e "\n"
    if ! cmd_exists pm2; then error "PM2 belum terinstall!"; return 1; fi
    info "Mengkonfigurasi PM2 startup (systemd)..."
    pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null || true
    pm2 save 2>/dev/null || true
    success "PM2 startup systemd berhasil dikonfigurasi!"
}

_uninstall_nodejs_pm2() {
    echo -e "\n"
    warn "HAPUS TOTAL Node.js & PM2"
    confirm "Apakah kamu yakin? Ini akan menghapus Node.js, npm, dan PM2!" || return 0

    if cmd_exists pm2; then
        info "Menghentikan semua aplikasi PM2..."
        pm2 kill 2>/dev/null || true
        sudo npm uninstall -g pm2 2>/dev/null || true
        pm2 unstartup systemd 2>/dev/null || true
        success "PM2 dihapus."
    fi

    if cmd_exists node; then
        info "Menghapus Node.js & npm..."
        sudo apt-get purge -y nodejs npm 2>/dev/null
        sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg 2>/dev/null
        sudo apt-get autoremove -y 2>/dev/null
        sudo apt-get autoclean 2>/dev/null
        success "Node.js & npm dihapus."
    fi

    rm -f "$CONF_FILE" 2>/dev/null
    success "Node.js & PM2 berhasil dihapus total!"
}
