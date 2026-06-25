#!/bin/bash
# ============================================================
#  MongoDB Manager — Setup, User, Database, Backup, Restore
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

# ---------- Banner ----------
show_banner() {
  clear
  echo -e "${BLD}${BLU}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║         MongoDB Manager v1.1             ║"
  echo "  ║   Ubuntu 20.04 / 22.04 / 24.04           ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"
}

# ============================================================
# CONF — Tersimpan di: ~/.mongodb_manager.conf
#        Contoh path : /root/.mongodb_manager.conf  (jika root)
#                    : /home/namauser/.mongodb_manager.conf
# ============================================================
CONF_FILE="$HOME/.mongodb_manager.conf"

load_conf() {
  if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
  else
    MONGO_PORT=27017
    MONGO_HOST="127.0.0.1"
    MONGO_BIND="127.0.0.1"
    MONGO_ADMIN_USER=""
    MONGO_ADMIN_PASS=""
    MONGO_AUTH="yes"
    MONGO_REPLSET=""
  fi
  # pastikan variabel ada meski conf lama belum punya field ini
  # MONGO_HOST = host koneksi mongosh (selalu 127.0.0.1 untuk manajemen lokal)
  # MONGO_BIND = bindIp di mongod.conf (127.0.0.1 atau 0.0.0.0)
  MONGO_HOST="${MONGO_HOST:-127.0.0.1}"
  MONGO_BIND="${MONGO_BIND:-127.0.0.1}"
  MONGO_REPLSET="${MONGO_REPLSET:-}"
}

save_conf() {
  cat > "$CONF_FILE" <<EOF
MONGO_PORT=$MONGO_PORT
MONGO_HOST=$MONGO_HOST
MONGO_BIND=$MONGO_BIND
MONGO_ADMIN_USER=$MONGO_ADMIN_USER
MONGO_ADMIN_PASS=$MONGO_ADMIN_PASS
MONGO_AUTH=$MONGO_AUTH
MONGO_REPLSET=$MONGO_REPLSET
EOF
  chmod 600 "$CONF_FILE"
}

# ---------- Helper mongosh ----------
mongo_exec() {
  local SCRIPT="$1"
  local DB="${2:-admin}"
  if [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]]; then
    mongosh --quiet \
      --host "$MONGO_HOST" --port "$MONGO_PORT" \
      -u "$MONGO_ADMIN_USER" -p "$MONGO_ADMIN_PASS" \
      --authenticationDatabase admin \
      "$DB" --eval "$SCRIPT"
  else
    mongosh --quiet \
      --host "$MONGO_HOST" --port "$MONGO_PORT" \
      "$DB" --eval "$SCRIPT"
  fi
}

# ============================================================
# HELPER — Deteksi konfigurasi mongod.conf aktual
# ============================================================
MONGOD_CONF="/etc/mongod.conf"

parse_mongod_conf() {
  local KEY="$1"
  [[ ! -f "$MONGOD_CONF" ]] && echo "" && return
  grep -E "^\s+${KEY}\s*:" "$MONGOD_CONF" \
    | awk -F':' '{gsub(/[[:space:]]/, "", $2); print $2}' \
    | head -1
}

# detect_ssl_certs() dipindah ke lib/ssl.sh (dipakai bersama dengan hosting)

sync_from_mongod_conf() {
  local file_port file_bind
  file_port=$(parse_mongod_conf "port")
  file_bind=$(parse_mongod_conf "bindIp")
  RUNNING_PORT="${file_port:-27017}"
  RUNNING_BIND="${file_bind:-127.0.0.1}"
  if grep -qE "^\s+authorization\s*:\s*enabled" "$MONGOD_CONF" 2>/dev/null; then
    RUNNING_AUTH="yes"
  elif grep -qE "^\s+authorization\s*:\s*disabled" "$MONGOD_CONF" 2>/dev/null; then
    RUNNING_AUTH="no"
  else
    RUNNING_AUTH="$MONGO_AUTH"
  fi
}

detect_running_config() {
  load_conf
  if [[ ! -f "$MONGOD_CONF" ]]; then
    warn "File $MONGOD_CONF tidak ditemukan — menggunakan konfigurasi tersimpan."
    return
  fi
  sync_from_mongod_conf
  local changed=0
  if [[ "$RUNNING_PORT" != "$MONGO_PORT" ]]; then
    warn "Port berbeda!"
    echo "    Tersimpan ($CONF_FILE) : $MONGO_PORT"
    echo "    Aktual  ($MONGOD_CONF) : $RUNNING_PORT"
    changed=1
  fi
  if [[ "$RUNNING_BIND" != "$MONGO_BIND" ]]; then
    warn "Bind IP berbeda!"
    echo "    Tersimpan ($CONF_FILE) : $MONGO_BIND"
    echo "    Aktual  ($MONGOD_CONF) : $RUNNING_BIND"
    changed=1
  fi
  if [[ "$RUNNING_AUTH" != "$MONGO_AUTH" ]]; then
    warn "Status auth berbeda!"
    echo "    Tersimpan ($CONF_FILE) : $MONGO_AUTH"
    echo "    Aktual  ($MONGOD_CONF) : $RUNNING_AUTH"
    changed=1
  fi
  if [[ "$changed" -eq 1 ]]; then
    echo
    ask "Konfigurasi tersimpan BERBEDA dengan $MONGOD_CONF yang aktual."
    echo "    1) Gunakan konfigurasi dari mongod.conf (direkomendasikan)"
    echo "    2) Tetap gunakan konfigurasi tersimpan"
    read -rp "  Pilihan [1]: " sync_choice
    if [[ "$sync_choice" != "2" ]]; then
      MONGO_PORT="$RUNNING_PORT"
      MONGO_BIND="$RUNNING_BIND"
      MONGO_AUTH="$RUNNING_AUTH"
      if [[ "$MONGO_AUTH" == "yes" && -z "$MONGO_ADMIN_USER" ]]; then
        echo
        warn "Auth aktif tapi kredensial belum tersimpan."
        read -rp "  Username admin MongoDB: " MONGO_ADMIN_USER
        read -rsp "  Password admin MongoDB: " MONGO_ADMIN_PASS; echo
      fi
      save_conf
      success "Konfigurasi disinkronkan dari $MONGOD_CONF."
    else
      warn "Menggunakan konfigurasi tersimpan — pastikan MongoDB berjalan di port $MONGO_PORT."
    fi
  else
    info "Konfigurasi sesuai (port: $MONGO_PORT, bind: $MONGO_BIND, auth: $MONGO_AUTH)."
  fi
}

# ============================================================
# 1. SETUP MONGODB
# ============================================================
setup_mongodb() {
  show_banner
  echo -e "${BLD}  [1] Setup MongoDB${NC}"
  line

  echo; ask "Pilih versi MongoDB:"
  echo "    1) 8.x (Latest — direkomendasikan)"
  echo "    2) 7.x"
  read -rp "  Pilihan [1]: " ver_choice
  case "$ver_choice" in
    2) MONGO_VER="7" ;;
    *) MONGO_VER="8" ;;
  esac

  echo
  read -rp "  Port MongoDB [27017]: " input_port
  MONGO_PORT="${input_port:-27017}"

  echo
  ask "Aktifkan autentikasi (auth)?"
  echo "    1) Ya — direkomendasikan (production)"
  echo "    2) Tidak — tanpa password (development)"
  read -rp "  Pilihan [1]: " auth_choice
  if [[ "$auth_choice" == "2" ]]; then
    MONGO_AUTH="no"
  else
    MONGO_AUTH="yes"
    echo
    read -rp "  Username admin [mongoAdmin]: " input_user
    MONGO_ADMIN_USER="${input_user:-mongoAdmin}"
    while true; do
      read -rsp "  Password admin: " input_pass; echo
      read -rsp "  Konfirmasi password: " input_pass2; echo
      [[ "$input_pass" == "$input_pass2" ]] && break
      error "Password tidak cocok, coba lagi."
    done
    MONGO_ADMIN_PASS="$input_pass"
  fi

  echo
  ask "Binding jaringan:"
  echo "    1) Lokal saja — 127.0.0.1 (aman, default)"
  echo "    2) Publik     — 0.0.0.0  (bisa diakses dari luar)"
  read -rp "  Pilihan [1]: " net_choice
  if [[ "$net_choice" == "2" ]]; then
    MONGO_BIND="0.0.0.0"   # mongod mendengarkan semua interface
    MONGO_HOST="127.0.0.1" # koneksi manajemen tetap lokal
    BIND_IP="0.0.0.0"
  else
    MONGO_BIND="127.0.0.1"
    MONGO_HOST="127.0.0.1"
    BIND_IP="127.0.0.1"
  fi

  # -- Replica Set (dibutuhkan untuk transactions / session rollback) --
  echo
  ask "Aktifkan Replica Set? (diperlukan untuk transactions & session rollback)"
  echo "    Bisa dipakai di single server sekalipun — tidak harus multi-node."
  echo
  echo "    1) Tidak — standalone biasa (default)"
  echo "    2) Ya    — aktifkan replica set (support transactions)"
  read -rp "  Pilihan [1]: " rs_choice
  if [[ "$rs_choice" == "2" ]]; then
    read -rp "  Nama replica set [rs0]: " input_rs
    MONGO_REPLSET="${input_rs:-rs0}"
  else
    MONGO_REPLSET=""
  fi

  # -- TLS/SSL --
  echo
  detect_ssl_certs   # scan dulu, hasilnya info saja

  MONGO_TLS="no"
  MONGO_TLS_PEM=""
  MONGO_TLS_CA=""

  ask "Aktifkan TLS/SSL untuk koneksi MongoDB?"
  echo "    1) Tidak — tanpa TLS (default)"
  echo "    2) Ya    — enkripsi koneksi"
  read -rp "  Pilihan [1]: " tls_choice

  if [[ "$tls_choice" == "2" ]]; then
    MONGO_TLS="yes"
    echo

    # Kalau Let's Encrypt ditemukan, tawarkan buat PEM gabungan otomatis
    if [[ -n "$DETECTED_KEY" && "$DETECTED_CERT" == *"letsencrypt"* ]]; then
      ask "Let's Encrypt terdeteksi. Buat PEM gabungan otomatis di /etc/mongodb/tls/?"
      echo "    1) Ya — buat otomatis (direkomendasikan)"
      echo "    2) Tidak — input path manual"
      read -rp "  Pilihan [1]: " le_auto
      if [[ "$le_auto" != "2" ]]; then
        sudo mkdir -p /etc/mongodb/tls
        sudo cat "$DETECTED_CERT" "$DETECTED_KEY" | sudo tee /etc/mongodb/tls/mongodb.pem > /dev/null
        sudo chmod 600 /etc/mongodb/tls/mongodb.pem
        sudo chown mongodb:mongodb /etc/mongodb/tls/mongodb.pem 2>/dev/null || true
        MONGO_TLS_PEM="/etc/mongodb/tls/mongodb.pem"
        success "PEM gabungan dibuat: $MONGO_TLS_PEM"

        # Simpan domain Let's Encrypt untuk renewal hook
        local le_domain_for_hook
        le_domain_for_hook=$(echo "$DETECTED_CERT" | awk -F'/' '{print $6}')

        # Buat certbot renewal hook agar MongoDB ikut update saat cert diperbarui
        info "Membuat certbot renewal hook untuk MongoDB..."
        sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
        sudo tee /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh > /dev/null <<HOOK
#!/bin/bash
# Auto-generated by MongoDB Manager
# Dijalankan otomatis oleh certbot setelah renewal berhasil
DOMAIN="${le_domain_for_hook}"
LE_CERT="/etc/letsencrypt/live/\${DOMAIN}/fullchain.pem"
LE_KEY="/etc/letsencrypt/live/\${DOMAIN}/privkey.pem"
MONGO_PEM="/etc/mongodb/tls/mongodb.pem"

# Rebuild PEM gabungan
cat "\${LE_CERT}" "\${LE_KEY}" > "\${MONGO_PEM}"
chmod 600 "\${MONGO_PEM}"
chown mongodb:mongodb "\${MONGO_PEM}" 2>/dev/null || true

# Restart MongoDB agar cert baru dimuat
systemctl restart mongod

echo "[$(date)] MongoDB TLS cert diperbarui dari Let's Encrypt domain: \${DOMAIN}" \
  >> /var/log/mongodb-tls-renew.log
HOOK
        sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh
        success "Renewal hook dibuat: /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh"
        info "MongoDB akan otomatis restart setiap kali certbot memperbarui sertifikat."
        echo
        read -rp "  Path CA file (kosong = tidak pakai): " input_ca
        MONGO_TLS_CA="${input_ca:-}"
      fi
    fi

    # Kalau /etc/mongodb/tls/mongodb.pem sudah ada langsung tawarkan
    if [[ -z "$MONGO_TLS_PEM" && -n "$DETECTED_CERT" && -z "$DETECTED_KEY" ]]; then
      MONGO_TLS_PEM="$DETECTED_CERT"
      MONGO_TLS_CA="$DETECTED_CA"
      info "Menggunakan PEM yang terdeteksi: $MONGO_TLS_PEM"
    fi

    # Input manual jika belum ada
    if [[ -z "$MONGO_TLS_PEM" ]]; then
      if [[ -n "$DETECTED_CERT" ]]; then
        read -rp "  Path file PEM (cert+key gabungan) [$DETECTED_CERT]: " input_pem
        MONGO_TLS_PEM="${input_pem:-$DETECTED_CERT}"
      else
        read -rp "  Path file PEM (cert+key gabungan): " MONGO_TLS_PEM
        [[ -z "$MONGO_TLS_PEM" ]] && { error "Path PEM tidak boleh kosong jika TLS aktif."; MONGO_TLS="no"; }
      fi
      if [[ -z "$MONGO_TLS_CA" ]]; then
        read -rp "  Path CA file (kosong = tidak pakai): " MONGO_TLS_CA
      fi
    fi

    # Validasi file PEM ada
    if [[ "$MONGO_TLS" == "yes" && -n "$MONGO_TLS_PEM" && ! -f "$MONGO_TLS_PEM" ]]; then
      warn "File PEM '$MONGO_TLS_PEM' tidak ditemukan — TLS dinonaktifkan."
      MONGO_TLS="no"; MONGO_TLS_PEM=""; MONGO_TLS_CA=""
    fi
  fi

  echo; line
  echo -e "  ${BLD}Ringkasan instalasi:${NC}"
  echo "    Versi       : MongoDB $MONGO_VER.x"
  echo "    Port        : $MONGO_PORT"
  echo "    Auth        : $MONGO_AUTH"
  [[ "$MONGO_AUTH" == "yes" ]] && echo "    User        : $MONGO_ADMIN_USER"
  echo "    Bind IP     : $MONGO_BIND (koneksi via 127.0.0.1)"
  if [[ -n "$MONGO_REPLSET" ]]; then
    echo "    Replica Set : $MONGO_REPLSET (transactions diaktifkan)"
  else
    echo "    Replica Set : tidak (standalone)"
  fi
  if [[ "$MONGO_TLS" == "yes" ]]; then
    echo "    TLS/SSL     : aktif"
    echo "    PEM file    : $MONGO_TLS_PEM"
    [[ -n "$MONGO_TLS_CA" ]] && echo "    CA file     : $MONGO_TLS_CA"
  else
    echo "    TLS/SSL     : tidak"
  fi
  line
  read -rp "  Lanjutkan? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { warn "Dibatalkan."; pause; return; }

  echo
  info "Memperbarui paket sistem..."
  sudo apt-get update -y
  info "Menginstal dependensi..."
  sudo apt-get install -y gnupg curl
  info "Menambahkan GPG key MongoDB $MONGO_VER.x..."
  curl -fsSL "https://www.mongodb.org/static/pgp/server-${MONGO_VER}.0.asc" | \
    sudo gpg -o "/usr/share/keyrings/mongodb-server-${MONGO_VER}.0.gpg" --dearmor
  info "Menambahkan repository MongoDB $MONGO_VER.x..."
  local CODENAME
  CODENAME=$(lsb_release -cs)
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-${MONGO_VER}.0.gpg ] \
https://repo.mongodb.org/apt/ubuntu ${CODENAME}/mongodb-org/${MONGO_VER}.0 multiverse" | \
    sudo tee "/etc/apt/sources.list.d/mongodb-org-${MONGO_VER}.0.list"
  info "Menginstal MongoDB..."
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org

  info "Menulis konfigurasi /etc/mongod.conf..."
  local AUTH_SECTION=""
  [[ "$MONGO_AUTH" == "yes" ]] && AUTH_SECTION=$'\nsecurity:\n  authorization: enabled'
  local RS_SECTION=""
  [[ -n "$MONGO_REPLSET" ]] && RS_SECTION=$'\nreplication:\n  replSetName: '"$MONGO_REPLSET"$''
  local TLS_SECTION=""
  if [[ "$MONGO_TLS" == "yes" && -n "$MONGO_TLS_PEM" ]]; then
    TLS_SECTION=$'\n  tls:\n    mode: requireTLS'
    TLS_SECTION+=$'\n    certificateKeyFile: '"$MONGO_TLS_PEM"
    [[ -n "$MONGO_TLS_CA" ]] && TLS_SECTION+=$'\n    CAFile: '"$MONGO_TLS_CA"
  fi
  sudo tee /etc/mongod.conf > /dev/null <<MONGOCFG
systemLog:
  destination: file
  logAppend: true
  path: /var/log/mongodb/mongod.log

storage:
  dbPath: /var/lib/mongodb

processManagement:
  timeZoneInfo: /usr/share/zoneinfo

net:
  port: ${MONGO_PORT}
  bindIp: ${MONGO_BIND}
${TLS_SECTION}
${AUTH_SECTION}
${RS_SECTION}
MONGOCFG

  info "Mengaktifkan dan memulai layanan..."
  sudo systemctl daemon-reload
  sudo systemctl enable mongod
  sudo systemctl start mongod
  sleep 3

  if [[ "$MONGO_AUTH" == "yes" ]]; then
    info "Membuat user admin..."
    sudo sed -i 's/authorization: enabled/authorization: disabled/' /etc/mongod.conf
    sudo systemctl restart mongod; sleep 2
    mongosh --quiet --host 127.0.0.1 --port "$MONGO_PORT" admin --eval "
      db.createUser({
        user: '$MONGO_ADMIN_USER', pwd: '$MONGO_ADMIN_PASS',
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
  fi

  # -- Inisialisasi Replica Set --
  if [[ -n "$MONGO_REPLSET" ]]; then
    info "Menginisialisasi replica set '$MONGO_REPLSET'..."
    sleep 2
    local RS_HOST="127.0.0.1"
    if [[ "$MONGO_AUTH" == "yes" ]]; then
      mongosh --quiet         --host "$RS_HOST" --port "$MONGO_PORT"         -u "$MONGO_ADMIN_USER" -p "$MONGO_ADMIN_PASS"         --authenticationDatabase admin         admin --eval "
          rs.initiate({
            _id: '$MONGO_REPLSET',
            members: [{ _id: 0, host: '$RS_HOST:$MONGO_PORT' }]
          });
          sleep(2000);
          print('Replica set status: ' + rs.status().ok);
        "
    else
      mongosh --quiet         --host "$RS_HOST" --port "$MONGO_PORT"         admin --eval "
          rs.initiate({
            _id: '$MONGO_REPLSET',
            members: [{ _id: 0, host: '$RS_HOST:$MONGO_PORT' }]
          });
          sleep(2000);
          print('Replica set status: ' + rs.status().ok);
        "
    fi
    success "Replica set '$MONGO_REPLSET' berhasil diinisialisasi."
  fi

  if [[ "$MONGO_BIND" == "0.0.0.0" ]]; then
    command -v ufw &>/dev/null && { info "Membuka port $MONGO_PORT di UFW..."; sudo ufw allow "$MONGO_PORT"/tcp; }
  fi

  save_conf

  # Bangun query string koneksi
  local QS=""
  [[ -n "$MONGO_REPLSET" ]] && QS="?replicaSet=${MONGO_REPLSET}"
  if [[ "$MONGO_TLS" == "yes" ]]; then
    [[ -n "$QS" ]] && QS+="&tls=true" || QS="?tls=true"
  fi
  local CONN_STR=""
  if [[ "$MONGO_AUTH" == "yes" ]]; then
    if [[ -n "$QS" ]]; then
      CONN_STR="mongodb://${MONGO_ADMIN_USER}:${MONGO_ADMIN_PASS}@127.0.0.1:${MONGO_PORT}/admin${QS}"
    else
      CONN_STR="mongodb://${MONGO_ADMIN_USER}:${MONGO_ADMIN_PASS}@127.0.0.1:${MONGO_PORT}/admin"
    fi
  else
    if [[ -n "$QS" ]]; then
      CONN_STR="mongodb://127.0.0.1:${MONGO_PORT}/${QS}"
    else
      CONN_STR="mongodb://127.0.0.1:${MONGO_PORT}/"
    fi
  fi

  echo; line
  echo -e "${BLD}${GRN}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║     MongoDB Berhasil Diinstal!           ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"

  echo -e "  ${BLD}── Konfigurasi ──────────────────────────────${NC}"
  echo "    Versi       : MongoDB ${MONGO_VER}.x"
  echo "    Port        : $MONGO_PORT"
  echo "    Bind IP     : $MONGO_BIND"
  if [[ "$MONGO_AUTH" == "yes" ]]; then
    echo "    Auth        : aktif"
    echo "    Admin user  : $MONGO_ADMIN_USER"
  else
    echo "    Auth        : nonaktif"
  fi
  if [[ -n "$MONGO_REPLSET" ]]; then
    echo "    Replica Set : $MONGO_REPLSET  ✓ (transactions & session aktif)"
  else
    echo "    Replica Set : tidak (standalone)"
  fi
  if [[ "$MONGO_TLS" == "yes" ]]; then
    echo "    TLS/SSL     : aktif  ✓"
    echo "    PEM file    : $MONGO_TLS_PEM"
    [[ -n "$MONGO_TLS_CA" ]] && echo "    CA file     : $MONGO_TLS_CA"
    if [[ -f /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh ]]; then
      echo "    Auto-renew  : aktif  ✓ (certbot hook terpasang)"
      echo "    Hook path   : /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh"
      echo "    Renew log   : /var/log/mongodb-tls-renew.log"
    fi
  else
    echo "    TLS/SSL     : tidak"
  fi
  echo "    Config file : $MONGOD_CONF"
  echo "    Saved conf  : $CONF_FILE"

  echo
  echo -e "  ${BLD}── Koneksi ───────────────────────────────────${NC}"
  echo -e "  ${CYN}${CONN_STR}${NC}"
  [[ "$MONGO_AUTH" != "yes" ]] && warn "Auth nonaktif — jangan gunakan di production!"

  echo
  echo -e "  ${BLD}── Catatan ──────────────────────────────────${NC}"
  [[ -n "$MONGO_REPLSET" ]] &&     echo "  • Tambahkan ?replicaSet=${MONGO_REPLSET} di connection string aplikasi"
  [[ "$MONGO_TLS" == "yes" ]] &&     echo "  • Tambahkan tls=true (dan tlsCAFile jika pakai CA) di connection string aplikasi"
  [[ "$MONGO_TLS" == "yes" && -f /etc/letsencrypt/renewal-hooks/deploy/mongodb-tls.sh ]] &&     echo "  • Sertifikat Let'''s Encrypt akan diperbarui otomatis via certbot (setiap ~3 bulan)"
  [[ "$MONGO_BIND" == "0.0.0.0" && "$MONGO_AUTH" != "yes" ]] &&     warn "BAHAYA: Bind publik + auth nonaktif — MongoDB terbuka ke internet tanpa password!"
  echo

  line; pause
}

# ============================================================
# 2. MANAGE USER — Submenu
# ============================================================

# Helper: tampilkan daftar semua user
_list_users() {
  info "Daftar user yang terdaftar:"
  echo
  mongo_exec "
    var users = db.system.users.find({}, {user:1, db:1, roles:1, _id:0}).toArray();
    if (users.length === 0) { print('    (belum ada user)'); }
    users.forEach(function(u) {
      var roles = u.roles.map(function(r){ return r.role + '@' + r.db; }).join(', ');
      print('    • ' + u.user + ' [db: ' + u.db + '] — roles: ' + roles);
    });
  " admin
}

# 2a. Buat user baru
_create_user() {
  show_banner
  echo -e "${BLD}  [2] Manage User › Buat User Baru${NC}"; line; echo

  read -rp "  Nama user baru: " NEW_USER
  [[ -z "$NEW_USER" ]] && { error "Username tidak boleh kosong."; pause; return; }

  while true; do
    read -rsp "  Password: " NEW_PASS; echo
    read -rsp "  Konfirmasi password: " NEW_PASS2; echo
    [[ "$NEW_PASS" == "$NEW_PASS2" ]] && break
    error "Password tidak cocok, coba lagi."
  done

  read -rp "  Database target [admin]: " NEW_DB
  NEW_DB="${NEW_DB:-admin}"

  echo; ask "Role:"
  echo "    1) readWrite            — baca & tulis (default)"
  echo "    2) read                 — hanya baca"
  echo "    3) dbAdmin              — admin 1 database"
  echo "    4) dbOwner              — pemilik penuh 1 database"
  echo "    5) readWriteAnyDatabase — baca-tulis semua DB"
  echo "    6) userAdminAnyDatabase — admin semua user"
  read -rp "  Pilihan [1]: " role_choice
  case "$role_choice" in
    2) ROLE="read" ;;
    3) ROLE="dbAdmin" ;;
    4) ROLE="dbOwner" ;;
    5) ROLE="readWriteAnyDatabase" ;;
    6) ROLE="userAdminAnyDatabase" ;;
    *) ROLE="readWrite" ;;
  esac

  mongo_exec "
    db = db.getSiblingDB('$NEW_DB');
    db.createUser({ user: '$NEW_USER', pwd: '$NEW_PASS', roles: [{ role: '$ROLE', db: '$NEW_DB' }] });
    print('User berhasil dibuat.');
  " admin

  echo; line
  success "User '$NEW_USER' berhasil dibuat!"
  echo "    Database : $NEW_DB  |  Role: $ROLE"
  echo -e "\n  Koneksi:"
  echo -e "  ${CYN}mongosh mongodb://${NEW_USER}:${NEW_PASS}@${MONGO_HOST}:${MONGO_PORT}/${NEW_DB}${NC}"
  line; pause
}

# 2b. Update user (username → tidak bisa diubah di MongoDB, update = customData/roles/password sekaligus)
_update_user() {
  show_banner
  echo -e "${BLD}  [2] Manage User › Update User${NC}"; line; echo
  _list_users; echo

  read -rp "  Nama user yang akan diupdate: " UPD_USER
  [[ -z "$UPD_USER" ]] && { error "Username tidak boleh kosong."; pause; return; }

  read -rp "  Database user tersebut [admin]: " UPD_DB
  UPD_DB="${UPD_DB:-admin}"

  echo
  ask "Apa yang ingin diupdate? (bisa pilih lebih dari satu, pisah koma — contoh: 1,2)"
  echo "    1) Password"
  echo "    2) Role"
  read -rp "  Pilihan: " upd_choice

  local NEW_PASS_UPD="" NEW_ROLE_UPD=""
  local JS_UPDATE=""

  # Password
  if echo "$upd_choice" | grep -q "1"; then
    while true; do
      read -rsp "  Password baru: " NEW_PASS_UPD; echo
      read -rsp "  Konfirmasi password: " NEW_PASS_UPD2; echo
      [[ "$NEW_PASS_UPD" == "$NEW_PASS_UPD2" ]] && break
      error "Password tidak cocok, coba lagi."
    done
    JS_UPDATE="${JS_UPDATE} updateFields.pwd = '$NEW_PASS_UPD';"
  fi

  # Role
  if echo "$upd_choice" | grep -q "2"; then
    echo; ask "Role baru:"
    echo "    1) readWrite            (default)"
    echo "    2) read"
    echo "    3) dbAdmin"
    echo "    4) dbOwner"
    echo "    5) readWriteAnyDatabase"
    echo "    6) userAdminAnyDatabase"
    read -rp "  Pilihan [1]: " role_choice2
    case "$role_choice2" in
      2) NEW_ROLE_UPD="read" ;;
      3) NEW_ROLE_UPD="dbAdmin" ;;
      4) NEW_ROLE_UPD="dbOwner" ;;
      5) NEW_ROLE_UPD="readWriteAnyDatabase" ;;
      6) NEW_ROLE_UPD="userAdminAnyDatabase" ;;
      *) NEW_ROLE_UPD="readWrite" ;;
    esac
    JS_UPDATE="${JS_UPDATE} updateFields.roles = [{ role: '$NEW_ROLE_UPD', db: '$UPD_DB' }];"
  fi

  [[ -z "$JS_UPDATE" ]] && { warn "Tidak ada perubahan yang dipilih."; pause; return; }

  mongo_exec "
    db = db.getSiblingDB('$UPD_DB');
    var updateFields = {};
    ${JS_UPDATE}
    db.updateUser('$UPD_USER', updateFields);
    print('User berhasil diupdate.');
  " admin

  echo; success "User '$UPD_USER' berhasil diupdate."; pause
}

# 2c. Reset password
_reset_password() {
  show_banner
  echo -e "${BLD}  [2] Manage User › Reset Password${NC}"; line; echo
  _list_users; echo

  read -rp "  Nama user: " RST_USER
  [[ -z "$RST_USER" ]] && { error "Username tidak boleh kosong."; pause; return; }

  read -rp "  Database user tersebut [admin]: " RST_DB
  RST_DB="${RST_DB:-admin}"

  while true; do
    read -rsp "  Password baru: " RST_PASS; echo
    read -rsp "  Konfirmasi password: " RST_PASS2; echo
    [[ "$RST_PASS" == "$RST_PASS2" ]] && break
    error "Password tidak cocok, coba lagi."
  done

  mongo_exec "
    db = db.getSiblingDB('$RST_DB');
    db.updateUser('$RST_USER', { pwd: '$RST_PASS' });
    print('Password berhasil direset.');
  " admin

  echo; success "Password user '$RST_USER' berhasil direset."; pause
}

# 2d. Delete user
_delete_user() {
  show_banner
  echo -e "${BLD}  [2] Manage User › Hapus User${NC}"; line; echo
  _list_users; echo

  read -rp "  Nama user yang akan dihapus: " DEL_USER
  [[ -z "$DEL_USER" ]] && { error "Username tidak boleh kosong."; pause; return; }

  read -rp "  Database user tersebut [admin]: " DEL_DB
  DEL_DB="${DEL_DB:-admin}"

  echo
  warn "PERINGATAN: User '$DEL_USER' akan dihapus permanen dari database '$DEL_DB'!"
  read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
  [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return; }

  mongo_exec "
    db = db.getSiblingDB('$DEL_DB');
    db.dropUser('$DEL_USER');
    print('User berhasil dihapus.');
  " admin

  echo; success "User '$DEL_USER' berhasil dihapus."; pause
}

# 2e. Change role
_change_role() {
  show_banner
  echo -e "${BLD}  [2] Manage User › Ganti Role${NC}"; line; echo
  _list_users; echo

  read -rp "  Nama user: " CHR_USER
  [[ -z "$CHR_USER" ]] && { error "Username tidak boleh kosong."; pause; return; }

  read -rp "  Database user tersebut [admin]: " CHR_DB
  CHR_DB="${CHR_DB:-admin}"

  echo; ask "Role baru:"
  echo "    1) readWrite            — baca & tulis (default)"
  echo "    2) read                 — hanya baca"
  echo "    3) dbAdmin              — admin 1 database"
  echo "    4) dbOwner              — pemilik penuh 1 database"
  echo "    5) readWriteAnyDatabase — baca-tulis semua DB"
  echo "    6) userAdminAnyDatabase — admin semua user"
  read -rp "  Pilihan [1]: " role_choice
  case "$role_choice" in
    2) NEW_ROLE="read" ;;
    3) NEW_ROLE="dbAdmin" ;;
    4) NEW_ROLE="dbOwner" ;;
    5) NEW_ROLE="readWriteAnyDatabase" ;;
    6) NEW_ROLE="userAdminAnyDatabase" ;;
    *) NEW_ROLE="readWrite" ;;
  esac

  mongo_exec "
    db = db.getSiblingDB('$CHR_DB');
    db.updateUser('$CHR_USER', { roles: [{ role: '$NEW_ROLE', db: '$CHR_DB' }] });
    print('Role berhasil diubah.');
  " admin

  echo; success "Role user '$CHR_USER' diubah menjadi '$NEW_ROLE'."; pause
}

# Submenu Manage User
manage_user_menu() {
  load_conf
  while true; do
    show_banner
    echo -e "${BLD}  [2] Manage User${NC}"
    line
    echo
    _list_users
    echo
    line
    echo -e "  ${BLD}Pilih aksi:${NC}"
    echo
    echo "    1)  Buat user baru"
    echo "    2)  Update user (password & role)"
    echo "    3)  Reset password"
    echo "    4)  Hapus user"
    echo "    5)  Ganti role"
    echo "    6)  Kembali ke menu utama"
    echo
    line
    read -rp "  Pilihan [1-6]: " choice
    case "$choice" in
      1) _create_user ;;
      2) _update_user ;;
      3) _reset_password ;;
      4) _delete_user ;;
      5) _change_role ;;
      6) return ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ============================================================
# 3. MANAGE DATABASE — Submenu
# ============================================================

# Helper: tampilkan daftar semua database
_list_databases() {
  info "Daftar database:"
  echo
  mongo_exec "
    var dbs = db.adminCommand({ listDatabases: 1 }).databases;
    dbs.forEach(function(d) {
      var size = (d.sizeOnDisk / 1024 / 1024).toFixed(2);
      print('    • ' + d.name + '  (' + size + ' MB)');
    });
  " admin
}

# 3a. Buat database (MongoDB lazy-create: perlu buat collection dulu)
_create_database() {
  show_banner
  echo -e "${BLD}  [3] Manage Database › Buat Database${NC}"; line; echo

  read -rp "  Nama database baru: " NEW_DBNAME
  [[ -z "$NEW_DBNAME" ]] && { error "Nama database tidak boleh kosong."; pause; return; }

  read -rp "  Nama collection pertama [default]: " NEW_COLNAME
  NEW_COLNAME="${NEW_COLNAME:-default}"

  mongo_exec "
    db = db.getSiblingDB('$NEW_DBNAME');
    db.createCollection('$NEW_COLNAME');
    print('Database dan collection berhasil dibuat.');
  " admin

  echo; success "Database '$NEW_DBNAME' dengan collection '$NEW_COLNAME' berhasil dibuat."
  warn "MongoDB membuat database secara lazy — database muncul setelah ada data/collection."
  pause
}

# 3b. Drop database
_drop_database() {
  show_banner
  echo -e "${BLD}  [3] Manage Database › Hapus Database${NC}"; line; echo
  _list_databases; echo

  read -rp "  Nama database yang akan dihapus: " DROP_DBNAME
  [[ -z "$DROP_DBNAME" ]] && { error "Nama database tidak boleh kosong."; pause; return; }

  echo
  warn "PERINGATAN: Database '$DROP_DBNAME' dan SEMUA datanya akan dihapus permanen!"
  read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
  [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return; }

  mongo_exec "
    db = db.getSiblingDB('$DROP_DBNAME');
    db.dropDatabase();
    print('Database berhasil dihapus.');
  " admin

  echo; success "Database '$DROP_DBNAME' berhasil dihapus."; pause
}

# 3c. Lihat collections dalam database
_show_collections() {
  show_banner
  echo -e "${BLD}  [3] Manage Database › Lihat Collections${NC}"; line; echo
  _list_databases; echo

  read -rp "  Nama database: " COL_DB
  [[ -z "$COL_DB" ]] && { error "Nama database tidak boleh kosong."; pause; return; }

  echo
  info "Collections di database '$COL_DB':"
  echo
  mongo_exec "
    db = db.getSiblingDB('$COL_DB');
    var cols = db.getCollectionInfos();
    if (cols.length === 0) { print('    (belum ada collection)'); }
    cols.forEach(function(c) {
      var stats = db.getCollection(c.name).stats();
      var count = stats.count || 0;
      var size  = ((stats.size || 0) / 1024).toFixed(1);
      print('    • ' + c.name + '  (' + count + ' dokumen, ' + size + ' KB)');
    });
  " admin

  pause
}

# 3d. Buat collection
_create_collection() {
  show_banner
  echo -e "${BLD}  [3] Manage Database › Buat Collection${NC}"; line; echo
  _list_databases; echo

  read -rp "  Nama database target: " CC_DB
  [[ -z "$CC_DB" ]] && { error "Nama database tidak boleh kosong."; pause; return; }

  read -rp "  Nama collection baru: " CC_NAME
  [[ -z "$CC_NAME" ]] && { error "Nama collection tidak boleh kosong."; pause; return; }

  mongo_exec "
    db = db.getSiblingDB('$CC_DB');
    db.createCollection('$CC_NAME');
    print('Collection berhasil dibuat.');
  " admin

  echo; success "Collection '$CC_NAME' berhasil dibuat di database '$CC_DB'."; pause
}

# 3e. Drop collection
_drop_collection() {
  show_banner
  echo -e "${BLD}  [3] Manage Database › Hapus Collection${NC}"; line; echo
  _list_databases; echo

  read -rp "  Nama database: " DC_DB
  [[ -z "$DC_DB" ]] && { error "Nama database tidak boleh kosong."; pause; return; }

  echo
  info "Collections di '$DC_DB':"
  mongo_exec "
    db = db.getSiblingDB('$DC_DB');
    db.getCollectionNames().forEach(c => print('    • ' + c));
  " admin
  echo

  read -rp "  Nama collection yang akan dihapus: " DC_NAME
  [[ -z "$DC_NAME" ]] && { error "Nama collection tidak boleh kosong."; pause; return; }

  echo
  warn "PERINGATAN: Collection '$DC_NAME' dan semua isinya akan dihapus permanen!"
  read -rp "  Ketik 'HAPUS' untuk konfirmasi: " confirm
  [[ "$confirm" != "HAPUS" ]] && { warn "Dibatalkan."; pause; return; }

  mongo_exec "
    db = db.getSiblingDB('$DC_DB');
    db.getCollection('$DC_NAME').drop();
    print('Collection berhasil dihapus.');
  " admin

  echo; success "Collection '$DC_NAME' berhasil dihapus."; pause
}

# Submenu Manage Database
manage_database_menu() {
  load_conf
  while true; do
    show_banner
    echo -e "${BLD}  [3] Manage Database${NC}"
    line
    echo
    _list_databases
    echo
    line
    echo -e "  ${BLD}Pilih aksi:${NC}"
    echo
    echo "    1)  Lihat collections dalam database"
    echo "    2)  Buat database baru"
    echo "    3)  Hapus database"
    echo "    4)  Buat collection baru"
    echo "    5)  Hapus collection"
    echo "    6)  Kembali ke menu utama"
    echo
    line
    read -rp "  Pilihan [1-6]: " choice
    case "$choice" in
      1) _show_collections ;;
      2) _create_database ;;
      3) _drop_database ;;
      4) _create_collection ;;
      5) _drop_collection ;;
      6) return ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ============================================================
# 4. BACKUP DATABASE
# ============================================================
backup_db() {
  show_banner
  echo -e "${BLD}  [4] Backup Database${NC}"; line

  detect_running_config
  echo

  info "Daftar database yang tersedia:"
  mongo_exec "db.adminCommand({listDatabases:1}).databases.forEach(d => print('    - ' + d.name))" admin
  echo

  read -rp "  Nama database yang di-backup (kosong = semua): " BKP_DB
  read -rp "  Direktori tujuan backup [/tmp/mongo_backup]: " BKP_DIR
  BKP_DIR="${BKP_DIR:-/tmp/mongo_backup}"

  local TIMESTAMP; TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local OUT_DIR="${BKP_DIR}/${TIMESTAMP}"
  mkdir -p "$OUT_DIR"

  local AUTH_ARGS=""
  [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]] && \
    AUTH_ARGS="-u $MONGO_ADMIN_USER -p $MONGO_ADMIN_PASS --authenticationDatabase admin"

  if [[ -n "$BKP_DB" ]]; then
    info "Membackup database '$BKP_DB'..."
    mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $AUTH_ARGS --db "$BKP_DB" --out "$OUT_DIR"
  else
    info "Membackup semua database..."
    mongodump --host "$MONGO_HOST" --port "$MONGO_PORT" $AUTH_ARGS --out "$OUT_DIR"
  fi

  info "Mengompres backup..."
  local ARCHIVE="${BKP_DIR}/backup_${TIMESTAMP}.tar.gz"
  tar -czf "$ARCHIVE" -C "$BKP_DIR" "$TIMESTAMP"
  rm -rf "$OUT_DIR"

  echo; line
  success "Backup selesai!"
  echo "    File  : $ARCHIVE"
  echo "    Ukuran: $(du -sh "$ARCHIVE" | cut -f1)"
  line; pause
}

# ============================================================
# 5. RESTORE DATABASE
# ============================================================
restore_db() {
  show_banner
  echo -e "${BLD}  [5] Restore Database${NC}"; line

  detect_running_config
  echo

  read -rp "  Path file backup (.tar.gz atau direktori): " RST_PATH
  [[ -z "$RST_PATH" ]] && { error "Path tidak boleh kosong."; pause; return; }
  [[ ! -e "$RST_PATH" ]] && { error "File/direktori '$RST_PATH' tidak ditemukan."; pause; return; }

  read -rp "  Nama database tujuan (kosong = sesuai backup): " RST_DB

  local AUTH_ARGS=""
  [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]] && \
    AUTH_ARGS="-u $MONGO_ADMIN_USER -p $MONGO_ADMIN_PASS --authenticationDatabase admin"

  local RST_DIR="$RST_PATH"
  if [[ "$RST_PATH" == *.tar.gz ]]; then
    local TMP_DIR="/tmp/mongo_restore_$$"
    mkdir -p "$TMP_DIR"
    info "Mengekstrak backup..."
    tar -xzf "$RST_PATH" -C "$TMP_DIR"
    RST_DIR=$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)
    [[ -z "$RST_DIR" ]] && RST_DIR="$TMP_DIR"
  fi

  warn "PERINGATAN: Data yang ada pada database tujuan akan ditimpa!"
  read -rp "  Ketik 'RESTORE' untuk konfirmasi: " confirm
  if [[ "$confirm" != "RESTORE" ]]; then
    warn "Dibatalkan."
    [[ -d "/tmp/mongo_restore_$$" ]] && rm -rf "/tmp/mongo_restore_$$"
    pause; return
  fi

  if [[ -n "$RST_DB" ]]; then
    info "Merestore ke database '$RST_DB'..."
    mongorestore --host "$MONGO_HOST" --port "$MONGO_PORT" $AUTH_ARGS --db "$RST_DB" --drop "$RST_DIR/$RST_DB"
  else
    info "Merestore semua database..."
    mongorestore --host "$MONGO_HOST" --port "$MONGO_PORT" $AUTH_ARGS --drop "$RST_DIR"
  fi

  [[ -d "/tmp/mongo_restore_$$" ]] && rm -rf "/tmp/mongo_restore_$$"
  echo; success "Restore selesai!"; pause
}

# ============================================================
# 6. SERVICE MONGODB — Status, Start, Stop, Restart
# ============================================================
service_menu() {
  while true; do
    show_banner
    echo -e "${BLD}  [6] Service MongoDB${NC}"
    line
    echo

    # Cek status service
    local SVC_STATUS SVC_COLOR SVC_SINCE SVC_PID SVC_ENABLED
    if systemctl is-active --quiet mongod 2>/dev/null; then
      SVC_STATUS="RUNNING"; SVC_COLOR="$GRN"
    else
      SVC_STATUS="STOPPED"; SVC_COLOR="$RED"
    fi
    SVC_SINCE=$(systemctl show mongod --property=ActiveEnterTimestamp --value 2>/dev/null)
    SVC_PID=$(systemctl show mongod    --property=MainPID --value 2>/dev/null)
    SVC_ENABLED=$(systemctl is-enabled mongod 2>/dev/null || echo "unknown")

    echo -e "  Status    : ${SVC_COLOR}${BLD}${SVC_STATUS}${NC}"
    echo    "  Enabled   : $SVC_ENABLED"
    [[ -n "$SVC_SINCE" && "$SVC_SINCE" != "n/a" ]] && echo "  Since     : $SVC_SINCE"
    [[ -n "$SVC_PID"   && "$SVC_PID"   != "0"   ]] && echo "  PID       : $SVC_PID"

    if [[ -f "$MONGOD_CONF" ]]; then
      local ACTUAL_PORT ACTUAL_BIND ACTUAL_RS
      ACTUAL_PORT=$(parse_mongod_conf "port");   ACTUAL_PORT="${ACTUAL_PORT:-27017}"
      ACTUAL_BIND=$(parse_mongod_conf "bindIp"); ACTUAL_BIND="${ACTUAL_BIND:-127.0.0.1}"
      ACTUAL_RS=$(grep -E "^\s+replSetName\s*:" "$MONGOD_CONF" 2>/dev/null \
        | awk -F':' '{gsub(/[[:space:]]/, "", $2); print $2}')
      echo    "  Port      : $ACTUAL_PORT"
      echo    "  Bind IP   : $ACTUAL_BIND"
      [[ -n "$ACTUAL_RS" ]] && echo "  ReplicaSet: $ACTUAL_RS"
    fi

    echo
    line
    echo -e "  ${BLD}Pilih aksi:${NC}"
    echo
    echo "    1)  Lihat log terbaru (50 baris)"
    echo "    2)  Start"
    echo "    3)  Stop"
    echo "    4)  Restart"
    echo "    5)  Reload konfigurasi (tanpa restart)"
    echo "    6)  Kembali ke menu utama"
    echo
    line
    read -rp "  Pilihan [1-6]: " svc_choice

    case "$svc_choice" in
      1)
        echo
        info "Log terbaru MongoDB (/var/log/mongodb/mongod.log):"
        echo
        sudo tail -n 50 /var/log/mongodb/mongod.log 2>/dev/null \
          || warn "Log tidak dapat dibaca — pastikan dijalankan dengan sudo."
        pause
        ;;
      2)
        echo
        if systemctl is-active --quiet mongod; then
          warn "MongoDB sudah berjalan."
        else
          info "Menjalankan MongoDB..."
          sudo systemctl start mongod && success "MongoDB berhasil dijalankan." \
            || error "Gagal menjalankan MongoDB."
        fi
        sleep 1
        ;;
      3)
        echo
        if ! systemctl is-active --quiet mongod; then
          warn "MongoDB sudah berhenti."
        else
          warn "MongoDB akan dihentikan — semua koneksi aktif akan terputus!"
          read -rp "  Lanjutkan? [y/N]: " svc_confirm
          if [[ "$svc_confirm" =~ ^[Yy]$ ]]; then
            info "Menghentikan MongoDB..."
            sudo systemctl stop mongod && success "MongoDB berhasil dihentikan." \
              || error "Gagal menghentikan MongoDB."
          else
            warn "Dibatalkan."
          fi
        fi
        sleep 1
        ;;
      4)
        echo
        info "Merestart MongoDB..."
        sudo systemctl restart mongod && success "MongoDB berhasil direstart." \
          || error "Gagal merestart MongoDB."
        sleep 2
        ;;
      5)
        echo
        info "Reload konfigurasi MongoDB (SIGHUP)..."
        sudo systemctl reload-or-restart mongod && success "Konfigurasi berhasil direload." \
          || error "Gagal reload — cek log untuk detail."
        sleep 1
        ;;
      6) return ;;
      *) warn "Pilihan tidak valid."; sleep 1 ;;
    esac
  done
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu() {
  load_conf
  while true; do
    show_banner
    echo -e "  ${BLD}Konfigurasi aktif:${NC}"
    echo "    Host : ${MONGO_HOST}:${MONGO_PORT}  |  Bind: ${MONGO_BIND}  |  Auth: ${MONGO_AUTH}"
    [[ "$MONGO_AUTH" == "yes" && -n "$MONGO_ADMIN_USER" ]] && echo "    User : ${MONGO_ADMIN_USER}"
    [[ -n "$MONGO_REPLSET" ]] && echo "    RS   : ${MONGO_REPLSET}"
    echo -e "    Conf : ${CYN}${CONF_FILE}${NC}"
    echo
    line
    echo -e "  ${BLD}Pilih menu:${NC}"
    echo
    echo "    1)  Setup MongoDB"
    echo "    2)  Manage User"
    echo "    3)  Manage Database"
    echo "    4)  Backup database"
    echo "    5)  Restore database"
    echo "    6)  Service MongoDB  (status/start/stop/restart)"
    echo "    7)  Keluar"
    echo
    line
    read -rp "  Pilihan [1-7]: " choice
    case "$choice" in
      1) setup_mongodb ;;
      2) manage_user_menu ;;
      3) manage_database_menu ;;
      4) backup_db ;;
      5) restore_db ;;
      6) service_menu ;;
      7) echo; success "Sampai jumpa!"; echo; exit 0 ;;
      *) warn "Pilihan tidak valid. Masukkan angka 1-7."; sleep 1 ;;
    esac
  done
}

# ---------- Entry point ----------
# Wrapper agar bisa dipanggil dari setup-server.sh
mongodb_main() { main_menu; }

# Jalankan hanya jika file ini dieksekusi langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  mongodb_main
fi
