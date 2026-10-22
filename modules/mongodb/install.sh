#!/bin/bash
# ============================================================
#  modules/mongodb/install.sh — APT Repository & Package Installer
# ============================================================
[[ -n "${_MONGODB_INSTALL_LOADED:-}" ]] && return 0
_MONGODB_INSTALL_LOADED=1

install_mongodb_packages() {
    local mongo_ver="$1"
    info "Memperbarui paket sistem..."
    if command -v ui_run_task &>/dev/null; then
        ui_run_task "Update paket sistem" sudo apt-get update -y
        ui_run_task "Menginstal dependensi gnupg & curl" sudo apt-get install -y gnupg curl
    else
        sudo apt-get update -y
        sudo apt-get install -y gnupg curl
    fi

    info "Menambahkan GPG key MongoDB $mongo_ver.x..."
    curl -fsSL "https://www.mongodb.org/static/pgp/server-${mongo_ver}.0.asc" | \
        sudo gpg -o "/usr/share/keyrings/mongodb-server-${mongo_ver}.0.gpg" --dearmor --yes 2>/dev/null

    info "Menambahkan repository MongoDB $mongo_ver.x..."
    local codename=""
    if command -v lsb_release &>/dev/null; then
        codename=$(lsb_release -cs)
    else
        codename=$(grep -oP '(?<=VERSION_CODENAME=).*' /etc/os-release | tr -d '"')
    fi

    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${mongo_ver}.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/${mongo_ver}.0 multiverse" | \
        sudo tee "/etc/apt/sources.list.d/mongodb-org-${mongo_ver}.0.list" > /dev/null

    info "Menginstal paket mongodb-org..."
    if command -v ui_run_task &>/dev/null; then
        ui_run_task "Update repository MongoDB" sudo apt-get update -y
        ui_run_task "Pemasangan paket mongodb-org" sudo apt-get install -y mongodb-org
    else
        sudo apt-get update -y
        sudo apt-get install -y mongodb-org
    fi

    if command -v mongod &>/dev/null; then
        success "Paket MongoDB $mongo_ver.x berhasil diinstall."
        return 0
    else
        error "Instalasi MongoDB gagal. Periksa koneksi internet atau repository."
        return 1
    fi
}
