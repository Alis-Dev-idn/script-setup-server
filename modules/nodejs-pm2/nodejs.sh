#!/bin/bash
# ============================================================
#  modules/nodejs-pm2/nodejs.sh — NodeSource Installer & Update
# ============================================================
[[ -n "${_NODEJS_PM2_NODEJS_LOADED:-}" ]] && return 0
_NODEJS_PM2_NODEJS_LOADED=1

detect_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        grep -oP '(?<=^VERSION_ID=).*' /etc/os-release | tr -d '"'
    else
        echo "unknown"
    fi
}

get_installed_node_version() {
    if cmd_exists node; then
        node --version 2>/dev/null | sed 's/^v//'
    fi
}

get_installed_node_major() {
    local ver=""
    ver="$(get_installed_node_version)"
    [[ -n "$ver" ]] && echo "${ver%%.*}"
}

get_available_lts_versions() {
    echo "18 20 22"
}

install_nodejs() {
    clear
    echo -e "${CYAN}--- INSTALL / REINSTALL NODE.JS ---${NC}\n"

    local ubuntu_ver="" current_ver="" ver_choice=""
    ubuntu_ver="$(detect_ubuntu_version)"
    info "Deteksi Ubuntu: $ubuntu_ver\n"

    info "Versi Node.js LTS yang tersedia:"
    echo "  1) Node.js 18  (LTS - Maintenance)"
    echo "  2) Node.js 20  (LTS - Active)"
    echo "  3) Node.js 22  (LTS - Active)\n"

    current_ver="$(get_installed_node_major)"
    [[ -n "$current_ver" ]] && info "Versi terinstall saat ini: v$current_ver\n"

    read -rp "Pilih versi (1-3, default: 2): " ver_choice
    case "$ver_choice" in
        1) NODEJS_MAJOR=18 ;;
        2|"") NODEJS_MAJOR=20 ;;
        3) NODEJS_MAJOR=22 ;;
        *) error "Pilihan tidak valid."; sleep 1; return 1 ;;
    esac

    confirm "Install Node.js v${NODEJS_MAJOR}?" || return 0
    echo -e "\n"
    info "Menyiapkan repositori NodeSource Node.js v${NODEJS_MAJOR}..."

    sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg 2>/dev/null
    sudo apt-get install -y curl gnupg 2>/dev/null
    sudo mkdir -p /etc/apt/keyrings

    if ! curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg; then
        error "Gagal mengunduh GPG key NodeSource!"
        pause; return 1
    fi

    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_MAJOR}.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    if command -v ui_run_task &>/dev/null; then
        ui_run_task "Update indeks repositori APT" sudo apt-get update -y
        ui_run_task "Menginstall Node.js v${NODEJS_MAJOR}" sudo apt-get install -y --allow-downgrades nodejs
    else
        sudo apt-get update -y
        sudo apt-get install -y --allow-downgrades nodejs
    fi

    if cmd_exists node && cmd_exists npm; then
        echo -e "\n"
        success "Node.js v${NODEJS_MAJOR} berhasil diinstall!"
        echo -e "  Node.js : ${GREEN}$(node --version)${NC}"
        echo -e "  npm     : ${GREEN}$(npm --version)${NC}"
    else
        error "Instalasi gagal! Node.js tidak ditemukan."
        pause; return 1
    fi

    save_conf
    echo ""; pause
}

update_nodejs() {
    clear
    echo -e "${CYAN}--- UPDATE NODE.JS ---${NC}\n"
    if ! cmd_exists node; then warn "Node.js belum terinstall!"; pause; return 0; fi

    local current_ver="" current_major="" update_choice=""
    current_ver="$(get_installed_node_version)"
    current_major="$(get_installed_node_major)"
    info "Versi saat ini: v${current_ver}\n"

    echo "Pilihan update:"
    echo "  1) Update dalam major version yang sama (v${current_major}.x)"
    echo "  2) Upgrade ke versi LTS terbaru"
    echo "  3) Kembali\n"
    read -rp "Pilihan (1-3): " update_choice

    case "$update_choice" in
        1)
            info "Mengupdate Node.js v${current_major}.x..."
            sudo apt-get update -y && sudo apt-get install -y --only-upgrade nodejs || { error "Gagal update!"; pause; return 1; }
            ;;
        2)
            _upgrade_nodejs_major "$current_major" || return 1
            ;;
        3|"") return 0 ;;
        *) error "Pilihan tidak valid."; sleep 1; return 1 ;;
    esac

    if cmd_exists node; then
        local new_ver; new_ver="$(get_installed_node_version)"
        echo -e "\n"; success "Node.js berhasil diupdate!"
        echo -e "  Sebelum : ${YELLOW}v${current_ver}${NC}\n  Sesudah : ${GREEN}v${new_ver}${NC}"
        sudo npm install -g npm@latest 2>/dev/null || true
    fi
    echo ""; pause
}

_upgrade_nodejs_major() {
    local current_major="$1"
    echo -e "\nVersi LTS yang tersedia:\n  1) Node.js 18\n  2) Node.js 20\n  3) Node.js 22\n"
    local lts_c="1" new_major=20
    read -rp "Pilih versi target (1-3): " lts_c
    case "$lts_c" in
        1) new_major=18 ;;
        2) new_major=20 ;;
        3) new_major=22 ;;
        *) error "Pilihan tidak valid."; sleep 1; return 1 ;;
    esac

    if [[ "$new_major" -eq "$current_major" ]]; then
        warn "Sudah menggunakan Node.js v${current_major}. Update minor..."
        sudo apt-get update -y && sudo apt-get install -y --only-upgrade nodejs
        return 0
    fi

    confirm "Lanjutkan upgrade ke v${new_major}?" || return 1
    sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg 2>/dev/null
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${new_major}.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
    sudo apt-get update -y && sudo apt-get install -y --allow-downgrades nodejs
    NODEJS_MAJOR="$new_major"
    save_conf
}
