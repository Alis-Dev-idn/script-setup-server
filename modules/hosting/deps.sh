#!/bin/bash
# ============================================================
#  modules/hosting/deps.sh — Cek & Install Dependensi Hosting
# ============================================================
[[ -n "${_HOSTING_DEPS_LOADED:-}" ]] && return 0
_HOSTING_DEPS_LOADED=1

check_deps() {
    clear
    echo -e "${CYAN}--- CEK & INSTALL DEPENDENSI ---${NC}"
    echo ""

    local missing=()
    local bin=""
    local pkg=""
    local svc=""

    declare -A pkg_map=(
        ["vsftpd"]="vsftpd"
        ["nginx"]="nginx"
        ["certbot"]="certbot"
        ["setfacl"]="acl"
        ["openssl"]="openssl"
        ["ufw"]="ufw"
    )

    for bin in "${!pkg_map[@]}"; do
        if command -v "$bin" &>/dev/null; then
            log_ok "$bin sudah terinstall"
        else
            log_warn "$bin belum terinstall (package: ${pkg_map[$bin]})"
            missing+=("${pkg_map[$bin]}")
        fi
    done

    if python3 -c "import certbot_dns_cloudflare" &>/dev/null 2>&1; then
        log_ok "certbot-dns-cloudflare sudah terinstall"
    else
        log_warn "certbot-dns-cloudflare belum terinstall"
        missing+=("python3-certbot-dns-cloudflare")
    fi

    echo ""
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_ok "Semua dependensi sudah lengkap."
        read -rp "   Tekan Enter untuk kembali..." _
        return 0
    fi

    echo -e "   ${YELLOW}Package yang perlu diinstall:${NC}"
    for pkg in "${missing[@]}"; do
        echo "     - $pkg"
    done
    echo ""

    if confirm "Install semua sekarang?"; then
        echo ""
        if command -v ui_run_task &>/dev/null; then
            ui_run_task "Update indeks repositori APT" sudo apt-get update -qq
            for pkg in "${missing[@]}"; do
                ui_run_task "Menginstall paket $pkg" sudo apt-get install -y "$pkg"
            done
        else
            sudo apt-get update -qq
            for pkg in "${missing[@]}"; do
                log_info "Menginstall $pkg..."
                sudo apt-get install -y "$pkg" &>/dev/null \
                    && log_ok "$pkg berhasil diinstall." \
                    || log_err "Gagal install $pkg."
            done
        fi

        for svc in vsftpd nginx; do
            if command -v "$svc" &>/dev/null; then
                sudo systemctl enable "$svc" &>/dev/null
                sudo systemctl start  "$svc" &>/dev/null
            fi
        done
        log_ok "Instalasi dependensi selesai."
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
    return 0
}
