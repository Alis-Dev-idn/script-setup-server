#!/bin/bash
# ============================================================
#  modules/mongodb/config.sh — Konfigurasi mongod.conf & Tuning
# ============================================================
[[ -n "${_MONGODB_CONFIG_LOADED:-}" ]] && return 0
_MONGODB_CONFIG_LOADED=1

setup_mongodb() {
    show_banner
    echo -e "${BLD}  [1] Setup MongoDB${NC}"
    line

    local mongo_ver="8" mongo_port="27017" mongo_auth="yes"
    local mongo_admin_user="mongoAdmin" mongo_admin_pass=""
    local mongo_bind="127.0.0.1" mongo_cache_gb="1" mongo_replset=""
    local mongo_tls="no" mongo_tls_pem="" mongo_tls_ca=""

    _prompt_mongo_options mongo_ver mongo_port mongo_auth mongo_admin_user mongo_admin_pass mongo_bind
    _prompt_mongo_cache mongo_cache_gb
    _prompt_mongo_replset mongo_replset
    _prompt_mongo_tls mongo_tls mongo_tls_pem mongo_tls_ca

    _show_setup_summary "$mongo_ver" "$mongo_port" "$mongo_auth" "$mongo_admin_user" "$mongo_bind" \
        "$mongo_cache_gb" "$mongo_replset" "$mongo_tls" "$mongo_tls_pem" "$mongo_tls_ca" || return 0

    install_mongodb_packages "$mongo_ver" || { pause; return 1; }

    local mongo_keyfile=""
    if [[ "$mongo_auth" == "yes" && -n "$mongo_replset" ]]; then
        info "Membuat keyFile untuk autentikasi internal replica set..."
        mongo_keyfile="/var/lib/mongodb/keyfile"
        sudo openssl rand -base64 756 | sudo tee "$mongo_keyfile" > /dev/null
        sudo chmod 400 "$mongo_keyfile"
        sudo chown mongodb:mongodb "$mongo_keyfile"
    fi

    _write_mongod_conf "$mongo_port" "$mongo_bind" "$mongo_cache_gb" "$mongo_auth" "$mongo_keyfile" \
        "$mongo_replset" "$mongo_tls" "$mongo_tls_pem" "$mongo_tls_ca"

    info "Mengaktifkan dan memulai layanan mongod..."
    sudo systemctl daemon-reload
    sudo systemctl enable mongod &>/dev/null
    sudo systemctl restart mongod &>/dev/null
    sleep 3

    if [[ "$mongo_auth" == "yes" ]]; then
        _init_mongo_auth "$mongo_port" "$mongo_admin_user" "$mongo_admin_pass"
    fi

    if [[ -n "$mongo_replset" ]]; then
        _init_mongo_replset "$mongo_port" "$mongo_auth" "$mongo_admin_user" "$mongo_admin_pass" "$mongo_replset"
    fi

    if ! systemctl is-active --quiet mongod; then
        echo; line; error "MongoDB GAGAL berjalan setelah konfigurasi diterapkan!"
        sudo systemctl status mongod --no-pager -l | tail -n 15
        line; pause; return 1
    fi

    [[ "$mongo_bind" == "0.0.0.0" ]] && command -v ufw &>/dev/null && {
        info "Membuka port $mongo_port di UFW..."
        sudo ufw allow "$mongo_port"/tcp &>/dev/null
    }

    _display_completion_banner "$mongo_ver" "$mongo_port" "$mongo_bind" "$mongo_cache_gb" \
        "$mongo_auth" "$mongo_admin_user" "$mongo_admin_pass" "$mongo_replset" "$mongo_keyfile" \
        "$mongo_tls" "$mongo_tls_pem" "$mongo_tls_ca"
}

_prompt_mongo_options() {
    local -n r_ver=$1 r_port=$2 r_auth=$3 r_user=$4 r_pass=$5 r_bind=$6
    echo; ask "Pilih versi MongoDB:"
    echo "    1) 8.x (Latest — direkomendasikan)"
    echo "    2) 7.x"
    local ver_c="1"
    read -rp "  Pilihan [1]: " ver_c
    [[ "$ver_c" == "2" ]] && r_ver="7" || r_ver="8"

    local p_in=""
    read -rp "  Port MongoDB [27017]: " p_in
    r_port="${p_in:-27017}"

    echo; ask "Aktifkan autentikasi (auth)?"
    echo "    1) Ya — direkomendasikan (production)"
    echo "    2) Tidak — tanpa password (development)"
    local auth_c="1"
    read -rp "  Pilihan [1]: " auth_c
    if [[ "$auth_c" == "2" ]]; then
        r_auth="no"
    else
        r_auth="yes"
        local u_in=""
        read -rp "  Username admin [mongoAdmin]: " u_in
        r_user="${u_in:-mongoAdmin}"
        local p1="" p2=""
        while true; do
            read -rsp "  Password admin: " p1; echo
            read -rsp "  Konfirmasi password: " p2; echo
            [[ "$p1" == "$p2" && -n "$p1" ]] && { r_pass="$p1"; break; }
            error "Password tidak cocok atau kosong, coba lagi."
        done
    fi

    echo; ask "Binding jaringan:"
    echo "    1) Lokal saja — 127.0.0.1 (aman, default)"
    echo "    2) Publik     — 0.0.0.0  (bisa diakses dari luar)"
    local net_c="1"
    read -rp "  Pilihan [1]: " net_c
    [[ "$net_c" == "2" ]] && r_bind="0.0.0.0" || r_bind="127.0.0.1"
}

_prompt_mongo_cache() {
    local -n r_cache=$1
    local total_ram_kb total_ram_gb rec_cache="1"
    total_ram_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null)
    if [[ -n "$total_ram_kb" && "$total_ram_kb" -gt 0 ]]; then
        total_ram_gb=$(awk -v kb="$total_ram_kb" 'BEGIN{printf "%.1f", kb/1024/1024}')
        rec_cache=$(awk -v kb="$total_ram_kb" 'BEGIN { gb = kb/1024/1024; rec = (gb - 1)/2; if (rec < 0.25) rec = 0.25; printf "%.2f", rec }')
        info "RAM server: ${total_ram_gb} GB, Rekomendasi WiredTiger cache: ${rec_cache} GB"
    fi
    local c_in=""
    read -rp "  Cache size WiredTiger dalam GB [${rec_cache}]: " c_in
    r_cache="${c_in:-$rec_cache}"
}

_prompt_mongo_replset() {
    local -n r_rs=$1
    echo; ask "Aktifkan Replica Set? (diperlukan untuk transactions & session rollback)"
    echo "    1) Tidak — standalone biasa (default)"
    echo "    2) Ya    — aktifkan replica set (support transactions)"
    local rs_c="1"
    read -rp "  Pilihan [1]: " rs_c
    if [[ "$rs_c" == "2" ]]; then
        local rs_in=""
        read -rp "  Nama replica set [rs0]: " rs_in
        r_rs="${rs_in:-rs0}"
    else
        r_rs=""
    fi
}

_prompt_mongo_tls() {
    local -n r_tls=$1 r_pem=$2 r_ca=$3
    detect_ssl_certs
    ask "Aktifkan TLS/SSL untuk koneksi MongoDB?"
    echo "    1) Tidak — tanpa TLS (default)"
    echo "    2) Ya    — enkripsi koneksi"
    local tls_c="1"
    read -rp "  Pilihan [1]: " tls_c
    if [[ "$tls_c" == "2" ]]; then
        r_tls="yes"
        _setup_tls_files r_pem r_ca
    else
        r_tls="no"
    fi
}

_setup_tls_files() {
    local -n ref_pem=$1 ref_ca=$2
    if [[ -n "$DETECTED_KEY" && "$DETECTED_CERT" == *"letsencrypt"* ]]; then
        ask "Let's Encrypt terdeteksi. Buat PEM gabungan otomatis di /etc/mongodb/tls/?"
        local le_auto="1"
        read -rp "  Pilihan [1=Ya, 2=Manual]: " le_auto
        if [[ "$le_auto" != "2" ]]; then
            sudo mkdir -p /etc/mongodb/tls
            sudo cat "$DETECTED_CERT" "$DETECTED_KEY" | sudo tee /etc/mongodb/tls/mongodb.pem > /dev/null
            sudo chmod 600 /etc/mongodb/tls/mongodb.pem
            sudo chown mongodb:mongodb /etc/mongodb/tls/mongodb.pem 2>/dev/null || true
            ref_pem="/etc/mongodb/tls/mongodb.pem"
            success "PEM gabungan dibuat: $ref_pem"
            _create_certbot_mongo_hook "$DETECTED_CERT"
            return 0
        fi
    fi
    local pem_in=""
    read -rp "  Path file PEM (cert+key gabungan): " pem_in
    ref_pem="$pem_in"
    local ca_in=""
    read -rp "  Path CA file (kosong = tidak pakai): " ca_in
    ref_ca="$ca_in"
}

_create_certbot_mongo_hook() {
    local det_cert="$1"
    local le_domain; le_domain=$(echo "$det_cert" | awk -F'/' '{print $6}')
    sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    sudo tee /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh > /dev/null <<HOOK
#!/bin/bash
DOMAIN="${le_domain}"
LE_CERT="/etc/letsencrypt/live/\${DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/\${DOMAIN}/privkey.pem"
MONGO_PEM="/etc/mongodb/tls/mongodb.pem"
cat "\${LE_CERT}" "\${LE_KEY}" > "\${MONGO_PEM}"
chmod 600 "\${MONGO_PEM}"
chown mongodb:mongodb "\${MONGO_PEM}" 2>/dev/null || true
systemctl restart mongod
echo "[\$(date)] MongoDB TLS cert diperbarui dari: \${DOMAIN}" >> /var/log/mongodb-tls-renew.log
HOOK
    sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh
    success "Renewal hook dibuat di /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh"
}

_show_setup_summary() {
    local ver="$1" port="$2" auth="$3" user="$4" bind="$5" cache="$6" rs="$7" tls="$8" pem="$9" ca="${10}"
    echo; line; echo -e "  ${BLD}Ringkasan instalasi:${NC}"
    echo "    Versi       : MongoDB $ver.x"
    echo "    Port        : $port"
    echo "    Auth        : $auth"
    [[ "$auth" == "yes" ]] && echo "    User        : $user"
    echo "    Bind IP     : $bind"
    echo "    Cache(heap) : ${cache} GB"
    [[ -n "$rs" ]] && echo "    Replica Set : $rs" || echo "    Replica Set : tidak"
    [[ "$tls" == "yes" ]] && echo "    TLS/SSL     : aktif ($pem)" || echo "    TLS/SSL     : tidak"
    line
    local conf=""
    read -rp "  Lanjutkan? [y/N]: " conf
    [[ "$conf" =~ ^[Yy]$ ]] || { warn "Dibatalkan."; pause; return 1; }
    return 0
}

_write_mongod_conf() {
    local port="$1" bind="$2" cache="$3" auth="$4" keyfile="$5" rs="$6" tls="$7" pem="$8" ca="$9"
    local auth_sec="" rs_sec="" tls_sec=""

    if [[ "$auth" == "yes" ]]; then
        auth_sec=$'\nsecurity:\n  authorization: enabled'
        [[ -n "$keyfile" ]] && auth_sec+=$'\n  keyFile: '"$keyfile"
    fi
    [[ -n "$rs" ]] && rs_sec=$'\nreplication:\n  replSetName: '"$rs"$''
    if [[ "$tls" == "yes" && -n "$pem" ]]; then
        tls_sec=$'\n  tls:\n    mode: requireTLS\n    certificateKeyFile: '"$pem"
        [[ -n "$ca" ]] && tls_sec+=$'\n    CAFile: '"$ca" || tls_sec+=$'\n    allowConnectionsWithoutCertificates: true'
    fi

    sudo tee /etc/mongod.conf > /dev/null <<MONGOCFG
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

storage:
  dbPath: /var/lib/mongodb
  wiredTiger:
    engineConfig:
      cacheSizeGB: ${cache}

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

net:
  port: ${port}
  bindIp: ${bind}
${tls_sec}
${auth_sec}
${rs_sec}
MONGOCFG
}

_init_mongo_auth() {
    local port="$1" admin_user="$2" admin_pass="$3"
    sudo sed -i 's/authorization: enabled/authorization: disabled/' /etc/mongod.conf
    sudo systemctl restart mongod; sleep 2
    run_with_spinner "Membuat user admin..." \
        mongosh --quiet --host 127.0.0.1 --port "$port" admin --eval "
        db.createUser({
            user: '$admin_user', pwd: '$admin_pass',
            roles: [
                { role: 'userAdminAnyDatabase', db: 'admin' },
                { role: 'readWriteAnyDatabase', db: 'admin' },
                { role: 'dbAdminAnyDatabase',   db: 'admin' },
                { role: 'clusterAdmin',         db: 'admin' }
            ]
        }); print('User admin dibuat.');
        "
    sudo sed -i 's/authorization: disabled/authorization: enabled/' /etc/mongod.conf
    sudo systemctl restart mongod; sleep 2
}

_init_mongo_replset() {
    local port="$1" auth="$2" admin_user="$3" admin_pass="$4" replset="$5"
    sleep 2
    local rs_args=(--quiet --host "127.0.0.1" --port "$port")
    if [[ "$auth" == "yes" ]]; then
        rs_args+=(-u "$admin_user" -p "$admin_pass" --authenticationDatabase admin)
    fi
    rs_args+=(admin --eval "
        rs.initiate({
            _id: '$replset',
            members: [{ _id: 0, host: '127.0.0.1:$port' }]
        });
        sleep(2000);
        print('Replica set status: ' + rs.status().ok);
    ")
    run_with_spinner "Menginisialisasi replica set '$replset'..." mongosh "${rs_args[@]}"
    success "Replica set '$replset' berhasil diinisialisasi."
}

_display_completion_banner() {
    local ver="$1" port="$2" bind="$3" cache="$4" auth="$5" user="$6" pass="$7" rs="$8" keyfile="$9" tls="${10}" pem="${11}" ca="${12}"
    local qs="" conn_str=""
    [[ -n "$rs" ]] && qs="?replicaSet=${rs}"
    [[ "$tls" == "yes" ]] && { [[ -n "$qs" ]] && qs+="&tls=true" || qs="?tls=true"; }

    if [[ "$auth" == "yes" ]]; then
        conn_str="mongodb://${user}:${pass}@127.0.0.1:${port}/admin${qs}"
    else
        conn_str="mongodb://127.0.0.1:${port}/${qs}"
    fi

    echo; line
    echo -e "${BLD}${GRN}  MongoDB Berhasil Diinstal!${NC}"
    echo -e "  Koneksi: ${CYN}${conn_str}${NC}"
    line; pause
}
