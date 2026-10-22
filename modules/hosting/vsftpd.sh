#!/bin/bash
# ============================================================
#  modules/hosting/vsftpd.sh — Konfigurasi vsftpd & FTP User
# ============================================================
[[ -n "${_HOSTING_VSFTPD_LOADED:-}" ]] && return 0
_HOSTING_VSFTPD_LOADED=1

BASE_DIR="/var/www"
VSFTPD_CONF="/etc/vsftpd.conf"
VSFTPD_USER_DIR="/etc/vsftpd/users"
VSFTPD_USERLIST="/etc/vsftpd/userlist"
SSH_DENY_CONF="/etc/ssh/sshd_config.d/deny-ftp-users.conf"
FTP_GROUP="ftpgroup"

setup_vsftpd_global() {
    clear
    echo -e "${CYAN}--- KONFIGURASI VSFTPD SERVER ---${NC}"
    echo -e "   ${YELLOW}Jalankan sekali saja saat pertama setup server.${NC}\n"

    local cur_port cur_pasv_min cur_pasv_max
    cur_port=$(grep -oP "(?<=^listen_port=)\d+" "$VSFTPD_CONF" 2>/dev/null || echo "21")
    cur_pasv_min=$(grep -oP "(?<=^pasv_min_port=)\d+" "$VSFTPD_CONF" 2>/dev/null || echo "49000")
    cur_pasv_max=$(grep -oP "(?<=^pasv_max_port=)\d+" "$VSFTPD_CONF" 2>/dev/null || echo "49100")

    echo "   Konfigurasi saat ini: port=$cur_port, pasv=$cur_pasv_min-$cur_pasv_max\n"
    local ftp_port="" pasv_min="" pasv_max=""
    read -rp "   Port FTP        (Enter = $cur_port)      : " ftp_port; [[ -z "$ftp_port" ]] && ftp_port="$cur_port"
    read -rp "   Passive port MIN (Enter = $cur_pasv_min) : " pasv_min; [[ -z "$pasv_min" ]] && pasv_min="$cur_pasv_min"
    read -rp "   Passive port MAX (Enter = $cur_pasv_max) : " pasv_max; [[ -z "$pasv_max" ]] && pasv_max="$cur_pasv_max"

    local vsftpd_ssl_cert="" vsftpd_ssl_key=""
    _select_vsftpd_ssl vsftpd_ssl_cert vsftpd_ssl_key

    local public_ip="" pasv_addr=""
    _detect_public_ip public_ip pasv_addr

    echo ""
    confirm "Terapkan konfigurasi vsftpd?" || { read -rp "   Tekan Enter untuk kembali..." _; return 0; }

    _apply_vsftpd_config "$ftp_port" "$pasv_min" "$pasv_max" "$vsftpd_ssl_cert" "$vsftpd_ssl_key" "$pasv_addr"
    _apply_vsftpd_firewall "$ftp_port" "$pasv_min" "$pasv_max"

    sudo systemctl restart vsftpd &>/dev/null \
        && log_ok "vsftpd berhasil direstart." \
        || log_err "vsftpd gagal restart. Cek: sudo systemctl status vsftpd"

    echo -e "\n   ${CYAN}Port yang perlu dibuka di firewall/router/cloud:${NC}"
    echo "     TCP $ftp_port          : FTP Control"
    echo "     TCP 20                 : FTP Active Data (opsional)"
    echo "     TCP $pasv_min-$pasv_max : FTP Passive Data"
    echo "     TCP 80 & 443           : HTTP & HTTPS\n"
    read -rp "   Tekan Enter untuk kembali..." _
}

_select_vsftpd_ssl() {
    local cert_var="$1" key_var="$2"
    echo ""
    if ! confirm "Aktifkan FTPS (SSL untuk vsftpd)?"; then return 0; fi

    local cert_dirs=()
    while IFS= read -r d; do cert_dirs+=("$d"); done \
        < <(find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

    local cert_sel="" _raw=""
    if [[ ${#cert_dirs[@]} -gt 0 ]]; then
        echo "   Cert tersedia:"
        for i in "${!cert_dirs[@]}"; do
            echo "     [$i] ${cert_dirs[$i]}"
        done
        echo "     [m] Input manual"
        read -rp "   Pilih: " cert_sel
        if [[ "$cert_sel" == "m" ]]; then
            read -rp "   Path fullchain.pem: " _raw; eval "$cert_var=\"\$(normalize_path \"\$_raw\")\""
            read -rp "   Path privkey.pem  : " _raw; eval "$key_var=\"\$(normalize_path \"\$_raw\")\""
        elif [[ "$cert_sel" =~ ^[0-9]+$ && "$cert_sel" -lt ${#cert_dirs[@]} ]]; then
            eval "$cert_var=\"${cert_dirs[$cert_sel]}/fullchain.pem\""
            eval "$key_var=\"${cert_dirs[$cert_sel]}/privkey.pem\""
        fi
    else
        log_warn "Tidak ada Let's Encrypt cert ditemukan."
        read -rp "   Path fullchain.pem (kosong = skip): " _raw
        eval "$cert_var=\"\$(normalize_path \"\$_raw\")\""
        local cur_cert; eval "cur_cert=\"\$$cert_var\""
        if [[ -n "$cur_cert" ]]; then
            read -rp "   Path privkey.pem: " _raw
            eval "$key_var=\"\$(normalize_path \"\$_raw\")\""
        fi
    fi
}

_detect_public_ip() {
    local ip_var="$1" addr_var="$2"
    log_info "Mendeteksi IP publik server..."
    local detected_ip=""
    detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 5 https://ifconfig.me 2>/dev/null \
        || hostname -I 2>/dev/null | awk '{print $1}')

    local user_addr=""
    if [[ -n "$detected_ip" ]]; then
        log_ok "IP terdeteksi: $detected_ip"
        read -rp "   pasv_address (Enter = $detected_ip, ketik manual jika beda): " user_addr
        [[ -z "$user_addr" ]] && user_addr="$detected_ip"
    else
        log_warn "Gagal deteksi IP otomatis."
        read -rp "   Masukkan IP publik server untuk pasv_address: " user_addr
    fi
    eval "$ip_var=\"\$detected_ip\""
    eval "$addr_var=\"\$user_addr\""
}

_apply_vsftpd_config() {
    local ftp_port="$1" pasv_min="$2" pasv_max="$3" ssl_cert="$4" ssl_key="$5" pasv_addr="$6"

    getent group "$FTP_GROUP" &>/dev/null || { sudo groupadd "$FTP_GROUP"; log_ok "Group '$FTP_GROUP' dibuat."; }
    sudo mkdir -p "$VSFTPD_USER_DIR"
    [[ -f "$VSFTPD_USERLIST" ]] || sudo touch "$VSFTPD_USERLIST"
    sudo mkdir -p "$(dirname "$SSH_DENY_CONF")"
    [[ -f "$SSH_DENY_CONF" ]] || echo "DenyUsers" | sudo tee "$SSH_DENY_CONF" > /dev/null

    [[ -f "$VSFTPD_CONF" ]] && {
        sudo cp "$VSFTPD_CONF" "${VSFTPD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
        log_ok "Backup vsftpd.conf lama disimpan."
    }

    local ssl_block=""
    if [[ -n "$ssl_cert" && -f "$ssl_cert" ]]; then
        ssl_block="ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=NO
force_local_logins_ssl=NO
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=$ssl_cert
rsa_private_key_file=$ssl_key
require_ssl_reuse=NO
ssl_ciphers=HIGH"
    else
        ssl_block="ssl_enable=NO"
    fi

    local pasv_addr_line=""
    [[ -n "$pasv_addr" ]] && pasv_addr_line="pasv_address=$pasv_addr"

    sudo tee "$VSFTPD_CONF" > /dev/null << EOF
# vsftpd.conf - dikelola oleh script-setup-server
listen=YES
listen_ipv6=NO
listen_port=$ftp_port
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
pasv_min_port=$pasv_min
pasv_max_port=$pasv_max
$pasv_addr_line
pasv_promiscuous=NO
$ssl_block
EOF
    log_ok "vsftpd.conf berhasil ditulis."
}

_apply_vsftpd_firewall() {
    local ftp_port="$1" pasv_min="$2" pasv_max="$3"
    if command -v ufw &>/dev/null; then
        sudo ufw allow "$ftp_port/tcp"             comment "FTP Control"      &>/dev/null
        sudo ufw allow 20/tcp                      comment "FTP Active Data"  &>/dev/null
        sudo ufw allow "$pasv_min:$pasv_max/tcp"  comment "FTP Passive Data" &>/dev/null
        sudo ufw allow 80/tcp                      comment "HTTP"             &>/dev/null
        sudo ufw allow 443/tcp                     comment "HTTPS"            &>/dev/null
        log_ok "UFW rules ditambahkan."
    fi
}

_create_ftp_user() {
    local ftp_user="$1" ftp_pass="$2" domain_dir="$3" deploy_user="$4"

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

    grep -qx "$ftp_user" "$VSFTPD_USERLIST" 2>/dev/null \
        || echo "$ftp_user" | sudo tee -a "$VSFTPD_USERLIST" > /dev/null
    log_ok "User masuk vsftpd whitelist."

    [[ -f "$SSH_DENY_CONF" ]] \
        && grep -qw "$ftp_user" "$SSH_DENY_CONF" \
        || sudo sed -i "s/^DenyUsers.*/& $ftp_user/" "$SSH_DENY_CONF"
    sudo systemctl reload sshd &>/dev/null || sudo systemctl reload ssh &>/dev/null
    log_ok "FTP user diblokir dari SSH."

    echo "local_root=$domain_dir" | sudo tee "$VSFTPD_USER_DIR/$ftp_user" > /dev/null
    log_ok "vsftpd user config: root=$domain_dir"

    getent group "$FTP_GROUP" &>/dev/null || { sudo groupadd "$FTP_GROUP"; log_ok "Group '$FTP_GROUP' dibuat."; }
    sudo usermod -aG "$FTP_GROUP" "$ftp_user"
    log_ok "FTP user masuk group '$FTP_GROUP'."

    [[ -n "$deploy_user" ]] && id "$deploy_user" &>/dev/null && {
        sudo usermod -aG "$FTP_GROUP" "$deploy_user"
        log_ok "Deploy user '$deploy_user' masuk group '$FTP_GROUP'."
    }

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

    local deploy_home=""
    deploy_home=$(getent passwd "$deploy_user" | cut -d: -f6)
    sudo mkdir -p "$deploy_home/.ssh"
    sudo chmod 700 "$deploy_home/.ssh"

    echo ""
    echo "   [1] Generate SSH keypair baru (private key ditampilkan untuk GitHub Secrets)"
    echo "   [2] Paste public key dari CI/CD"
    local key_mode=""
    read -rp "   Pilih [1/2]: " key_mode

    if [[ "$key_mode" == "1" ]]; then
        local key_file="/tmp/deploy_key_$$"
        ssh-keygen -t ed25519 -C "deploy@$domain" -f "$key_file" -N "" &>/dev/null
        cat "${key_file}.pub" | sudo tee -a "$deploy_home/.ssh/authorized_keys" > /dev/null
        sudo chmod 600 "$deploy_home/.ssh/authorized_keys"
        sudo chown -R "$deploy_user:$deploy_user" "$deploy_home/.ssh"
        deploy_key_priv=$(cat "$key_file")
        rm -f "$key_file" "${key_file}.pub"
        log_ok "SSH keypair di-generate."
    elif [[ "$key_mode" == "2" ]]; then
        local pub_key=""
        echo "   Paste public key (ssh-ed25519 AAAA... atau ssh-rsa AAAA...):"
        read -r pub_key
        if [[ -n "$pub_key" ]]; then
            echo "$pub_key" | sudo tee -a "$deploy_home/.ssh/authorized_keys" > /dev/null
            sudo chmod 600 "$deploy_home/.ssh/authorized_keys"
            sudo chown -R "$deploy_user:$deploy_user" "$deploy_home/.ssh"
            log_ok "Public key disimpan."
        else
            log_warn "Public key kosong, skip."
        fi
    fi

    echo "$deploy_key_priv"
}
