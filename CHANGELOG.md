# Changelog

Semua perubahan penting pada project ini dicatat di file ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/),
dan project ini memakai [Semantic Versioning](https://semver.org/lang/id/).

> **Aturan:** setiap perubahan wajib menambahkan entri di sini dan memperbarui
> [ROUTEMAP.md](ROUTEMAP.md) bila menu/alur berubah. Lihat [CLAUDE.md](CLAUDE.md).

## [Unreleased]

### Added
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
