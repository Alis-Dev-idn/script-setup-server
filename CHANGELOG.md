# Changelog

Semua perubahan penting pada project ini dicatat di file ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/),
dan project ini memakai [Semantic Versioning](https://semver.org/lang/id/).

> **Aturan:** setiap perubahan wajib menambahkan entri di sini dan memperbarui
> [ROUTEMAP.md](ROUTEMAP.md) bila menu/alur berubah. Lihat [CLAUDE.md](CLAUDE.md).

## [Unreleased]

### Fixed
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
