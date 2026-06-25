#!/bin/bash

# ================================================================
#   PANEL MANAJEMEN HOSTING LINUX
#   vsftpd + Nginx + SSL (Certbot/Cloudflare DNS) + Deploy User
#   Ubuntu/Debian
# ================================================================

# ---------- Library bersama ----------
_MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$_MODULE_DIR/../lib"
# shellcheck source=../lib/common.sh
source "$_LIB_DIR/common.sh"      # warna, log_*, confirm, normalize_path, domain_to_slug
# shellcheck source=../lib/cloudflare.sh
source "$_LIB_DIR/cloudflare.sh"  # CF_CRED_FILE, setup_cloudflare_creds
# shellcheck source=../lib/ssl.sh
source "$_LIB_DIR/ssl.sh"         # detect_ssl_certs, resolve_ssl_cert

# ---------- Variabel khusus hosting ----------
BASE_DIR="/var/www"
VSFTPD_CONF="/etc/vsftpd.conf"
VSFTPD_USER_DIR="/etc/vsftpd/users"
VSFTPD_USERLIST="/etc/vsftpd/userlist"
SSH_DENY_CONF="/etc/ssh/sshd_config.d/deny-ftp-users.conf"
FTP_GROUP="ftpgroup"

# ================================================================
# MENU UTAMA
# ================================================================
show_main_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         PANEL MANAJEMEN HOSTING LINUX                         ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    echo " 1. Cek & Install Dependensi"
    echo " 2. Setup Cloudflare API Token"
    echo " 3. Konfigurasi vsftpd Server (sekali saja)"
    echo " 4. Manage Website & FTP"
    echo " 5. Manage SSL"
    echo " 6. Keluar"
    echo -e "${CYAN}================================================================${NC}"
}

# ================================================================
# MENU 1: CEK & INSTALL DEPENDENSI
# ================================================================
check_deps() {
    clear
    echo -e "${CYAN}--- CEK & INSTALL DEPENDENSI ---${NC}"
    echo ""

    local missing=()
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
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    echo -e "   ${YELLOW}Package yang perlu diinstall:${NC}"
    for pkg in "${missing[@]}"; do echo "     - $pkg"; done
    echo ""

    if confirm "Install semua sekarang?"; then
        echo ""
        sudo apt update -qq
        for pkg in "${missing[@]}"; do
            log_info "Menginstall $pkg..."
            sudo apt install -y "$pkg" &>/dev/null \
                && log_ok "$pkg berhasil diinstall." \
                || log_err "Gagal install $pkg. Coba: sudo apt install $pkg"
        done
        for svc in vsftpd nginx; do
            command -v "$svc" &>/dev/null && {
                sudo systemctl enable "$svc" &>/dev/null
                sudo systemctl start  "$svc" &>/dev/null
            }
        done
        log_ok "Instalasi selesai."
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# MENU 2: SETUP CLOUDFLARE API TOKEN
#   setup_cloudflare_creds() dipindah ke lib/cloudflare.sh (dipakai bersama)

# ================================================================
# MENU 3: KONFIGURASI VSFTPD SERVER (SEKALI SAJA)
# ================================================================
setup_vsftpd_global() {
    clear
    echo -e "${CYAN}--- KONFIGURASI VSFTPD SERVER ---${NC}"
    echo -e "   ${YELLOW}Jalankan sekali saja saat pertama setup server.${NC}"
    echo ""

    local cur_port cur_pasv_min cur_pasv_max
    cur_port=$(grep -oP     "(?<=^listen_port=)\d+"   "$VSFTPD_CONF" 2>/dev/null || echo "21")
    cur_pasv_min=$(grep -oP "(?<=^pasv_min_port=)\d+" "$VSFTPD_CONF" 2>/dev/null || echo "49000")
    cur_pasv_max=$(grep -oP "(?<=^pasv_max_port=)\d+" "$VSFTPD_CONF" 2>/dev/null || echo "49100")

    echo "   Konfigurasi saat ini: port=$cur_port, pasv=$cur_pasv_min-$cur_pasv_max"
    echo ""
    read -rp "   Port FTP        (Enter = $cur_port)      : " FTP_PORT;    [[ -z "$FTP_PORT"  ]] && FTP_PORT="$cur_port"
    read -rp "   Passive port MIN (Enter = $cur_pasv_min) : " PASV_MIN;    [[ -z "$PASV_MIN"  ]] && PASV_MIN="$cur_pasv_min"
    read -rp "   Passive port MAX (Enter = $cur_pasv_max) : " PASV_MAX;    [[ -z "$PASV_MAX"  ]] && PASV_MAX="$cur_pasv_max"

    # Pilih SSL cert untuk vsftpd
    local VSFTPD_SSL_CERT="" VSFTPD_SSL_KEY="" ssl_block
    echo ""
    if confirm "Aktifkan FTPS (SSL untuk vsftpd)?"; then
        echo ""
        local cert_dirs=()
        while IFS= read -r d; do cert_dirs+=("$d"); done \
            < <(find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

        if [[ ${#cert_dirs[@]} -gt 0 ]]; then
            echo "   Cert tersedia:"
            for i in "${!cert_dirs[@]}"; do
                echo "     [$i] ${cert_dirs[$i]}"
            done
            echo "     [m] Input manual"
            read -rp "   Pilih: " CERT_SEL
            if [[ "$CERT_SEL" == "m" ]]; then
                read -rp "   Path fullchain.pem: " _raw; VSFTPD_SSL_CERT=$(normalize_path "$_raw")
                read -rp "   Path privkey.pem  : " _raw; VSFTPD_SSL_KEY=$(normalize_path "$_raw")
            elif [[ "$CERT_SEL" =~ ^[0-9]+$ && "$CERT_SEL" -lt ${#cert_dirs[@]} ]]; then
                VSFTPD_SSL_CERT="${cert_dirs[$CERT_SEL]}/fullchain.pem"
                VSFTPD_SSL_KEY="${cert_dirs[$CERT_SEL]}/privkey.pem"
            fi
        else
            log_warn "Tidak ada Let's Encrypt cert ditemukan."
            read -rp "   Path fullchain.pem (kosong = skip): " _raw
            VSFTPD_SSL_CERT=$(normalize_path "$_raw")
            [[ -n "$VSFTPD_SSL_CERT" ]] && { read -rp "   Path privkey.pem: " _raw; VSFTPD_SSL_KEY=$(normalize_path "$_raw"); }
        fi
    fi

    # Deteksi IP publik untuk pasv_address
    echo ""
    log_info "Mendeteksi IP publik server..."
    local PUBLIC_IP=""
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}')

    if [[ -n "$PUBLIC_IP" ]]; then
        log_ok "IP terdeteksi: $PUBLIC_IP"
        read -rp "   pasv_address (Enter = $PUBLIC_IP, ketik manual jika beda): " PASV_ADDR
        [[ -z "$PASV_ADDR" ]] && PASV_ADDR="$PUBLIC_IP"
    else
        log_warn "Gagal deteksi IP otomatis."
        read -rp "   Masukkan IP publik server untuk pasv_address: " PASV_ADDR
    fi

    echo ""
    confirm "Terapkan konfigurasi vsftpd?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    # Pastikan group dan direktori ada
    getent group "$FTP_GROUP" &>/dev/null || { sudo groupadd "$FTP_GROUP"; log_ok "Group '$FTP_GROUP' dibuat."; }
    sudo mkdir -p "$VSFTPD_USER_DIR"
    [[ -f "$VSFTPD_USERLIST" ]] || sudo touch "$VSFTPD_USERLIST"
    sudo mkdir -p "$(dirname "$SSH_DENY_CONF")"
    [[ -f "$SSH_DENY_CONF" ]] || echo "DenyUsers" | sudo tee "$SSH_DENY_CONF" > /dev/null

    # Backup vsftpd.conf lama
    [[ -f "$VSFTPD_CONF" ]] && {
        sudo cp "$VSFTPD_CONF" "${VSFTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        log_ok "Backup vsftpd.conf lama disimpan."
    }

    # SSL block
    if [[ -n "$VSFTPD_SSL_CERT" && -f "$VSFTPD_SSL_CERT" ]]; then
        ssl_block="
# --- SSL / FTPS ---
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=$VSFTPD_SSL_CERT
rsa_private_key_file=$VSFTPD_SSL_KEY
require_ssl_reuse=NO
ssl_ciphers=HIGH"
    else
        ssl_block="
# --- SSL ---
ssl_enable=NO"
    fi

    local pasv_addr_line=""
    [[ -n "$PASV_ADDR" ]] && pasv_addr_line="pasv_address=$PASV_ADDR"

    sudo tee "$VSFTPD_CONF" > /dev/null << EOF
# vsftpd.conf - dikelola oleh setup-hosting.sh

listen=YES
listen_ipv6=NO
listen_port=$FTP_PORT
listen_address=0.0.0.0

anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022

chroot_local_user=YES
allow_writeable_chroot=YES
user_config_dir=$VSFTPD_USER_DIR

userlist_enable=YES
userlist_file=$VSFTPD_USERLIST
userlist_deny=NO

pasv_enable=YES
pasv_min_port=$PASV_MIN
pasv_max_port=$PASV_MAX
$pasv_addr_line
pasv_promiscuous=NO
$ssl_block
EOF

    log_ok "vsftpd.conf berhasil ditulis."

    # UFW rules
    if command -v ufw &>/dev/null; then
        sudo ufw allow "$FTP_PORT/tcp"             comment "FTP Control"      &>/dev/null
        sudo ufw allow 20/tcp                      comment "FTP Active Data"  &>/dev/null
        sudo ufw allow "$PASV_MIN:$PASV_MAX/tcp"  comment "FTP Passive Data" &>/dev/null
        sudo ufw allow 80/tcp                      comment "HTTP"             &>/dev/null
        sudo ufw allow 443/tcp                     comment "HTTPS"            &>/dev/null
        log_ok "UFW rules ditambahkan."
    fi

    sudo systemctl restart vsftpd &>/dev/null \
        && log_ok "vsftpd berhasil direstart." \
        || log_err "vsftpd gagal restart. Cek: sudo systemctl status vsftpd"

    echo ""
    echo -e "   ${CYAN}Port yang perlu dibuka di firewall/router/cloud:${NC}"
    echo "     TCP $FTP_PORT          : FTP Control"
    echo "     TCP 20                 : FTP Active Data (opsional)"
    echo "     TCP $PASV_MIN-$PASV_MAX : FTP Passive Data"
    echo "     TCP 80 & 443           : HTTP & HTTPS"
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ================================================================
# RESOLVE SSL (internal)
#   resolve_ssl_cert() dipindah ke lib/ssl.sh (dipakai bersama)
# ================================================================

# ================================================================
# BUAT USER FTP + FOLDER + ACL (dipakai oleh create_site & create_ftp_only)
# ================================================================
_create_ftp_user() {
    local ftp_user="$1" ftp_pass="$2" domain_dir="$3" deploy_user="$4"


    # Pastikan /usr/sbin/nologin terdaftar di /etc/shells agar PAM izinkan login FTP
    if ! grep -qx "/usr/sbin/nologin" /etc/shells 2>/dev/null; then
        echo "/usr/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
        log_ok "/usr/sbin/nologin ditambahkan ke /etc/shells."
    fi

    log_info "Membuat user FTP '$ftp_user'..."
    if id "$ftp_user" &>/dev/null; then
        log_warn "User '$ftp_user' sudah ada, skip buat user."
    else
        sudo adduser "$ftp_user" --shell /usr/sbin/nologin --gecos "" --disabled-password &>/dev/null \
            && echo "$ftp_user:$ftp_pass" | sudo chpasswd \
            && log_ok "User FTP '$ftp_user' dibuat." \
            || { log_err "Gagal membuat user FTP."; return 1; }
    fi

    # Tambahkan ke vsftpd whitelist
    grep -qx "$ftp_user" "$VSFTPD_USERLIST" 2>/dev/null \
        || echo "$ftp_user" | sudo tee -a "$VSFTPD_USERLIST" > /dev/null
    log_ok "User masuk vsftpd whitelist."

    # Larang SSH
    [[ -f "$SSH_DENY_CONF" ]] \
        && grep -qw "$ftp_user" "$SSH_DENY_CONF" \
        || sudo sed -i "s/^DenyUsers.*/& $ftp_user/" "$SSH_DENY_CONF"
    sudo systemctl reload sshd &>/dev/null || sudo systemctl reload ssh &>/dev/null
    log_ok "FTP user diblokir dari SSH."

    # vsftpd user config (set root FTP)
    echo "local_root=$domain_dir" | sudo tee "$VSFTPD_USER_DIR/$ftp_user" > /dev/null
    log_ok "vsftpd user config: root=$domain_dir"

    # Group
    getent group "$FTP_GROUP" &>/dev/null || { sudo groupadd "$FTP_GROUP"; log_ok "Group '$FTP_GROUP' dibuat."; }
    sudo usermod -aG "$FTP_GROUP" "$ftp_user"
    log_ok "FTP user masuk group '$FTP_GROUP'."

    # Deploy user ke group jika ada
    [[ -n "$deploy_user" ]] && id "$deploy_user" &>/dev/null && {
        sudo usermod -aG "$FTP_GROUP" "$deploy_user"
        log_ok "Deploy user '$deploy_user' masuk group '$FTP_GROUP'."
    }

    # Set kepemilikan & ACL
    sudo chown -R "www-data:$FTP_GROUP" "$domain_dir"
    sudo chmod -R 775 "$domain_dir"
    sudo chmod g+s "$domain_dir"

    sudo setfacl -R    -m "u:$ftp_user:rwx"    "$domain_dir"
    sudo setfacl -R -d -m "u:$ftp_user:rwx"    "$domain_dir"
    sudo setfacl -R    -m "u:www-data:rx"       "$domain_dir"
    sudo setfacl -R -d -m "u:www-data:rx"       "$domain_dir"
    [[ -n "$deploy_user" ]] && id "$deploy_user" &>/dev/null && {
        sudo setfacl -R    -m "u:$deploy_user:rwx" "$domain_dir"
        sudo setfacl -R -d -m "u:$deploy_user:rwx" "$domain_dir"
    }
    log_ok "ACL berhasil diset."
    return 0
}

# ================================================================
# BUAT DEPLOY USER (dipakai oleh create_site & create_ftp_only)
# ================================================================
_create_deploy_user() {
    local deploy_user="$1" domain="$2"
    local deploy_key_priv=""

    if ! id "$deploy_user" &>/dev/null; then
        sudo adduser "$deploy_user" --shell /bin/bash --gecos "" --disabled-password &>/dev/null
        sudo passwd -l "$deploy_user" &>/dev/null
        log_ok "Deploy user '$deploy_user' dibuat (hanya SSH key)."
    else
        log_warn "Deploy user '$deploy_user' sudah ada."
    fi

    local deploy_home
    deploy_home=$(getent passwd "$deploy_user" | cut -d: -f6)
    sudo mkdir -p "$deploy_home/.ssh"
    sudo chmod 700 "$deploy_home/.ssh"

    echo ""
    echo "   [1] Generate SSH keypair baru (private key ditampilkan untuk GitHub Secrets)"
    echo "   [2] Paste public key dari CI/CD"
    read -rp "   Pilih [1/2]: " KEY_MODE

    if [[ "$KEY_MODE" == "1" ]]; then
        local key_file="/tmp/deploy_key_$$"
        ssh-keygen -t ed25519 -C "deploy@$domain" -f "$key_file" -N "" &>/dev/null
        cat "${key_file}.pub" | sudo tee -a "$deploy_home/.ssh/authorized_keys" > /dev/null
        sudo chmod 600 "$deploy_home/.ssh/authorized_keys"
        sudo chown -R "$deploy_user:$deploy_user" "$deploy_home/.ssh"
        deploy_key_priv=$(cat "$key_file")
        rm -f "$key_file" "${key_file}.pub"
        log_ok "SSH keypair di-generate."
    elif [[ "$KEY_MODE" == "2" ]]; then
        echo "   Paste public key (ssh-ed25519 AAAA... atau ssh-rsa AAAA...):"
        read -r PUB_KEY
        if [[ -n "$PUB_KEY" ]]; then
            echo "$PUB_KEY" | sudo tee -a "$deploy_home/.ssh/authorized_keys" > /dev/null
            sudo chmod 600 "$deploy_home/.ssh/authorized_keys"
            sudo chown -R "$deploy_user:$deploy_user" "$deploy_home/.ssh"
            log_ok "Public key disimpan."
        else
            log_warn "Public key kosong, skip."
        fi
    fi

    echo "$deploy_key_priv"
}

# ================================================================
# MANAGE WEBSITE & FTP - SUB MENU
# ================================================================

# Tampilkan daftar singkat di bagian atas sub-menu
_show_site_list() {
    echo -e "   ${CYAN}--- DAFTAR WEBSITE & USER FTP ---${NC}"
    echo ""

    # Kolom header
    printf "   ${CYAN}%-35s %-9s %-20s %s${NC}\n" "Domain / Folder" "Mode" "FTP User" "Root FTP"
    printf "   %-35s %-9s %-20s %s\n" "-----------------------------------" "---------" "--------------------" "---------"

    local has_entry=0

    # 1. Website yang punya Nginx config
    local nginx_domains=()
    for f in /etc/nginx/sites-enabled/*; do
        [[ -f "$f" ]] || continue
        local d; d=$(basename "$f")
        [[ "$d" == "default" ]] && continue
        nginx_domains+=("$d")

        local mode="HTTP"
        grep -q "listen 443" "$f" 2>/dev/null && mode="HTTPS"

        local ftp_user="-"
        local ftp_root="-"
        if [[ -d "$VSFTPD_USER_DIR" ]]; then
            local uf
            uf=$(grep -rl "local_root=$BASE_DIR/$d" "$VSFTPD_USER_DIR" 2>/dev/null | head -1)
            if [[ -n "$uf" ]]; then
                ftp_user=$(basename "$uf")
                ftp_root=$(grep -oP "(?<=local_root=).*" "$uf" 2>/dev/null || echo "-")
            fi
        fi

        printf "   %-35s ${GREEN}%-9s${NC} %-20s %s\n" "$d" "[$mode]" "$ftp_user" "$ftp_root"
        has_entry=1
    done

    # 2. FTP-only: ada di vsftpd user_config_dir tapi TIDAK punya Nginx site
    if [[ -d "$VSFTPD_USER_DIR" ]]; then
        for uf in "$VSFTPD_USER_DIR"/*; do
            [[ -f "$uf" ]] || continue
            local ftp_user; ftp_user=$(basename "$uf")
            local ftp_root; ftp_root=$(grep -oP "(?<=local_root=).*" "$uf" 2>/dev/null || echo "-")

            # Tentukan folder name dari root path
            local folder_name; folder_name=$(basename "$ftp_root")

            # Skip jika folder ini sudah tampil via Nginx
            local already=0
            for nd in "${nginx_domains[@]}"; do
                [[ "$nd" == "$folder_name" ]] && { already=1; break; }
            done
            [[ $already -eq 1 ]] && continue

            printf "   %-35s ${YELLOW}%-9s${NC} %-20s %s\n" "$folder_name" "[FTP]" "$ftp_user" "$ftp_root"
            has_entry=1
        done
    fi

    if [[ $has_entry -eq 0 ]]; then
        echo "   (belum ada website / akun FTP terdaftar)"
    fi
    echo ""
}

show_manage_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         MANAGE WEBSITE & FTP                                  ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    _show_site_list
    echo " 1. Buat Website + FTP baru"
    echo " 2. Buat FTP saja (tanpa Website)"
    echo " 3. Hapus Website & FTP"
    echo " 4. Ubah Password FTP"
    echo " 5. Kembali ke menu utama"
    echo -e "${CYAN}================================================================${NC}"
}

# ----------------------------------------------------------------
# SUB MENU 1: BUAT WEBSITE + FTP
# ----------------------------------------------------------------
create_site() {
    clear
    echo -e "${CYAN}--- BUAT WEBSITE + FTP BARU ---${NC}"
    echo ""

    while true; do
        read -rp "   Domain (contoh: app.example.com): " DOMAIN
        [[ -n "$DOMAIN" ]] && break; log_err "Domain tidak boleh kosong."
    done

    while true; do
        read -rp "   Username FTP baru: " FTP_USER
        if [[ -z "$FTP_USER" ]]; then log_err "Username tidak boleh kosong."
        elif id "$FTP_USER" &>/dev/null; then log_err "User '$FTP_USER' sudah ada."
        else break; fi
    done

    while true; do
        read -rsp "   Password FTP: " FTP_PASS; echo
        read -rsp "   Konfirmasi  : " FTP_PASS2; echo
        if [[ -z "$FTP_PASS" ]]; then log_err "Password tidak boleh kosong."
        elif [[ "$FTP_PASS" != "$FTP_PASS2" ]]; then log_err "Password tidak cocok."
        else break; fi
    done

    while true; do
        read -rp "   Port Node.js API (contoh: 3000): " API_PORT
        [[ "$API_PORT" =~ ^[0-9]+$ ]] && break; log_err "Port harus angka."
    done

    echo ""
    echo "   Tipe website:"
    echo "   [1] SPA - React / Vue / Angular (try_files ke index.html)"
    echo "   [2] Static / HTML biasa"
    read -rp "   Pilih [1/2, default 1]: " SITE_TYPE
    [[ -z "$SITE_TYPE" ]] && SITE_TYPE="1"

    # Deploy user
    local DEPLOY_USER="" DEPLOY_KEY_PRIV=""
    echo ""
    if confirm "Buat deploy user untuk CI/CD (SSH key, tanpa password)?"; then
        DEPLOY_USER="deploy_$(domain_to_slug "$DOMAIN")"
    fi

    # SSL
    echo ""
    resolve_ssl_cert "$DOMAIN" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    local DOMAIN_DIR="$BASE_DIR/$DOMAIN"
    local FOLDER_FE="$DOMAIN_DIR/fe"
    local FOLDER_API="$DOMAIN_DIR/api"

    # Ringkasan
    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Domain      : $DOMAIN"
    echo "   FTP User    : $FTP_USER"
    echo "   Deploy User : ${DEPLOY_USER:-tidak dibuat}"
    echo "   Folder FE   : $FOLDER_FE"
    echo "   Folder API  : $FOLDER_API"
    echo "   API Port    : $API_PORT"
    echo "   Tipe Site   : $([ "$SITE_TYPE" == "1" ] && echo "SPA" || echo "Static")"
    echo "   SSL         : ${SSL_CERT:-HTTP only}"
    echo ""
    confirm "Lanjutkan?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    echo ""
    echo -e "${BLUE}[1/6] Membuat folder...${NC}"
    sudo mkdir -p "$FOLDER_FE" "$FOLDER_API" \
        && log_ok "Folder dibuat: $DOMAIN_DIR/{fe,api}" \
        || { log_err "Gagal membuat folder."; read -rp "   Enter untuk kembali..." _; return; }

    echo -e "${BLUE}[2/6] Membuat deploy user...${NC}"
    if [[ -n "$DEPLOY_USER" ]]; then
        DEPLOY_KEY_PRIV=$(_create_deploy_user "$DEPLOY_USER" "$DOMAIN")
    else
        log_info "Deploy user dilewati."
    fi

    echo -e "${BLUE}[3/6] Membuat FTP user & ACL...${NC}"
    _create_ftp_user "$FTP_USER" "$FTP_PASS" "$DOMAIN_DIR" "$DEPLOY_USER" \
        || { read -rp "   Enter untuk kembali..." _; return; }

    echo -e "${BLUE}[4/6] Membuat index.html placeholder...${NC}"
    if [[ ! -f "$FOLDER_FE/index.html" ]]; then
        local badge_text sub_text badge_color
        if [[ "$SITE_TYPE" == "1" ]]; then
            badge_text="SPA Ready"
            badge_color="#38bdf820; color: #38bdf8; border: 1px solid #38bdf840"
            sub_text="Upload hasil build React/Vue ke folder fe/ via FTP.<br>Semua route sudah diarahkan ke index.html."
        else
            badge_text="Website Aktif"
            badge_color="#22c55e20; color: #22c55e; border: 1px solid #22c55e40"
            sub_text="Upload file website ke folder fe/ via FTP."
        fi
        sudo tee "$FOLDER_FE/index.html" > /dev/null << HTMLEOF
<!DOCTYPE html><html lang="id">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$DOMAIN - Aktif</title>
<style>
* { margin:0; padding:0; box-sizing:border-box; }
body { font-family:'Segoe UI',sans-serif; background:#0f172a; color:#e2e8f0;
       display:flex; align-items:center; justify-content:center; min-height:100vh; }
.card { background:#1e293b; border:1px solid #334155; border-radius:12px;
        padding:48px 56px; text-align:center; max-width:480px; width:90%; }
.badge { display:inline-block; background:$badge_color;
         border-radius:999px; padding:4px 16px; font-size:13px; font-weight:600; margin-bottom:24px; }
h1 { font-size:22px; font-weight:700; color:#f1f5f9; margin-bottom:8px; }
.domain { font-size:15px; color:#38bdf8; margin-bottom:20px; word-break:break-all; }
p { font-size:14px; color:#94a3b8; line-height:1.6; }
.footer { margin-top:32px; font-size:12px; color:#475569; }
</style></head>
<body><div class="card">
    <div class="badge">$badge_text</div>
    <h1>Hosting Berhasil Dikonfigurasi</h1>
    <div class="domain">$DOMAIN</div>
    <p>$sub_text</p>
    <div class="footer">Powered by Nginx + vsftpd</div>
</div></body></html>
HTMLEOF
        log_ok "index.html placeholder dibuat."
    else
        log_warn "index.html sudah ada, tidak ditimpa."
    fi

    echo -e "${BLUE}[5/6] Menulis konfigurasi Nginx...${NC}"
    local NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
    local TRY_FILES
    [[ "$SITE_TYPE" == "1" ]] \
        && TRY_FILES='try_files $uri $uri/ /index.html' \
        || TRY_FILES='try_files $uri $uri/ =404'

    if [[ -n "$SSL_CERT" && -f "$SSL_CERT" ]]; then
        sudo tee "$NGINX_CONF" > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    root  $FOLDER_FE;
    index index.html index.htm;
    location / { $TRY_FILES; }
    location /api/ {
        proxy_pass         http://127.0.0.1:$API_PORT/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF
    else
        sudo tee "$NGINX_CONF" > /dev/null << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;
    root  $FOLDER_FE;
    index index.html index.htm;
    location / { $TRY_FILES; }
    location /api/ {
        proxy_pass         http://127.0.0.1:$API_PORT/;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINXEOF
    fi

    sudo ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/$DOMAIN"
    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        log_ok "Nginx config dibuat & direload."
    else
        log_err "Nginx config error! Cek: sudo nginx -t"
    fi

    echo -e "${BLUE}[6/6] Restart vsftpd...${NC}"
    sudo systemctl restart vsftpd &>/dev/null \
        && log_ok "vsftpd berhasil direstart." \
        || log_err "vsftpd gagal restart."

    # --- RINGKASAN ---
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN} RINGKASAN                                                  ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo "  Domain       : $DOMAIN"
    echo "  FTP User     : $FTP_USER"
    echo "  Folder       : $DOMAIN_DIR"
    echo "    /fe         -> Web root (Nginx)"
    echo "    /api        -> Folder API"
    if [[ -n "$SSL_CERT" ]]; then
        echo "  Akses Web    : https://$DOMAIN"
        echo "  Akses API    : https://$DOMAIN/api/..."
    else
        echo "  Akses Web    : http://$DOMAIN"
        echo "  Akses API    : http://$DOMAIN/api/..."
    fi
    if [[ -n "$DEPLOY_USER" ]]; then
        echo "  Deploy User  : $DEPLOY_USER (SSH, folder sama dengan FTP)"
        if [[ -n "$DEPLOY_KEY_PRIV" ]]; then
            echo ""
            echo -e "  ${YELLOW}!! SIMPAN PRIVATE KEY INI KE GITHUB SECRETS (SSH_PRIVATE_KEY) !!${NC}"
            echo ""
            echo "$DEPLOY_KEY_PRIV"
            echo ""
        fi
    fi
    echo -e "${CYAN}============================================================${NC}"
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# SUB MENU 2: BUAT FTP SAJA (tanpa Website)
# ----------------------------------------------------------------
create_ftp_only() {
    clear
    echo -e "${CYAN}--- BUAT FTP SAJA (tanpa Website) ---${NC}"
    echo ""

    while true; do
        read -rp "   Domain / nama folder (contoh: api.example.com): " DOMAIN
        [[ -n "$DOMAIN" ]] && break; log_err "Tidak boleh kosong."
    done

    while true; do
        read -rp "   Username FTP baru: " FTP_USER
        if [[ -z "$FTP_USER" ]]; then log_err "Tidak boleh kosong."
        elif id "$FTP_USER" &>/dev/null; then log_err "User '$FTP_USER' sudah ada."
        else break; fi
    done

    while true; do
        read -rsp "   Password FTP: " FTP_PASS; echo
        read -rsp "   Konfirmasi  : " FTP_PASS2; echo
        if [[ -z "$FTP_PASS" ]]; then log_err "Tidak boleh kosong."
        elif [[ "$FTP_PASS" != "$FTP_PASS2" ]]; then log_err "Password tidak cocok."
        else break; fi
    done

    local DEPLOY_USER=""
    echo ""
    if confirm "Buat deploy user untuk CI/CD?"; then
        DEPLOY_USER="deploy_$(domain_to_slug "$DOMAIN")"
    fi

    local DOMAIN_DIR="$BASE_DIR/$DOMAIN"

    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   FTP User    : $FTP_USER"
    echo "   Deploy User : ${DEPLOY_USER:-tidak dibuat}"
    echo "   Folder FTP  : $DOMAIN_DIR"
    echo "   (Nginx tidak dikonfigurasi)"
    echo ""
    confirm "Lanjutkan?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    echo ""
    echo -e "${BLUE}[1/3] Membuat folder...${NC}"
    sudo mkdir -p "$DOMAIN_DIR" \
        && log_ok "Folder dibuat: $DOMAIN_DIR" \
        || { log_err "Gagal membuat folder."; read -rp "   Enter untuk kembali..." _; return; }

    echo -e "${BLUE}[2/3] Membuat deploy user...${NC}"
    if [[ -n "$DEPLOY_USER" ]]; then
        local _key
        _key=$(_create_deploy_user "$DEPLOY_USER" "$DOMAIN")
        [[ -n "$_key" ]] && {
            echo ""
            echo -e "   ${YELLOW}!! PRIVATE KEY UNTUK GITHUB SECRETS !!${NC}"
            echo "$_key"
            echo ""
        }
    else
        log_info "Deploy user dilewati."
    fi

    echo -e "${BLUE}[3/3] Membuat FTP user & ACL...${NC}"
    _create_ftp_user "$FTP_USER" "$FTP_PASS" "$DOMAIN_DIR" "$DEPLOY_USER" \
        || { read -rp "   Enter untuk kembali..." _; return; }

    sudo systemctl restart vsftpd &>/dev/null \
        && log_ok "vsftpd berhasil direstart." \
        || log_err "vsftpd gagal restart."

    echo ""
    log_ok "Akun FTP '$FTP_USER' siap. Root FTP: $DOMAIN_DIR"
    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# SUB MENU 3: HAPUS WEBSITE & FTP
# ----------------------------------------------------------------
delete_site() {
    clear
    echo -e "${RED}--- HAPUS WEBSITE & FTP ---${NC}"
    echo ""
    _show_site_list

    read -rp "   Domain yang ingin dihapus: " DEL_DOMAIN
    [[ -z "$DEL_DOMAIN" ]] && { read -rp "   Enter untuk kembali..." _; return; }

    read -rp "   FTP Username terkait: " DEL_FTP_USER
    [[ -z "$DEL_FTP_USER" ]] && { read -rp "   Enter untuk kembali..." _; return; }

    local DEL_DEPLOY_USER="deploy_$(domain_to_slug "$DEL_DOMAIN")"

    echo ""
    log_warn "Yang akan dihapus:"
    echo "   - Nginx config : /etc/nginx/sites-available/$DEL_DOMAIN"
    echo "   - FTP user     : $DEL_FTP_USER"
    echo "   - vsftpd config: $VSFTPD_USER_DIR/$DEL_FTP_USER"
    id "$DEL_DEPLOY_USER" &>/dev/null && echo "   - Deploy user  : $DEL_DEPLOY_USER"
    echo ""
    confirm "Yakin hapus?" || { log_info "Dibatalkan."; read -rp "   Enter untuk kembali..." _; return; }

    echo ""

    # Hapus Nginx
    for f in "/etc/nginx/sites-enabled/$DEL_DOMAIN" "/etc/nginx/sites-available/$DEL_DOMAIN"; do
        [[ -f "$f" ]] && { sudo rm -f "$f"; log_ok "Dihapus: $f"; }
    done
    sudo nginx -t &>/dev/null && sudo systemctl reload nginx && log_ok "Nginx direload."

    # Hapus vsftpd user config & whitelist
    sudo rm -f "$VSFTPD_USER_DIR/$DEL_FTP_USER"
    [[ -f "$VSFTPD_USERLIST" ]] && sudo sed -i "/^$DEL_FTP_USER$/d" "$VSFTPD_USERLIST"
    log_ok "vsftpd user config & whitelist dibersihkan."

    # Hapus FTP user
    if id "$DEL_FTP_USER" &>/dev/null; then
        sudo deluser --remove-home "$DEL_FTP_USER" &>/dev/null
        log_ok "FTP user '$DEL_FTP_USER' dihapus."
    else
        log_warn "FTP user '$DEL_FTP_USER' tidak ditemukan."
    fi

    # Hapus dari SSH DenyUsers
    [[ -f "$SSH_DENY_CONF" ]] && {
        sudo sed -i "s/ $DEL_FTP_USER//g; s/$DEL_FTP_USER //g" "$SSH_DENY_CONF"
        sudo systemctl reload sshd &>/dev/null || sudo systemctl reload ssh &>/dev/null
        log_ok "Dihapus dari SSH DenyUsers."
    }

    # Hapus deploy user (opsional)
    id "$DEL_DEPLOY_USER" &>/dev/null && confirm "Hapus deploy user '$DEL_DEPLOY_USER' juga?" && {
        sudo deluser --remove-home "$DEL_DEPLOY_USER" &>/dev/null
        log_ok "Deploy user '$DEL_DEPLOY_USER' dihapus."
    }

    # Hapus folder (opsional)
    local DEL_FOLDER="$BASE_DIR/$DEL_DOMAIN"
    [[ -d "$DEL_FOLDER" ]] && confirm "Hapus folder data $DEL_FOLDER?" && {
        sudo rm -rf "$DEL_FOLDER"
        log_ok "Folder '$DEL_FOLDER' dihapus."
    }

    sudo systemctl restart vsftpd &>/dev/null && log_ok "vsftpd direstart."
    echo ""
    log_ok "Penghapusan selesai."
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# SUB MENU 4: UBAH PASSWORD FTP
# ----------------------------------------------------------------
change_password() {
    clear
    echo -e "${CYAN}--- UBAH PASSWORD FTP ---${NC}"
    echo ""
    _show_site_list

    read -rp "   Username FTP: " TARGET_USER
    if ! id "$TARGET_USER" &>/dev/null; then
        log_err "User '$TARGET_USER' tidak ditemukan."
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    while true; do
        read -rsp "   Password baru : " NEW_PASS; echo
        read -rsp "   Konfirmasi    : " NEW_PASS2; echo
        if [[ -z "$NEW_PASS" ]]; then log_err "Tidak boleh kosong."
        elif [[ "$NEW_PASS" != "$NEW_PASS2" ]]; then log_err "Password tidak cocok."
        else break; fi
    done

    echo "$TARGET_USER:$NEW_PASS" | sudo chpasswd \
        && log_ok "Password '$TARGET_USER' berhasil diubah." \
        || log_err "Gagal mengubah password."

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# MANAGE LOOP
# ----------------------------------------------------------------
manage_menu() {
    while true; do
        show_manage_menu
        read -rp "Pilih sub-menu (1-5): " SUB_CHOICE
        echo ""
        case "$SUB_CHOICE" in
            1) create_site ;;
            2) create_ftp_only ;;
            3) delete_site ;;
            4) change_password ;;
            5) return ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

# ================================================================
# MENU 5: MANAGE SSL
# ================================================================

# ----------------------------------------------------------------
# Helper: tampilkan semua sertifikat yang ada
# ----------------------------------------------------------------
_show_ssl_list() {
    echo -e "   ${CYAN}--- DAFTAR SERTIFIKAT SSL ---${NC}"
    echo ""

    local live_dir="/etc/letsencrypt/live"
    if [[ ! -d "$live_dir" ]]; then
        echo "   (direktori $live_dir tidak ditemukan)"
        echo ""
        return
    fi

    local found=0
    local now; now=$(date +%s)

    printf "   %-4s %-35s %-22s %-12s %s\n" "No" "Domain / Cert Name" "Domains (SAN)" "Expiry" "Status"
    printf "   %-4s %-35s %-22s %-12s %s\n" "----" "-----------------------------------" "----------------------" "------------" "------"

    local idx=0
    for cert_dir in "$live_dir"/*/; do
        [[ -f "$cert_dir/fullchain.pem" ]] || continue
        local cert_name; cert_name=$(basename "$cert_dir")
        [[ "$cert_name" == "README" ]] && continue

        # Ambil SAN domains dari sertifikat
        local san_domains
        san_domains=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -text 2>/dev/null \
            | grep -oP '(?<=DNS:)[^\s,]+' | tr '\n' ',' | sed 's/,$//')
        [[ -z "$san_domains" ]] && san_domains="-"

        # Tanggal expiry
        local expiry_str expiry_ts status_label
        expiry_str=$(openssl x509 -in "$cert_dir/fullchain.pem" -noout -enddate 2>/dev/null \
            | cut -d= -f2)
        expiry_ts=$(date -d "$expiry_str" +%s 2>/dev/null || echo "0")
        local days_left=$(( (expiry_ts - now) / 86400 ))
        local expiry_fmt; expiry_fmt=$(date -d "$expiry_str" +"%Y-%m-%d" 2>/dev/null || echo "unknown")

        if [[ $days_left -lt 0 ]]; then
            status_label="${RED}EXPIRED${NC}"
        elif [[ $days_left -le 14 ]]; then
            status_label="${RED}${days_left}h lagi${NC}"
        elif [[ $days_left -le 30 ]]; then
            status_label="${YELLOW}${days_left}h lagi${NC}"
        else
            status_label="${GREEN}${days_left}h lagi${NC}"
        fi

        printf "   %-4s %-35s %-22s %-12s " "$idx" "$cert_name" "${san_domains:0:22}" "$expiry_fmt"
        echo -e "$status_label"
        (( idx++ ))
        found=1
    done

    echo ""
    if [[ $found -eq 0 ]]; then
        echo "   (belum ada sertifikat Let's Encrypt)"
        echo ""
    fi
}

# ----------------------------------------------------------------
# SSL Sub 1: List / Detail sertifikat
# ----------------------------------------------------------------
ssl_list() {
    clear
    echo -e "${CYAN}--- LIST SERTIFIKAT SSL ---${NC}"
    echo ""
    _show_ssl_list

    local live_dir="/etc/letsencrypt/live"
    local cert_dirs=()
    while IFS= read -r d; do cert_dirs+=("$d"); done \
        < <(find "$live_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
            | grep -v "README" | sort)

    if [[ ${#cert_dirs[@]} -gt 0 ]]; then
        echo ""
        read -rp "   Masukkan nomor untuk melihat detail (Enter = skip): " SEL
        if [[ "$SEL" =~ ^[0-9]+$ && "$SEL" -lt ${#cert_dirs[@]} ]]; then
            local chosen="${cert_dirs[$SEL]}"
            echo ""
            echo -e "   ${CYAN}--- Detail: $(basename "$chosen") ---${NC}"
            sudo openssl x509 -in "$chosen/fullchain.pem" -noout \
                -subject -issuer -dates -fingerprint -ext subjectAltName 2>/dev/null \
                | sed 's/^/   /'
            echo ""
            echo "   File:"
            echo "     fullchain : $chosen/fullchain.pem"
            echo "     privkey   : $chosen/privkey.pem"
            echo "     chain     : $chosen/chain.pem"
            echo "     cert      : $chosen/cert.pem"
        fi
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# SSL Sub 2: Buat sertifikat baru
# ----------------------------------------------------------------
ssl_create() {
    clear
    echo -e "${CYAN}--- BUAT SERTIFIKAT SSL BARU ---${NC}"
    echo ""

    if [[ ! -f "$CF_CRED_FILE" ]]; then
        log_err "Cloudflare credentials belum ada."
        log_info "Jalankan Menu 2 (Setup Cloudflare API Token) terlebih dahulu."
        echo ""
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    echo "   Metode pembuatan:"
    echo "   [1] Cloudflare DNS (wildcard support, domain tidak perlu aktif)"
    echo "   [2] HTTP-01 Challenge (domain harus resolve ke server ini)"
    echo ""
    read -rp "   Pilih metode [1/2, default 1]: " METHOD
    [[ -z "$METHOD" ]] && METHOD="1"

    echo ""
    read -rp "   Domain utama (contoh: example.com): " MAIN_DOMAIN
    if [[ -z "$MAIN_DOMAIN" ]]; then
        log_err "Domain tidak boleh kosong."
        read -rp "   Tekan Enter untuk kembali..." _; return
    fi

    echo ""
    echo "   Tambahkan domain/subdomain lain? (kosongkan jika tidak ada)"
    echo "   Pisahkan dengan spasi. Contoh: www.example.com api.example.com"
    read -rp "   Domain tambahan: " EXTRA_DOMAINS_RAW

    read -rp "   Email untuk notifikasi Let's Encrypt [admin@$MAIN_DOMAIN]: " LE_EMAIL
    [[ -z "$LE_EMAIL" ]] && LE_EMAIL="admin@$MAIN_DOMAIN"

    # Bangun argumen -d
    local d_args="-d $MAIN_DOMAIN"
    for ed in $EXTRA_DOMAINS_RAW; do
        d_args="$d_args -d $ed"
    done

    # Tawarkan wildcard jika pakai CF DNS
    local add_wildcard="n"
    if [[ "$METHOD" == "1" ]]; then
        echo ""
        if confirm "Tambahkan wildcard *.$MAIN_DOMAIN?"; then
            d_args="$d_args -d *.$MAIN_DOMAIN"
            add_wildcard="y"
        fi
    fi

    echo ""
    echo -e "   ${YELLOW}--- Ringkasan ---${NC}"
    echo "   Metode      : $([ "$METHOD" == "1" ] && echo "Cloudflare DNS" || echo "HTTP-01")"
    echo "   Domain      : $MAIN_DOMAIN $EXTRA_DOMAINS_RAW$([ "$add_wildcard" == "y" ] && echo " *.$MAIN_DOMAIN")"
    echo "   Email       : $LE_EMAIL"
    echo ""
    confirm "Generate sertifikat sekarang?" || { read -rp "   Tekan Enter untuk kembali..." _; return; }

    echo ""
    if [[ "$METHOD" == "1" ]]; then
        log_info "Menjalankan certbot (DNS challenge)..."
        sudo certbot certonly \
            --dns-cloudflare \
            --dns-cloudflare-credentials "$CF_CRED_FILE" \
            $d_args \
            --non-interactive --agree-tos \
            -m "$LE_EMAIL"
    else
        log_info "Menjalankan certbot (HTTP challenge)..."
        sudo certbot certonly \
            --nginx \
            $d_args \
            --non-interactive --agree-tos \
            -m "$LE_EMAIL"
    fi

    echo ""
    local cert_path="/etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem"
    if [[ -f "$cert_path" ]]; then
        log_ok "Sertifikat berhasil dibuat!"
        echo ""
        echo "   Path sertifikat:"
        echo "     fullchain : /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem"
        echo "     privkey   : /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem"

        echo ""
        if confirm "Pasang sertifikat ini ke Nginx site sekarang?"; then
            _ssl_apply_to_nginx "$MAIN_DOMAIN" \
                "/etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem" \
                "/etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem"
        fi
    else
        log_err "Sertifikat gagal dibuat. Cek output certbot di atas."
    fi

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# Helper: pasang SSL ke konfigurasi Nginx yang sudah ada
# ----------------------------------------------------------------
_ssl_apply_to_nginx() {
    local cert_domain="$1" cert_path="$2" key_path="$3"

    # Temukan Nginx sites yang cocok atau pilih manual
    local nginx_sites=()
    while IFS= read -r f; do
        nginx_sites+=("$f")
    done < <(find /etc/nginx/sites-available -type f ! -name "default" | sort)

    if [[ ${#nginx_sites[@]} -eq 0 ]]; then
        log_warn "Tidak ada Nginx site ditemukan."
        return
    fi

    echo ""
    echo "   Pilih Nginx site yang akan dipasang SSL:"
    for i in "${!nginx_sites[@]}"; do
        local site_name; site_name=$(basename "${nginx_sites[$i]}")
        local has_ssl="HTTP"
        grep -q "listen 443" "${nginx_sites[$i]}" 2>/dev/null && has_ssl="HTTPS"
        echo "     [$i] $site_name [$has_ssl]"
    done
    echo "     [s] Skip"
    echo ""
    read -rp "   Pilih: " SITE_SEL

    [[ "$SITE_SEL" == "s" || -z "$SITE_SEL" ]] && return

    if ! [[ "$SITE_SEL" =~ ^[0-9]+$ && "$SITE_SEL" -lt ${#nginx_sites[@]} ]]; then
        log_err "Pilihan tidak valid."; return
    fi

    local target_conf="${nginx_sites[$SITE_SEL]}"
    local site_name; site_name=$(basename "$target_conf")

    # Backup
    sudo cp "$target_conf" "${target_conf}.bak.$(date +%Y%m%d%H%M%S)"
    log_ok "Backup config: ${target_conf}.bak.*"

    # Cek apakah sudah ada blok HTTPS
    if grep -q "listen 443" "$target_conf" 2>/dev/null; then
        # Update path cert yang ada
        sudo sed -i \
            -e "s|ssl_certificate .*;|ssl_certificate     $cert_path;|" \
            -e "s|ssl_certificate_key .*;|ssl_certificate_key $key_path;|" \
            "$target_conf"
        log_ok "Path sertifikat di-update pada config yang ada."
    else
        # Konversi HTTP-only ke HTTPS
        local server_name; server_name=$(grep -oP "(?<=server_name )[^;]+" "$target_conf" | head -1 | tr -d ' ')
        local root_dir;    root_dir=$(grep -oP "(?<=root )[^;]+"  "$target_conf" | head -1 | tr -d ' ')
        local index_dir;   index_dir=$(grep -oP "(?<=index )[^;]+" "$target_conf" | head -1)
        local locations;   locations=$(awk '/location /,/^}/' "$target_conf" 2>/dev/null | head -40)

        sudo tee "$target_conf" > /dev/null << SSLEOF
server {
    listen 80;
    server_name $server_name;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $server_name;
    ssl_certificate     $cert_path;
    ssl_certificate_key $key_path;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    root  $root_dir;
    index $index_dir;
$locations
}
SSLEOF
        log_ok "Config dikonversi ke HTTPS."
    fi

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        log_ok "Nginx berhasil direload dengan SSL baru."
    else
        log_err "Nginx config error setelah penerapan SSL!"
        log_warn "Cek: sudo nginx -t"
        log_warn "Backup tersedia di: ${target_conf}.bak.*"
    fi
}

# ----------------------------------------------------------------
# SSL Sub 3: Renew sertifikat
# ----------------------------------------------------------------
ssl_renew() {
    clear
    echo -e "${CYAN}--- RENEW SERTIFIKAT SSL ---${NC}"
    echo ""
    _show_ssl_list

    echo "   Pilihan renew:"
    echo "   [1] Renew semua sertifikat (certbot renew)"
    echo "   [2] Renew sertifikat tertentu"
    echo "   [3] Dry-run (simulasi, tanpa benar-benar renew)"
    echo ""
    read -rp "   Pilih [1/2/3]: " RENEW_CHOICE

    echo ""
    case "$RENEW_CHOICE" in
        1)
            log_info "Menjalankan certbot renew --all..."
            sudo certbot renew
            echo ""
            if [[ $? -eq 0 ]]; then
                log_ok "Renew selesai. Nginx akan direload..."
                sudo systemctl reload nginx &>/dev/null && log_ok "Nginx direload."
            else
                log_warn "Certbot renew mungkin ada error, periksa output di atas."
            fi
            ;;
        2)
            local live_dir="/etc/letsencrypt/live"
            local cert_dirs=()
            while IFS= read -r d; do cert_dirs+=("$d"); done \
                < <(find "$live_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
                    | grep -v "README" | sort)

            if [[ ${#cert_dirs[@]} -eq 0 ]]; then
                log_warn "Tidak ada sertifikat ditemukan."; echo ""
                read -rp "   Tekan Enter untuk kembali..." _; return
            fi

            echo "   Pilih sertifikat:"
            for i in "${!cert_dirs[@]}"; do
                echo "     [$i] $(basename "${cert_dirs[$i]}")"
            done
            echo ""
            read -rp "   Nomor: " CERT_SEL

            if [[ "$CERT_SEL" =~ ^[0-9]+$ && "$CERT_SEL" -lt ${#cert_dirs[@]} ]]; then
                local chosen_name; chosen_name=$(basename "${cert_dirs[$CERT_SEL]}")
                log_info "Renew: $chosen_name"
                sudo certbot renew --cert-name "$chosen_name" --force-renewal
                echo ""
                if [[ $? -eq 0 ]]; then
                    log_ok "Sertifikat '$chosen_name' berhasil diperbarui."
                    sudo systemctl reload nginx &>/dev/null && log_ok "Nginx direload."
                else
                    log_err "Gagal renew '$chosen_name'. Periksa output di atas."
                fi
            else
                log_err "Pilihan tidak valid."
            fi
            ;;
        3)
            log_info "Menjalankan dry-run certbot renew..."
            sudo certbot renew --dry-run
            echo ""
            log_info "Dry-run selesai. Tidak ada perubahan nyata."
            ;;
        *)
            log_err "Pilihan tidak valid."
            ;;
    esac

    echo ""
    read -rp "   Tekan Enter untuk kembali..." _
}

# ----------------------------------------------------------------
# SSL Menu Loop
# ----------------------------------------------------------------
show_ssl_menu() {
    clear
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}         MANAGE SSL                                            ${NC}"
    echo -e "${CYAN}================================================================${NC}"
    _show_ssl_list
    echo " 1. List & Detail Sertifikat"
    echo " 2. Buat Sertifikat Baru"
    echo " 3. Renew Sertifikat"
    echo " 4. Kembali ke menu utama"
    echo -e "${CYAN}================================================================${NC}"
}

ssl_menu() {
    while true; do
        show_ssl_menu
        read -rp "Pilih sub-menu (1-4): " SSL_CHOICE
        echo ""
        case "$SSL_CHOICE" in
            1) ssl_list ;;
            2) ssl_create ;;
            3) ssl_renew ;;
            4) return ;;
            *) echo -e "${RED}   Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

# ================================================================
# ENTRY POINT
# ================================================================
hosting_main() {
    while true; do
        show_main_menu
        read -rp "Pilih menu (1-6): " CHOICE
        echo ""
        case "$CHOICE" in
            1) check_deps ;;
            2) setup_cloudflare_creds ;;
            3) setup_vsftpd_global ;;
            4) manage_menu ;;
            5) ssl_menu ;;
            6) echo -e "${GREEN}Keluar. Sampai jumpa!${NC}"; exit 0 ;;
            *) echo -e "${RED}Pilihan tidak valid.${NC}"; sleep 1 ;;
        esac
    done
}

# Jalankan hanya jika file ini dieksekusi langsung (bukan di-source)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo -e "${YELLOW}Script membutuhkan root. Menjalankan ulang dengan sudo...${NC}"
        exec sudo bash "$0" "$@"
    fi
    hosting_main
fi
