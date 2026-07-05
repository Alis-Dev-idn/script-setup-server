# Changelog

Semua perubahan penting pada project ini dicatat di file ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/),
dan project ini memakai [Semantic Versioning](https://semver.org/lang/id/).

> **Aturan:** setiap perubahan wajib menambahkan entri di sini dan memperbarui
> [ROUTEMAP.md](ROUTEMAP.md) bila menu/alur berubah. Lihat [CLAUDE.md](CLAUDE.md).

## [Unreleased]

### Fixed
- **MongoDB Manager — Setup**: `setup_mongodb()` gagal start mongod saat auth +
  replica set diaktifkan bersamaan — MongoDB mewajibkan `security.keyFile` bila
  `authorization: enabled` dipakai bersama `replication.replSetName`
  (`BadValue: security.keyFile is required when authorization is enabled with
  replica sets`), tapi skrip tidak pernah membuatnya. Kini keyFile dibuat otomatis
  (`openssl rand -base64 756`, `/var/lib/mongodb/keyfile`, `chmod 400`) untuk
  kombinasi tersebut. Skrip juga sekarang memverifikasi `mongod` benar-benar
  `active` sebelum menampilkan banner "Berhasil Diinstal!" — sebelumnya banner
  sukses tetap tampil walau service gagal start.
- **MongoDB Manager — Restore**: `restore_db()` salah membangun path source
  `mongorestore` dari nama database **tujuan** yang diketik user, bukan nama
  database **asli** di dalam backup — menyebabkan `mongorestore target ... invalid:
  stat ...: no such file or directory` saat path backup langsung menunjuk direktori
  dump flat (tanpa subfolder) atau saat merestore dengan nama database berbeda
  (rename). Skrip juga tidak pernah mengecek exit code `mongorestore`, sehingga tetap
  melaporkan "Restore selesai!" walau proses gagal total (0 dokumen ter-restore).
- **Hosting/Nginx API proxy**: hilangkan trailing slash pada `proxy_pass`
  (`http://127.0.0.1:$API_PORT/` → `http://127.0.0.1:$API_PORT`) di config website
  agar path `/api/...` diteruskan utuh ke backend (trailing slash bikin routing salah).
- **MQTT TLS**: perjelas bahwa file `streams-*/mqtt-*.conf` adalah STREAM server yang
  di-include di dalam `stream {}` (tambah komentar di file), serta tambah diagnostik
  pasca-setup: cek port TLS sudah `LISTEN` dan broker backend punya listener —
  memberi peringatan bila broker tidak listen di port tujuan (penyebab umum mqtts
  gagal connect meski konfigurasi TLS benar).
- **MQTT TLS**: deteksi modul Nginx `stream` kini membedakan build statis vs
  `--with-stream=dynamic` yang belum di-`load_module` (penyebab `unknown directive
  "stream"` walau `--with-stream` terlihat di `nginx -V`).
- **MQTT TLS**: saat `nginx -t` gagal, pesan error asli kini **ditampilkan** (tidak
  lagi dibuang ke `/dev/null`) dan symlink `streams-enabled` yang baru dibuat
  **dinonaktifkan otomatis** agar konfigurasi Nginx yang berjalan tetap valid.

### Added
- **MongoDB Manager — Service**: tambah opsi "Perbaiki keyFile (auth + replica set)"
  di menu Service MongoDB (nomor 6), untuk memperbaiki instalasi lama yang sudah
  terlanjur gagal start karena kombinasi auth + replica set tanpa `security.keyFile`
  (lihat entri Fixed di atas) — tanpa perlu mengulang seluruh wizard Setup MongoDB
  (yang akan minta ulang password admin, dsb). Backup `/etc/mongod.conf` dibuat
  otomatis sebelum diubah.
- **MongoDB Manager — Setup**: tambah pengaturan cache memory WiredTiger (heap) saat
  instalasi. Mendeteksi total RAM server (`/proc/meminfo`) dan memberi rekomendasi
  otomatis mengikuti formula resmi MongoDB (`(RAM GB - 1) / 2`, minimum 0.25 GB), operator
  bisa menerima rekomendasi atau input ukuran sendiri. Nilai ditulis ke
  `storage.wiredTiger.engineConfig.cacheSizeGB` di `/etc/mongod.conf` dan ditampilkan di
  ringkasan sebelum instalasi, ringkasan hasil instalasi, serta status di menu
  **Service MongoDB**.
- **MongoDB Manager — Backup & Restore**: kini menampilkan preview isi data sebelum
  eksekusi. Backup menampilkan daftar collection dari database yang dipilih (via
  `listCollections`); restore mendeteksi struktur backup (`.tar.gz` atau direktori) dan
  menampilkan database/collection yang ditemukan sebelum minta konfirmasi `RESTORE`.
  Restore juga kini mendukung rename database (pilih database sumber, lalu nama
  database tujuan terpisah) dan folder dump flat (satu database tanpa subfolder).
- Modul **Nginx Extra** (`modules/nginx-extra.sh`), menu utama nomor 4:
  - **WSS Reverse Proxy** dua mode:
    - Menempel ke domain HTTPS yang **sudah ada** (mis. `wss://<domain>/ws`) dengan
      menyisipkan blok `location` (backup + auto-rollback bila `nginx -t` gagal).
    - Membuat **domain khusus baru** (server block `80 -> 443`).
    - Path & port backend bisa diinput user, default `/ws` (existing) / `/` (baru)
      dan port `3001`. Header upgrade + timeout panjang untuk koneksi WebSocket.
  - **MQTT TLS** via Nginx **stream** termination (default `mqtts 8883` -> broker
    plain `127.0.0.1:1883`); otomatis memasang `libnginx-mod-stream` & menyuntik
    blok `stream{}` ke `nginx.conf` bila perlu.
  - **Auto-Renew Deploy-Hook** certbot (`renewal-hooks/deploy/reload-services.sh`)
    yang reload Nginx & Mosquitto mengikuti sertifikat utama Let's Encrypt.
  - Submenu List & Hapus konfigurasi; setiap pembuatan menampilkan **ringkasan**.
- Dokumen tata kelola repo: `ROUTEMAP.md` (route map kanonik), `CHANGELOG.md`,
  `CLAUDE.md` (aturan kontribusi).

### Changed
- `setup-server.sh`: menu utama menambah `4. Nginx Extra`, opsi Keluar menjadi `5`.
- `README.md`: tabel fitur, struktur project, dan bagian Peta Menu kini menunjuk ke
  `ROUTEMAP.md`.
