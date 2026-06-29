# Script Setup Server

> Panel manajemen server terpadu untuk Ubuntu/Debian -- Hosting, MongoDB, Node.js & PM2

## Fitur

| Modul | Fitur |
|-------|-------|
| Hosting Panel | vsftpd, Nginx, SSL (Certbot + Cloudflare DNS), Deploy User |
| MongoDB Manager | Setup, User, Database, Backup, Restore, Service, Replica Set, TLS |
| Node.js & PM2 | Install/Update Node.js, Install/Update PM2, Manage Aplikasi, Systemd Startup |
| Nginx Extra | WSS reverse proxy, MQTT TLS (stream termination), Auto-renew deploy-hook |

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
|   |-- nodejs-pm2.sh            # Node.js & PM2 manager
|   +-- nginx-extra.sh           # WSS + MQTT TLS (stream) + auto-renew hook
|
|-- .gitignore
+-- README.md
```

## Peta Menu (Route Map)

Pohon menu lengkap (sumber kebenaran tunggal) ada di **[ROUTEMAP.md](ROUTEMAP.md)**.
`setup-server.sh` adalah pintu masuk yang memanggil tiap modul; tiap modul juga bisa
dijalankan langsung lewat shim-nya.

Ringkasan modul tingkat atas:

```
setup-server  (Panel Terpadu)
|-- 1. Hosting Panel    -> modules/hosting.sh     (vsftpd + Nginx + SSL + Deploy User)
|-- 2. MongoDB Manager  -> modules/mongodb.sh     (setup, user, DB, backup, service, TLS)
|-- 3. Node.js & PM2    -> modules/nodejs-pm2.sh  (install/update, manage app, startup)
|-- 4. Nginx Extra      -> modules/nginx-extra.sh (WSS + MQTT TLS + auto-renew)
+-- 5. Keluar
```

> Riwayat perubahan ada di **[CHANGELOG.md](CHANGELOG.md)**. Aturan kontribusi
> (update route map & changelog tiap perubahan) ada di **[CLAUDE.md](CLAUDE.md)**.

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
