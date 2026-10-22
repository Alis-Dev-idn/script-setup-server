#!/bin/bash
# ============================================================
#  modules/mongodb/service.sh — Service Control & Diagnostics
# ============================================================
[[ -n "${_MONGODB_SERVICE_LOADED:-}" ]] && return 0
_MONGODB_SERVICE_LOADED=1

_repair_mongo_config() {
    echo
    if [[ ! -f "$MONGOD_CONF" ]]; then
        error "File $MONGOD_CONF tidak ditemukan."
        pause; return 0
    fi

    local backup_conf="" changed="no"

    # 1) keyFile untuk auth + replica set
    local has_auth="no" has_rs="no" has_keyfile="no"
    grep -qE "^\s+authorization\s*:\s*enabled" "$MONGOD_CONF" 2>/dev/null && has_auth="yes"
    grep -qE "^\s+replSetName\s*:" "$MONGOD_CONF" 2>/dev/null && has_rs="yes"
    grep -qE "^\s+keyFile\s*:" "$MONGOD_CONF" 2>/dev/null && has_keyfile="yes"

    if [[ "$has_auth" == "yes" && "$has_rs" == "yes" && "$has_keyfile" != "yes" ]]; then
        warn "keyFile belum ada padahal auth + replica set aktif."
        backup_conf="$MONGOD_CONF.bak.$(date +%Y%m%d%H%M%S)"
        sudo cp "$MONGOD_CONF" "$backup_conf"
        info "Backup konfigurasi: $backup_conf"

        local keyfile_path="/var/lib/mongodb/keyfile"
        info "Membuat keyFile di $keyfile_path..."
        sudo openssl rand -base64 756 | sudo tee "$keyfile_path" > /dev/null
        sudo chmod 400 "$keyfile_path"
        sudo chown mongodb:mongodb "$keyfile_path"
        sudo sed -i "/^\s*authorization\s*:\s*enabled/a\\  keyFile: ${keyfile_path}" "$MONGOD_CONF"
        changed="yes"
    fi

    # 2) TLS tanpa chain of trust (CAFile)
    local has_tls="no" has_cafile="no" has_allow_no_cert="no"
    grep -qE "^\s+mode\s*:\s*requireTLS" "$MONGOD_CONF" 2>/dev/null && has_tls="yes"
    grep -qE "^\s+CAFile\s*:" "$MONGOD_CONF" 2>/dev/null && has_cafile="yes"
    grep -qE "^\s+allowConnectionsWithoutCertificates\s*:" "$MONGOD_CONF" 2>/dev/null && has_allow_no_cert="yes"

    if [[ "$has_tls" == "yes" && "$has_cafile" != "yes" && "$has_allow_no_cert" != "yes" ]]; then
        warn "TLS aktif tanpa CAFile — menambahkan allowConnectionsWithoutCertificates."
        if [[ -z "$backup_conf" ]]; then
            backup_conf="$MONGOD_CONF.bak.$(date +%Y%m%d%H%M%S)"
            sudo cp "$MONGOD_CONF" "$backup_conf"
            info "Backup konfigurasi: $backup_conf"
        fi
        sudo sed -i "/^\s*certificateKeyFile\s*:/a\\    allowConnectionsWithoutCertificates: true" "$MONGOD_CONF"
        changed="yes"
    fi

    if [[ "$changed" != "yes" ]]; then
        info "Tidak ditemukan masalah konfigurasi umum yang perlu diperbaiki."
        pause; return 0
    fi

    info "Merestart mongod..."
    sudo systemctl restart mongod; sleep 2
    if systemctl is-active --quiet mongod; then
        success "MongoDB berhasil direstart."
    else
        error "MongoDB masih gagal start. Log:"
        sudo systemctl status mongod --no-pager -l | tail -n 15
    fi
    pause
}

service_menu() {
    local svc_choice=""
    while true; do
        show_banner
        echo -e "${BLD}  [6] Service MongoDB${NC}"; line; echo

        local svc_status="STOPPED" svc_color="$RED" svc_since="" svc_pid="" svc_enabled=""
        if systemctl is-active --quiet mongod 2>/dev/null; then
            svc_status="RUNNING"; svc_color="$GRN"
        fi
        svc_since=$(systemctl show mongod --property=ActiveEnterTimestamp --value 2>/dev/null)
        svc_pid=$(systemctl show mongod --property=MainPID --value 2>/dev/null)
        svc_enabled=$(systemctl is-enabled mongod 2>/dev/null || echo "unknown")

        echo -e "  Status    : ${svc_color}${BLD}${svc_status}${NC}"
        echo    "  Enabled   : $svc_enabled"
        [[ -n "$svc_since" && "$svc_since" != "n/a" ]] && echo "  Since     : $svc_since"
        [[ -n "$svc_pid"   && "$svc_pid"   != "0"   ]] && echo "  PID       : $svc_pid"

        if [[ -f "$MONGOD_CONF" ]]; then
            local actual_port actual_bind actual_rs actual_cache
            actual_port=$(parse_mongod_conf "port"); actual_port="${actual_port:-27017}"
            actual_bind=$(parse_mongod_conf "bindIp"); actual_bind="${actual_bind:-127.0.0.1}"
            actual_rs=$(grep -E "^\s+replSetName\s*:" "$MONGOD_CONF" 2>/dev/null | awk -F':' '{gsub(/[[:space:]]/, "", $2); print $2}')
            actual_cache=$(parse_mongod_conf "cacheSizeGB")
            echo "  Port      : $actual_port  |  Bind IP: $actual_bind"
            [[ -n "$actual_rs" ]] && echo "  ReplicaSet: $actual_rs"
            [[ -n "$actual_cache" ]] && echo "  Cache(GB) : $actual_cache"
        fi

        echo; line; echo -e "  ${BLD}Pilih aksi:${NC}\n"
        echo "    1)  Lihat log terbaru (50 baris)"
        echo "    2)  Start"
        echo "    3)  Stop"
        echo "    4)  Restart"
        echo "    5)  Reload konfigurasi (tanpa restart)"
        echo "    6)  Perbaiki masalah konfigurasi umum (keyFile & TLS)"
        echo "    7)  Kembali ke menu utama\n"; line
        read -rp "  Pilihan [1-7]: " svc_choice

        case "$svc_choice" in
            1)
                echo; info "Log terbaru MongoDB (/var/log/mongodb/mongod.log):"
                sudo tail -n 50 /var/log/mongodb/mongod.log 2>/dev/null || warn "Log tidak dapat dibaca."
                pause ;;
            2)
                systemctl is-active --quiet mongod && warn "MongoDB sudah berjalan." || {
                    info "Menjalankan MongoDB..."
                    sudo systemctl start mongod && success "MongoDB berhasil dijalankan." || error "Gagal start."
                }
                sleep 1 ;;
            3)
                if ! systemctl is-active --quiet mongod; then warn "MongoDB sudah berhenti."; else
                    local c=""
                    read -rp "  Hentikan MongoDB? [y/N]: " c
                    [[ "$c" =~ ^[Yy]$ ]] && { sudo systemctl stop mongod && success "MongoDB dihentikan." || error "Gagal stop."; }
                fi
                sleep 1 ;;
            4)
                info "Merestart MongoDB..."
                sudo systemctl restart mongod && success "MongoDB direstart." || error "Gagal restart."
                sleep 2 ;;
            5)
                info "Reload konfigurasi MongoDB (SIGHUP)..."
                sudo systemctl reload-or-restart mongod && success "Konfigurasi direload." || error "Gagal reload."
                sleep 1 ;;
            6) _repair_mongo_config ;;
            7) return 0 ;;
            *) warn "Pilihan tidak valid."; sleep 1 ;;
        esac
    done
}
