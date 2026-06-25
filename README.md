# Script Setup Server

> Panel manajemen server terpadu untuk Ubuntu/Debian -- Hosting, MongoDB, Node.js & PM2

## Fitur

| Modul | Fitur |
|-------|-------|
| Hosting Panel | vsftpd, Nginx, SSL (Certbot + Cloudflare DNS), Deploy User |
| MongoDB Manager | Setup, User, Database, Backup, Restore, Service, Replica Set, TLS |
| Node.js & PM2 | Install/Update Node.js, Install/Update PM2, Manage Aplikasi, Systemd Startup |

## Quick Start (Curl Online)

```bash
curl -fsSL https://raw.githubusercontent.com/Alis-Dev-idn/script-setup-server/main/install.sh | sudo bash
```

Setelah terpasang, jalankan panel utama:

```bash
setup-server
```

> **Catatan:** URL di atas mengambil dari branch `main`. Jika dapat error `404`,
> pastikan branch `main` ada di repo (lihat [Troubleshooting](#troubleshooting)).

## Struktur Project

```
script-setup-server/
|-- setup-server.sh              # Entry point utama (Panel Terpadu)
|-- install.sh                   # Online installer (curl-able)
|-- setup-hosting.sh             # Shim -> modules/hosting.sh
|-- mongodb-manager.sh           # Shim -> modules/mongodb.sh
|-- nodejs-pm2-manager.sh        # Shim -> modules/nodejs-pm2.sh
|
|-- lib/
|   |-- common.sh                # Warna, logging, helper umum, spinner
|   |-- cloudflare.sh            # Cloudflare API token management
|   +-- ssl.sh                   # SSL certificate detection & management
|
|-- modules/
|   |-- hosting.sh               # vsftpd + Nginx + SSL + Deploy User
|   |-- mongodb.sh               # MongoDB: setup, user, DB, backup
|   +-- nodejs-pm2.sh            # Node.js & PM2 manager
|
|-- .gitignore
+-- README.md
```

## Peta Menu (Route Map)

Navigasi panel berbentuk pohon menu. `setup-server.sh` adalah pintu masuk yang
memanggil tiap modul; tiap modul juga bisa dijalankan langsung lewat shim-nya.

```
setup-server  (Panel Terpadu)
|
|-- 1. Hosting Panel                       -> modules/hosting.sh (hosting_main)
|     |-- 1. Cek & Install Dependensi      (vsftpd, nginx, certbot, acl, openssl, ufw, dns-cloudflare)
|     |-- 2. Setup Cloudflare API Token    -> lib/cloudflare.sh (setup_cloudflare_creds)
|     |-- 3. Konfigurasi vsftpd Server     (sekali saja: port, pasv, FTPS, pasv_address)
|     |-- 4. Manage Website & FTP
|     |     |-- 1. Buat Website + FTP baru (folder fe/api, deploy user, Nginx, SSL)
|     |     |-- 2. Buat FTP saja (tanpa Website)
|     |     |-- 3. Hapus Website & FTP
|     |     |-- 4. Ubah Password FTP
|     |     +-- 5. Kembali
|     |-- 5. Manage SSL
|     |     |-- 1. List & Detail Sertifikat
|     |     |-- 2. Buat Sertifikat Baru    (Cloudflare DNS / HTTP-01, wildcard)
|     |     |-- 3. Renew Sertifikat        (semua / tertentu / dry-run)
|     |     +-- 4. Kembali
|     +-- 6. Keluar
|
|-- 2. MongoDB Manager                     -> modules/mongodb.sh (mongodb_main)
|     |   (config dibaca dari /etc/mongod.conf; kredensial admin diinput per sesi)
|     |-- 1. Setup MongoDB                  (versi, port, auth, bind, replica set, TLS/SSL)
|     |-- 2. Manage User
|     |     |-- 1. Buat user baru
|     |     |-- 2. Update user (password & role)
|     |     |-- 3. Reset password
|     |     |-- 4. Hapus user
|     |     |-- 5. Ganti role
|     |     +-- 6. Kembali
|     |-- 3. Manage Database
|     |     |-- 1. Lihat collections dalam database
|     |     |-- 2. Buat database baru
|     |     |-- 3. Hapus database
|     |     |-- 4. Buat collection baru
|     |     |-- 5. Hapus collection
|     |     +-- 6. Kembali
|     |-- 4. Backup database                (mongodump + kompres .tar.gz)
|     |-- 5. Restore database               (mongorestore dari .tar.gz/direktori)
|     |-- 6. Service MongoDB
|     |     |-- 1. Lihat log terbaru (50 baris)
|     |     |-- 2. Start
|     |     |-- 3. Stop
|     |     |-- 4. Restart
|     |     |-- 5. Reload konfigurasi
|     |     +-- 6. Kembali
|     +-- 7. Keluar
|
|-- 3. Node.js & PM2                        -> modules/nodejs-pm2.sh (nodejs_pm2_main)
|     |-- 1. Install / Reinstall Node.js    (18 / 20 / 22)
|     |-- 2. Install / Reinstall PM2
|     |-- 3. Update Node.js
|     |-- 4. Update PM2 & Process
|     |-- 5. Status Node.js & PM2
|     |-- 6. Manage Aplikasi (PM2)
|     |     |-- 1. Start aplikasi baru
|     |     |-- 2. Stop aplikasi
|     |     |-- 3. Restart aplikasi
|     |     |-- 4. Delete aplikasi dari PM2
|     |     |-- 5. Lihat log aplikasi
|     |     |-- 6. Lihat detail aplikasi (monit)
|     |     |-- 7. Simpan daftar aplikasi (pm2 save)
|     |     +-- 8. Kembali
|     |-- 7. Konfigurasi
|     |     |-- 1. Pilih versi Node.js default
|     |     |-- 2. Setup alias/shortcut
|     |     |-- 3. Setup PM2 startup (systemd)
|     |     |-- 4. Hapus Node.js & PM2 (uninstall total)
|     |     +-- 5. Kembali
|     +-- 8. Keluar
|
+-- 4. Keluar
```

## Arsitektur Singkat

- **`lib/*`** = library bersama yang di-`source` oleh semua modul (warna, logging,
  spinner loading, deteksi/resolusi sertifikat SSL, dan Cloudflare token).
- **`modules/*`** = logika tiap panel. Tiap modul punya guard `BASH_SOURCE` sehingga
  aman di-`source` oleh `setup-server.sh` (tidak auto-run) maupun dijalankan langsung.
- **shim** (`setup-hosting.sh`, `mongodb-manager.sh`, `nodejs-pm2-manager.sh`) =
  pembungkus tipis agar perintah lama tetap jalan, hanya meneruskan ke `modules/*`.

### Catatan Modul MongoDB

- Konfigurasi koneksi (port, bind, auth, replica set) **dibaca langsung dari
  `/etc/mongod.conf`** sebagai sumber kebenaran -- bukan dari file cache.
- Kredensial admin **diminta tiap sesi** dan diverifikasi koneksinya; password
  **tidak** disimpan ke disk.
- Operasi yang butuh koneksi DB (list user/database, backup, restore, buat admin,
  init replica set) menampilkan **indikator loading (spinner)**.

## Menjalankan Per Modul

```bash
bash setup-server.sh            # panel terpadu (pilih modul)
bash setup-hosting.sh           # langsung ke Hosting Panel
bash mongodb-manager.sh         # langsung ke MongoDB Manager
bash nodejs-pm2-manager.sh      # langsung ke Node.js & PM2
```

Semua script butuh akses `root` (akan otomatis `sudo` ulang bila perlu).

## Troubleshooting

### Quick Start (curl) error `404`

URL installer menunjuk ke branch **`main`**:
`.../script-setup-server/main/install.sh`. Error `404` muncul jika branch `main`
belum ada di GitHub (mis. repo masih memakai `master`).

Solusi:

1. Pastikan branch `main` sudah ter-push:
   ```bash
   git push -u origin main
   ```
2. Jadikan `main` sebagai **default branch** di GitHub:
   **Settings → General → Default branch → ganti ke `main`**.
3. (Opsional) hapus branch lama setelah default dipindah:
   ```bash
   git push origin --delete master
   ```

Verifikasi cepat URL raw dapat diakses:

```bash
curl -fsSL -o /dev/null -w "%{http_code}\n" \
  https://raw.githubusercontent.com/Alis-Dev-idn/script-setup-server/main/install.sh
# harus mengembalikan 200
```
