# Changelog

Semua perubahan penting pada project ini dicatat di file ini.
Format mengikuti [Keep a Changelog](https://keepachangelog.com/id/1.1.0/),
dan project ini memakai [Semantic Versioning](https://semver.org/lang/id/).

> **Aturan:** setiap perubahan wajib menambahkan entri di sini dan memperbarui
> [route-map.md](route-map.md) bila menu/alur berubah. Lihat [07-dokumentasi-changelog.md](../.agent/rules/07-dokumentasi-changelog.md).

---

## [Unreleased]

## [1.1.0] - 2026-10-22

### Added
- **Arsitektur Modular Domain**: Pemecahan arsitektur monolitik script Bash menjadi submodul domain terisolasi di `modules/hosting/`, `modules/mongodb/`, `modules/nodejs-pm2/`, dan `modules/nginx-extra/`. Seluruh file baru berukuran < 350 baris dan fungsi individual < 50 baris.
- **Komponen CLI UI/UX Modern (`lib/ui.sh`)**: Implementasi spinner in-place satu baris anti-wall-of-text, frame card menu ANSI 256 colors, dan visualisasi status yang rapi dan konsisten.
- **Standarisasi Dokumentasi Resmi di `docs/`**: Integrasi dokumen arsitektur dan tata kelola (`docs/route-map.md`, `docs/technical-architecture-blueprint.md`, `docs/cli-ux-specification.md`, `docs/requirements-refactor-besar.md`, dan `docs/adr/ADR-001-modularisasi-script-setup-server.md`).

### Changed
- **Enkapsulasi Variabel & Scoping**: Seluruh variabel internal dalam modul dideklarasikan menggunakan keyword `local` untuk mencegah *global scope pollution* saat di-source bersamaan.
- **Entry Points & Shims**: `setup-server.sh`, `install.sh`, dan root shims (`setup-hosting.sh`, `mongodb-manager.sh`, `nodejs-pm2-manager.sh`) diperbarui mengarah ke router modular domain baru tanpa *breaking changes* bagi pengguna.
- **Sentralisasi Dokumentasi**: Seluruh dokumentasi yang tercecer di root (`ROUTEMAP.md`, `CHANGELOG.md`, `requirements/`, `design/`) telah dipindahkan dan ditertibkan ke dalam direktori resmi `docs/`.

## [1.0.0] - 2026-07-05

### Fixed
- **Node.js & PM2 Manager**: `install_nodejs()`/`update_nodejs()` menyimpan GPG key NodeSource mentah langsung sebagai file `.gpg` tanpa di-`dearmor` — diperbaiki dengan `curl ... | sudo gpg --dearmor -o ...`.
- **Node.js & PM2 Manager**: Penambahan pause dan penanganan exit code pada langkah kritikal `apt-get`, `curl`, dan `npm install -g`.
- **Node.js & PM2 Manager**: Renaming `show_banner()` menjadi `_nodejs_show_banner()` agar tidak bentrok dengan `show_banner()` di MongoDB Manager.
- **MongoDB Manager**: Penambahan pembuatan `security.keyFile` otomatis saat kombinasi auth dan replica set diaktifkan bersamaan.
- **MongoDB Manager**: Penambahan konfigurasi `allowConnectionsWithoutCertificates: true` saat TLS diaktifkan tanpa CAFile.
- **Hosting / Nginx**: Penghapusan trailing slash pada `proxy_pass` di reverse proxy API.
- **MQTT TLS**: Deteksi dinamis module Nginx stream dan proteksi rollback otomatis jika `nginx -t` gagal.

### Added
- **MongoDB Manager**: Opsi menu "7. Hapus/Uninstall MongoDB" untuk pembersihan paket, repositori, dan data.
- **MongoDB Manager**: Opsi perbaikan konfigurasi otomatis keyFile & TLS pada menu Service.
- **MongoDB Manager**: Fitur tuning heap cache memory WiredTiger dengan deteksi otomatis kapasitas RAM server.
- **Nginx Extra**: Fitur WSS Reverse Proxy, MQTT over TLS Stream termination, dan Certbot auto-renew deploy-hook.
