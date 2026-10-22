#!/bin/bash
# ============================================================
#  modules/mongodb/uninstall.sh — Uninstall & Purge MongoDB
# ============================================================
[[ -n "${_MONGODB_UNINSTALL_LOADED:-}" ]] && return 0
_MONGODB_UNINSTALL_LOADED=1

uninstall_mongodb() {
    show_banner
    echo -e "${BLD}  Hapus/Uninstall MongoDB${NC}"; line; echo

    if ! command -v mongod &>/dev/null && [[ ! -f "$MONGOD_CONF" ]]; then
        warn "MongoDB sepertinya belum terinstall di server ini."
        pause; return 0
    fi

    warn "PERINGATAN: Ini akan menghapus service, package, config, dan repository APT"
    warn "MongoDB secara permanen dari server ini.\n"

    local del_data="" conf_word=""
    read -rp "  Hapus juga SELURUH DATA DATABASE di /var/lib/mongodb? [y/N]: " del_data
    echo
    read -rp "  Ketik 'HAPUS' untuk konfirmasi: " conf_word
    if [[ "$conf_word" != "HAPUS" ]]; then
        warn "Dibatalkan."
        pause; return 0
    fi

    echo
    info "Menghentikan & menonaktifkan service mongod..."
    sudo systemctl stop mongod 2>/dev/null
    sudo systemctl disable mongod 2>/dev/null

    info "Menghapus package MongoDB..."
    sudo apt-get purge -y 'mongodb-org*' 2>/dev/null
    sudo apt-get autoremove -y 2>/dev/null
    sudo apt-get autoclean 2>/dev/null

    info "Menghapus repository & GPG key APT..."
    sudo rm -f /etc/apt/sources.list.d/mongodb-org-*.list
    sudo rm -f /usr/share/keyrings/mongodb-server-*.gpg

    if [[ -f "$MONGOD_CONF" ]]; then
        local backup_conf="${MONGOD_CONF}.removed.$(date +%Y%m%d%H%M%S)"
        sudo cp "$MONGOD_CONF" "$backup_conf" 2>/dev/null
        info "Config lama di-backup ke: $backup_conf"
        sudo rm -f "$MONGOD_CONF"
    fi

    info "Menghapus keyFile & TLS PEM (jika ada)..."
    sudo rm -f /var/lib/mongodb/keyfile
    sudo rm -rf /etc/mongodb/tls

    if [[ -f /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh ]]; then
        sudo rm -f /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh
        info "Renewal hook TLS MongoDB dihapus."
    fi

    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        warn "Menghapus seluruh data database di /var/lib/mongodb dan log..."
        sudo rm -rf /var/lib/mongodb
        sudo rm -rf /var/log/mongodb
    else
        info "Data database di /var/lib/mongodb dipertahankan (tidak dihapus)."
    fi

    sudo systemctl daemon-reload

    echo; line
    success "MongoDB berhasil dihapus dari server."
    info "Jalankan menu '1. Setup MongoDB' untuk menginstal ulang dari awal."
    line; pause
}
