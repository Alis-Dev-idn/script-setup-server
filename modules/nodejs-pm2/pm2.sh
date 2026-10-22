#!/bin/bash
# ============================================================
#  modules/nodejs-pm2/pm2.sh — Global PM2 Management
# ============================================================
[[ -n "${_NODEJS_PM2_PM2_LOADED:-}" ]] && return 0
_NODEJS_PM2_PM2_LOADED=1

get_installed_pm2_version() {
    if cmd_exists pm2; then
        pm2 --version 2>/dev/null | head -1
    fi
}

install_pm2() {
    clear
    echo -e "${CYAN}--- INSTALL / REINSTALL PM2 ---${NC}\n"

    if ! cmd_exists node; then
        warn "Node.js belum terinstall!"
        local inst_node=""
        read -rp "Install Node.js v20 terlebih dahulu? (y/n): " inst_node
        if [[ "$inst_node" =~ ^[Yy]$ ]]; then
            NODEJS_MAJOR=20
            install_nodejs
        else
            error "Node.js dibutuhkan untuk PM2. Batal."
            pause; return 1
        fi
        cmd_exists node || { error "Node.js belum siap. PM2 dibatalkan."; pause; return 1; }
    fi

    info "Node.js: $(node --version)  |  npm: $(npm --version)\n"

    if cmd_exists pm2; then
        local old_ver; old_ver="$(get_installed_pm2_version)"
        warn "PM2 v$old_ver sudah terinstall, reinstalling..."
        sudo npm uninstall -g pm2 2>/dev/null || true
    fi

    confirm "Install PM2 secara global via npm?" || return 0
    echo -e "\n"
    info "Menginstall PM2 secara global..."

    if command -v ui_run_task &>/dev/null; then
        ui_run_task "Pemasangan PM2 via npm" sudo npm install -g pm2
    else
        sudo npm install -g pm2
    fi

    info "Mengkonfigurasi PM2 startup hook..."
    pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null || true

    if cmd_exists pm2; then
        local pm2_ver; pm2_ver="$(get_installed_pm2_version)"
        echo -e "\n"; success "PM2 v${pm2_ver} berhasil diinstall!"
        info "Contoh: pm2 start app.js --name myapp | pm2 save | pm2 list"
    else
        error "Instalasi PM2 gagal!"; pause; return 1
    fi

    save_conf
    echo ""; pause
}

update_pm2() {
    clear
    echo -e "${CYAN}--- UPDATE PM2 & PROSES ---${NC}\n"
    if ! cmd_exists pm2; then warn "PM2 belum terinstall!"; pause; return 0; fi

    local current_ver; current_ver="$(get_installed_pm2_version)"
    info "PM2 saat ini: v${current_ver}\n"

    echo "Pilihan update:"
    echo "  1) Update PM2 ke versi terbaru"
    echo "  2) Restart semua aplikasi PM2"
    echo "  3) Reload semua aplikasi PM2 (zero-downtime)"
    echo "  4) Kembali\n"

    local update_choice=""
    read -rp "Pilihan (1-4): " update_choice
    case "$update_choice" in
        1)
            confirm "Update PM2 dari npm?" || return 0
            sudo npm install -g pm2@latest && pm2 update 2>/dev/null
            local new_ver; new_ver="$(get_installed_pm2_version)"
            success "PM2 diupdate dari v${current_ver} ke v${new_ver}!"
            ;;
        2)
            _pm2_restart_all
            ;;
        3)
            _pm2_reload_all
            ;;
        4|"") return 0 ;;
        *) error "Pilihan tidak valid."; sleep 1; return 1 ;;
    esac
    echo ""; pause
}

_pm2_restart_all() {
    if ! pm2 list 2>/dev/null | grep -q "online\|errored\|stopped"; then
        warn "Tidak ada aplikasi yang berjalan di PM2."
        return 0
    fi
    confirm "Restart semua aplikasi PM2?" || return 0
    pm2 restart all 2>/dev/null && success "Semua aplikasi direstart!" || error "Sebagian aplikasi gagal direstart."
}

_pm2_reload_all() {
    if ! pm2 list 2>/dev/null | grep -q "online\|errored\|stopped"; then
        warn "Tidak ada aplikasi yang berjalan di PM2."
        return 0
    fi
    confirm "Reload semua aplikasi (zero-downtime)?" || return 0
    pm2 reload all 2>/dev/null && success "Semua aplikasi direload!" || error "Sebagian aplikasi gagal direload."
}
