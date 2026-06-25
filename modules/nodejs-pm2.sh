#!/bin/bash
# ============================================================
#  Node.js & PM2 Manager — Install, Update, Manage Service
#  Kompatibel: Ubuntu 20.04 / 22.04 / 24.04
# ============================================================

# ---------- Library bersama ----------
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$_MODULE_DIR/../lib"
# shellcheck source=../lib/common.sh
source "$_LIB_DIR/common.sh"
# shellcheck source=../lib/cloudflare.sh
source "$_LIB_DIR/cloudflare.sh"
# shellcheck source=../lib/ssl.sh
source "$_LIB_DIR/ssl.sh"

# ---------- Konfigurasi ----------
CONF_FILE="$HOME/.nodejs_pm2_manager.conf"
NODEJS_MAJOR_DEFAULT=20  # LTS default

load_conf() {
    if [[ -f "$CONF_FILE" ]]; then
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

# ============================================================
#  HELPER
# ============================================================

# ---------- Distro Detection ----------
detect_ubuntu_version() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${VERSION_ID}"
    else
        echo "unknown"
    fi
}

# ---------- Cek apakah command tersedia ----------
cmd_exists() {
    command -v "$1" &>/dev/null
}

# ---------- Cek Node.js terinstall ----------
get_installed_node_version() {
    if cmd_exists node; then
        node --version 2>/dev/null | sed 's/^v//'
    fi
}

get_installed_node_major() {
    local ver
    ver="$(get_installed_node_version)"
    if [[ -n "$ver" ]]; then
        echo "${ver%%.*}"
    fi
}

# ---------- Cek PM2 terinstall ----------
get_installed_pm2_version() {
    if cmd_exists pm2; then
        pm2 --version 2>/dev/null | head -1
    fi
}

# ---------- Versi Node LTS tersedia ----------
get_available_lts_versions() {
    # Menggunakan NodeSource untuk list versi yang tersedia
    echo "18 20 22"
}

# ============================================================
#  MENU
# ============================================================

show_banner() {
    clear
    echo -e "${BLD}${BLU}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     Node.js & PM2 Manager v1.0          ║"
    echo "  ║     Ubuntu 20.04 / 22.04 / 24.04       ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

show_status_summary() {
    local node_ver="-" pm2_ver="-" node_status="${RED}✗ Not Installed${NC}" pm2_status="${RED}✗ Not Installed${NC}"

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
    echo -e "  ${CYAN}└─────────────────────────────────────────┘${NC}"
    echo ""
}

show_menu() {
    show_banner
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

# ============================================================
#  MENU 1: INSTALL NODE.JS
# ============================================================

install_nodejs() {
    clear
    echo -e "${CYAN}--- INSTALL / REINSTALL NODE.JS ---${NC}"
    echo ""

    # Deteksi versi Ubuntu
    local ubuntu_ver
    ubuntu_ver="$(detect_ubuntu_version)"
    info "Deteksi Ubuntu: $ubuntu_ver"

    # Tampilkan versi yang tersedia
    local available
    available="$(get_available_lts_versions)"
    echo ""
    info "Versi Node.js LTS yang tersedia:"
    echo "  1) Node.js 18  (LTS  - Maintenance, EOL April 2025)"
    echo "  2) Node.js 20  (LTS  - Active, EOL April 2026)"
    echo "  3) Node.js 22  (LTS  - Active, EOL April 2027)"
    echo ""

    local current_ver
    current_ver="$(get_installed_node_major)"
    if [[ -n "$current_ver" ]]; then
        info "Versi terinstall saat ini: v$current_ver"
    fi
    echo ""

    local ver_choice
    read -rp "Pilih versi (1-3, default: 2): " ver_choice
    case "$ver_choice" in
        1) NODEJS_MAJOR=18 ;;
        2|"") NODEJS_MAJOR=20 ;;
        3) NODEJS_MAJOR=22 ;;
        *)
            error "Pilihan tidak valid."
            sleep 1
            return
            ;;
    esac

    echo ""
    confirm "Install Node.js v${NODEJS_MAJOR}?" || return

    echo ""
    info "Memulai installasi Node.js v${NODEJS_MAJOR}..."

    # ---------- Hapus versi lama (jika ada) ----------
    if cmd_exists node; then
        local old_ver
        old_ver="$(get_installed_node_version)"
        warn "Node.js v$old_ver terinstall, menghapus..."
        if cmd_exists nvm; then
            # Jika pakai nvm
            export NVM_DIR="$HOME/.nvm"
            # shellcheck source=/dev/null
            [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
            nvm uninstall "$old_ver" 2>/dev/null
        else
            # Hapus via NodeSource
            sudo apt-get purge -y nodejs 2>/dev/null
        fi
        success "Versi lama dihapus"
    fi

    # ---------- Install via NodeSource ----------
    info "Menambahkan NodeSource repository untuk Node.js v${NODEJS_MAJOR}..."

    # Hapus repo lama
    sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null
    sudo rm -f /etc/apt/keyrings/nodesource.gpg 2>/dev/null

    # Import GPG key
    sudo mkdir -p /etc/apt/keyrings
    if ! sudo curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
         -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null; then
        error "Gagal mengunduh GPG key NodeSource!"
        return 1
    fi

    # Tambahkan repository
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODEJS_MAJOR}.x nodistro main" \
        | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

    # Install
    info "Menjalankan apt-get update..."
    if ! sudo apt-get update -y 2>/dev/null; then
        error "Gagal melakukan apt-get update!"
        return 1
    fi

    info "Menginstall Node.js v${NODEJS_MAJOR}..."
    if ! sudo apt-get install -y nodejs 2>/dev/null; then
        error "Gagal menginstall Node.js!"
        return 1
    fi

    # ---------- Verifikasi ----------
    if cmd_exists node && cmd_exists npm; then
        local node_ver npm_ver
        node_ver="$(node --version)"
        npm_ver="$(npm --version)"
        echo ""
        success "Node.js v${NODEJS_MAJOR} berhasil diinstall!"
        echo -e "  Node.js : ${GREEN}${node_ver}${NC}"
        echo -e "  npm     : ${GREEN}${npm_ver}${NC}"
    else
        error "Instalasi gagal! Node.js tidak ditemukan."
        return 1
    fi

    # Simpan konfigurasi
    save_conf

    echo ""
    info "Installasi selesai."
    pause
}

# ============================================================
#  MENU 2: INSTALL PM2
# ============================================================

install_pm2() {
    clear
    echo -e "${CYAN}--- INSTALL / REINSTALL PM2 ---${NC}"
    echo ""

    # Cek Node.js dulu
    if ! cmd_exists node; then
        warn "Node.js belum terinstall!"
        echo ""
        read -rp "Install Node.js v20 terlebih dahulu? (y/n): " install_node_first
        if [[ "$install_node_first" == "y" || "$install_node_first" == "Y" ]]; then
            NODEJS_MAJOR=20
            install_nodejs
        else
            error "Node.js dibutuhkan untuk PM2. Batal."
            pause
            return 1
        fi
    fi

    info "Node.js: $(node --version)  |  npm: $(npm --version)"
    echo ""

    # Hapus PM2 global lama (jika ada)
    if cmd_exists pm2; then
        local old_ver
        old_ver="$(get_installed_pm2_version)"
        warn "PM2 v$old_ver sudah terinstall, reinstalling..."
        sudo npm uninstall -g pm2 2>/dev/null
    fi

    confirm "Install PM2 secara global via npm?" || return

    echo ""
    info "Menginstall PM2 secara global..."

    if ! sudo npm install -g pm2 2>/dev/null; then
        error "Gagal menginstall PM2!"
        return 1
    fi

    # ---------- Setup Startup Hook ----------
    info "Mengkonfigurasi PM2 startup hook..."
    if cmd_exists pm2; then
        pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null || true
    fi

    # ---------- Verifikasi ----------
    if cmd_exists pm2; then
        local pm2_ver
        pm2_ver="$(get_installed_pm2_version)"
        echo ""
        success "PM2 v${pm2_ver} berhasil diinstall!"
        echo ""
        info "Beberapa command berguna:"
        echo -e "  pm2 start <script.js>          ${CYAN}# Jalankan aplikasi${NC}"
        echo -e "  pm2 start ecosystem.config.js   ${CYAN}# Jalankan dari config${NC}"
        echo -e "  pm2 save                        ${CYAN}# Simpan daftar aplikasi${NC}"
        echo -e "  pm2 list                        ${CYAN}# Lihat semua aplikasi${NC}"
    else
        error "Instalasi PM2 gagal!"
        return 1
    fi

    save_conf

    echo ""
    pause
}

# ============================================================
#  MENU 3: UPDATE NODE.JS
# ============================================================

update_nodejs() {
    clear
    echo -e "${CYAN}--- UPDATE NODE.JS ---${NC}"
    echo ""

    if ! cmd_exists node; then
        warn "Node.js belum terinstall!"
        pause
        return
    fi

    local current_ver
    current_ver="$(get_installed_node_version)"
    local current_major
    current_major="$(get_installed_node_major)"
    info "Versi saat ini: v${current_ver}"
    echo ""

    info "Pilihan update:"
    echo "  1) Update dalam major version yang sama (v${current_major}.x)"
    echo "  2) Upgrade ke versi LTS terbaru"
    echo "  3) Kembali"
    echo ""

    local update_choice
    read -rp "Pilihan (1-3): " update_choice
    case "$update_choice" in
        1)
            echo ""
            info "Mengupdate Node.js v${current_major}.x ke versi terbaru..."
            sudo apt-get update -y 2>/dev/null
            sudo apt-get install -y --only-upgrade nodejs 2>/dev/null
            ;;
        2)
            echo ""
            info "Versi LTS yang tersedia:"
            echo "  1) Node.js 18  (Maintenance)"
            echo "  2) Node.js 20  (Active)"
            echo "  3) Node.js 22  (Active)"
            echo ""
            local lts_choice
            read -rp "Pilih versi target (1-3): " lts_choice
            local new_major
            case "$lts_choice" in
                1) new_major=18 ;;
                2) new_major=20 ;;
                3) new_major=22 ;;
                *) error "Pilihan tidak valid."; sleep 1; return ;;
            esac

            if [[ "$new_major" -eq "$current_major" ]]; then
                warn "Sudah menggunakan Node.js v${current_major}. Update minor..."
                sudo apt-get update -y 2>/dev/null
                sudo apt-get install -y --only-upgrade nodejs 2>/dev/null
            else
                info "Mengupgrade dari Node.js v${current_major} ke v${new_major}..."
                confirm "Lanjutkan upgrade? (Node.js akan diganti)" || return

                # Ganti repo NodeSource
                sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null
                sudo mkdir -p /etc/apt/keyrings
                sudo curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
                    -o /etc/apt/keyrings/nodesource.gpg 2>/dev/null
                echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${new_major}.x nodistro main" \
                    | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
                sudo apt-get update -y 2>/dev/null
                sudo apt-get install -y --allow-downgrades nodejs 2>/dev/null
                NODEJS_MAJOR="$new_major"
                save_conf
            fi
            ;;
        3|"")
            return
            ;;
        *)
            error "Pilihan tidak valid."
            sleep 1
            return
            ;;
    esac

    # ---------- Verifikasi ----------
    if cmd_exists node; then
        local new_ver
        new_ver="$(get_installed_node_version)"
        echo ""
        success "Node.js berhasil diupdate!"
        echo -e "  Sebelum : ${YELLOW}v${current_ver}${NC}"
        echo -e "  Sesudah : ${GREEN}v${new_ver}${NC}"

        # Update npm juga
        info "Mengupdate npm..."
        sudo npm install -g npm@latest 2>/dev/null
        echo -e "  npm     : ${GREEN}$(npm --version)${NC}"
    else
        error "Update gagal! Node.js tidak ditemukan."
        return 1
    fi

    echo ""
    pause
}

# ============================================================
#  MENU 4: UPDATE PM2 & PROSES
# ============================================================

update_pm2() {
    clear
    echo -e "${CYAN}--- UPDATE PM2 & PROSES ---${NC}"
    echo ""

    if ! cmd_exists pm2; then
        warn "PM2 belum terinstall!"
        pause
        return
    fi

    local current_ver
    current_ver="$(get_installed_pm2_version)"
    info "PM2 saat ini: v${current_ver}"
    echo ""

    info "Pilihan update:"
    echo "  1) Update PM2 ke versi terbaru"
    echo "  2) Restart semua aplikasi PM2"
    echo "  3) Reload semua aplikasi PM2 (zero-downtime)"
    echo "  4) Kembali"
    echo ""

    local update_choice
    read -rp "Pilihan (1-4): " update_choice
    case "$update_choice" in
        1)
            echo ""
            info "Mengupdate PM2..."
            confirm "Update PM2 dari npm?" || return
            sudo npm install -g pm2@latest 2>/dev/null
            local new_ver
            new_ver="$(get_installed_pm2_version)"
            echo ""
            success "PM2 diupdate!"
            echo -e "  Sebelum : ${YELLOW}v${current_ver}${NC}"
            echo -e "  Sesudah : ${GREEN}v${new_ver}${NC}"

            # Update modules PM2 juga
            info "Mengupdate PM2 modules..."
            pm2 update 2>/dev/null
            success "PM2 modules diupdate"
            ;;
        2)
            echo ""
            if ! pm2 list 2>/dev/null | grep -q "online\|errored\|stopped"; then
                warn "Tidak ada aplikasi yang berjalan di PM2."
                pause
                return
            fi
            info "Restart semua aplikasi PM2..."
            confirm "Restart semua?" || return
            pm2 restart all 2>/dev/null
            success "Semua aplikasi direstart!"
            ;;
        3)
            echo ""
            if ! pm2 list 2>/dev/null | grep -q "online\|errored\|stopped"; then
                warn "Tidak ada aplikasi yang berjalan di PM2."
                pause
                return
            fi
            info "Reload semua aplikasi (zero-downtime)..."
            confirm "Reload semua?" || return
            pm2 reload all 2>/dev/null
            success "Semua aplikasi direload (zero-downtime)!"
            ;;
        4|"")
            return
            ;;
        *)
            error "Pilihan tidak valid."
            sleep 1
            return
            ;;
    esac

    echo ""
    pause
}

# ============================================================
#  MENU 5: STATUS NODE.JS & PM2
# ============================================================

show_detail_status() {
    clear
    echo -e "${CYAN}--- STATUS NODE.JS & PM2 ---${NC}"
    echo ""

    # ---------- Node.js Status ----------
    echo -e "${BLD}${CYAN}=== Node.js ===${NC}"
    if cmd_exists node; then
        local node_ver npm_ver npx_ver
        node_ver="$(node --version 2>/dev/null)"
        npm_ver="$(npm --version 2>/dev/null)"
        npx_ver="$(npx --version 2>/dev/null)"
        success "Node.js installed: ${node_ver}"
        echo -e "  npm  : ${GREEN}${npm_ver}${NC}"
        echo -e "  npx  : ${GREEN}${npx_ver}${NC}"
        echo -e "  Path : $(which node 2>/dev/null)"
        echo ""
        info "Global packages:"
        npm list -g --depth=0 2>/dev/null | sed 's/^/  /'
    else
        error "Node.js tidak terinstall."
    fi

    echo ""

    # ---------- PM2 Status ----------
    echo -e "${BLD}${CYAN}=== PM2 ===${NC}"
    if cmd_exists pm2; then
        local pm2_ver
        pm2_ver="$(get_installed_pm2_version)"
        success "PM2 installed: v${pm2_ver}"
        echo -e "  Path : $(which pm2 2>/dev/null)"
        echo ""
        info "Daftar aplikasi PM2:"
        echo ""
        pm2 list 2>/dev/null
        echo ""

        # PM2 System Info
        info "System info:"
        echo ""
        pm2 sysinfo 2>/dev/null || true
    else
        error "PM2 tidak terinstall."
    fi

    echo ""

    # ---------- System Resources ----------
    echo -e "${BLD}${CYAN}=== Sistem ===${NC}"
    local uptime_str load_str
    uptime_str="$(uptime -p 2>/dev/null || uptime)"
    load_str="$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')"
    echo "  Uptime : $uptime_str"
    echo "  Load   : $load_str"
    echo "  RAM    :"
    free -h 2>/dev/null | sed 's/^/  /'
    echo ""

    pause
}

# ============================================================
#  MENU 6: MANAGE APLIKASI PM2
# ============================================================

pm2_app_menu() {
    while true; do
        clear
        echo -e "${CYAN}--- MANAGE APLIKASI PM2 ---${NC}"
        echo ""
        if cmd_exists pm2; then
            pm2 list 2>/dev/null
        else
            error "PM2 belum terinstall!"
            pause
            return
        fi
        echo ""
        echo "  1) Start aplikasi baru"
        echo "  2) Stop aplikasi"
        echo "  3) Restart aplikasi"
        echo "  4) Delete aplikasi dari PM2"
        echo "  5) Lihat log aplikasi"
        echo "  6) Lihat detail aplikasi (monit)"
        echo "  7) Simpan daftar aplikasi (pm2 save)"
        echo "  8) Kembali"
        echo ""

        local app_choice
        read -rp "Pilihan (1-8): " app_choice
        case "$app_choice" in
            1)
                echo ""
                echo "  Format start:"
                echo "    pm2 start app.js --name myapp"
                echo "    pm2 start ecosystem.config.js"
                echo ""
                read -rp "  Masukkan command pm2 start: " start_cmd
                if [[ -n "$start_cmd" ]]; then
                    pm2 $start_cmd 2>/dev/null
                    echo ""
                    success "Aplikasi dimulai!"
                fi
                ;;
            2)
                echo ""
                read -rp "  Nama atau ID aplikasi yang akan di-stop: " stop_name
                if [[ -n "$stop_name" ]]; then
                    pm2 stop "$stop_name" 2>/dev/null
                    success "Aplikasi '$stop_name' di-stop."
                fi
                ;;
            3)
                echo ""
                read -rp "  Nama atau ID aplikasi yang akan direstart: " restart_name
                if [[ -n "$restart_name" ]]; then
                    pm2 restart "$restart_name" 2>/dev/null
                    success "Aplikasi '$restart_name' direstart."
                fi
                ;;
            4)
                echo ""
                read -rp "  Nama atau ID aplikasi yang akan dihapus: " del_name
                if [[ -n "$del_name" ]]; then
                    confirm "Hapus '$del_name' dari PM2?" || continue
                    pm2 delete "$del_name" 2>/dev/null
                    success "Aplikasi '$del_name' dihapus dari PM2."
                fi
                ;;
            5)
                echo ""
                read -rp "  Nama atau ID aplikasi: " log_name
                if [[ -n "$log_name" ]]; then
                    info "Menampilkan log (tekan Ctrl+C untuk keluar):"
                    pm2 logs "$log_name" --lines 50 --nostream 2>/dev/null
                    echo ""
                    echo -e "  ${YELLOW}Tip: Gunakan 'pm2 logs $log_name' untuk log real-time${NC}"
                fi
                ;;
            6)
                echo ""
                info "Memulai PM2 Monitor (tekan 'q' untuk keluar)..."
                pm2 monit 2>/dev/null
                ;;
            7)
                pm2 save 2>/dev/null
                success "Daftar aplikasi tersimpan! (akan otomatis restore saat reboot)"
                ;;
            8|"")
                return
                ;;
            *)
                error "Pilihan tidak valid."
                sleep 1
                ;;
        esac

        sleep 1
    done
}

# ============================================================
#  MENU 7: KONFIGURASI
# ============================================================

show_config_menu() {
    clear
    echo -e "${CYAN}--- KONFIGURASI ---${NC}"
    echo ""
    echo "  Konfigurasi saat ini:"
    echo -e "  - Node.js major  : ${GREEN}${NODEJS_MAJOR}${NC}"
    echo -e "  - Config file    : ${GREEN}${CONF_FILE}${NC}"
    echo ""

    echo "  1) Pilih versi Node.js default (untuk install baru)"
    echo "  2) Setup alias/shortcut"
    echo "  3) Setup PM2 startup (systemd)"
    echo "  4) Hapus Node.js & PM2 (uninstall total)"
    echo "  5) Kembali"
    echo ""

    local cfg_choice
    read -rp "Pilihan (1-5): " cfg_choice
    case "$cfg_choice" in
        1)
            echo ""
            info "Default Node.js version untuk install baru:"
            echo "  1) Node.js 18"
            echo "  2) Node.js 20"
            echo "  3) Node.js 22"
            echo ""
            read -rp "Pilihan (1-3): " default_ver
            case "$default_ver" in
                1) NODEJS_MAJOR=18 ;;
                2) NODEJS_MAJOR=20 ;;
                3) NODEJS_MAJOR=22 ;;
                *) error "Pilihan tidak valid."; sleep 1; return ;;
            esac
            save_conf
            ;;
        2)
            echo ""
            info "Membuat alias untuk command umum..."
            local shell_rc="$HOME/.bashrc"
            if [[ "$SHELL" == *"zsh"* ]]; then
                shell_rc="$HOME/.zshrc"
            fi

            local aliases=(
                "alias pm2logs='pm2 logs --lines 100'"
                "alias pm2list='pm2 list'"
                "alias pm2monit='pm2 monit'"
                "alias nodever='node --version && npm --version'"
            )

            for alias_line in "${aliases[@]}"; do
                if ! grep -qF "$alias_line" "$shell_rc" 2>/dev/null; then
                    echo "$alias_line" >> "$shell_rc"
                    echo -e "  ${GREEN}+${NC} $alias_line"
                else
                    echo -e "  ${YELLOW}= (sudah ada)${NC} $alias_line"
                fi
            done

            echo ""
            success "Alias ditambahkan ke $shell_rc"
            echo -e "  ${YELLOW}Restart shell atau jalankan: source $shell_rc${NC}"
            ;;
        3)
            echo ""
            if ! cmd_exists pm2; then
                error "PM2 belum terinstall!"
                sleep 1
                return
            fi
            info "Mengkonfigurasi PM2 startup (systemd)..."
            pm2 startup systemd -u "$USER" --hp "$HOME" 2>/dev/null
            pm2 save 2>/dev/null
            echo ""
            success "PM2 startup dikonfigurasi!"
            info "Sekarang setiap kali server reboot, PM2 akan otomatis menjalankan aplikasi yang tersimpan."
            ;;
        4)
            echo ""
            warn "HAPUS TOTAL Node.js & PM2"
            confirm "Apakah kamu yakin? Ini akan menghapus Node.js, npm, dan PM2!" || return
            echo ""

            # Hapus PM2 dulu
            if cmd_exists pm2; then
                info "Menghentikan semua aplikasi PM2..."
                pm2 kill 2>/dev/null
                sudo npm uninstall -g pm2 2>/dev/null
                pm2 unstartup systemd 2>/dev/null || true
                success "PM2 dihapus."
            fi

            # Hapus Node.js
            if cmd_exists node; then
                info "Menghapus Node.js..."
                sudo apt-get purge -y nodejs npm 2>/dev/null
                sudo rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null
                sudo rm -f /etc/apt/keyrings/nodesource.gpg 2>/dev/null
                sudo apt-get autoremove -y 2>/dev/null
                sudo apt-get autoclean 2>/dev/null
                success "Node.js & npm dihapus."
            fi

            # Bersihkan config
            rm -f "$CONF_FILE" 2>/dev/null

            echo ""
            success "Node.js & PM2 berhasil dihapus total!"
            ;;
        5|"")
            return
            ;;
        *)
            error "Pilihan tidak valid."
            sleep 1
            ;;
    esac

    echo ""
    pause
}

# ============================================================
#  MAIN LOOP
# ============================================================

nodejs_pm2_main() {
    load_conf

    while true; do
        show_menu
        read -rp "Pilih menu (1-8): " CHOICE
        echo ""
        case "$CHOICE" in
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

# Jalankan hanya jika file ini dieksekusi langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${YELLOW}Script membutuhkan root. Menjalankan ulang dengan sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi
    nodejs_pm2_main
fi
