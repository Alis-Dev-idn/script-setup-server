# CLAUDE.md — Panduan Kontribusi

Panduan untuk Claude / kontributor saat mengubah repo ini.

## Aturan WAJIB setiap perubahan

Setiap kali mengubah script (menambah/menghapus menu, modul, opsi, atau perilaku):

1. **Update [ROUTEMAP.md](ROUTEMAP.md)** bila menu atau alur navigasi berubah —
   ROUTEMAP.md adalah sumber kebenaran tunggal untuk pohon menu.
2. **Tambahkan entri ke [CHANGELOG.md](CHANGELOG.md)** di bagian `[Unreleased]`
   (format Keep a Changelog: Added / Changed / Fixed / Removed).
3. **Validasi sintaks** sebelum commit: `bash -n` untuk setiap file `.sh` yang diubah
   (jalankan `shellcheck -x` bila tersedia).
4. **Commit tanpa baris kredit** `Co-Authored-By` (preferensi pemilik repo).

## Struktur

```
setup-server.sh        # entry point panel terpadu (men-source semua modul)
install.sh             # online installer (curl-able)
setup-hosting.sh       # shim -> modules/hosting.sh
mongodb-manager.sh     # shim -> modules/mongodb.sh
nodejs-pm2-manager.sh  # shim -> modules/nodejs-pm2.sh
lib/
  common.sh            # warna, log_*, confirm, normalize_path, spinner
  cloudflare.sh        # CF_CRED_FILE, setup_cloudflare_creds
  ssl.sh               # detect_ssl_certs, resolve_ssl_cert -> SSL_CERT/SSL_KEY
modules/
  hosting.sh           # vsftpd + Nginx + SSL + Deploy User
  mongodb.sh           # MongoDB: setup, user, DB, backup
  nodejs-pm2.sh        # Node.js & PM2 manager
  nginx-extra.sh       # WSS + MQTT TLS (stream) + auto-renew deploy-hook
```

## Konvensi kode

- **Library bersama** di `lib/*` di-`source` oleh semua modul. Pakai ulang helper
  yang ada (`log_ok/log_warn/log_err/log_info`, `confirm`, `normalize_path`,
  `resolve_ssl_cert`) — jangan menulis ulang.
- Setiap modul punya guard `BASH_SOURCE` agar aman di-`source` oleh `setup-server.sh`
  (tidak auto-run) maupun dijalankan langsung dengan auto-`sudo`.
- Semua script butuh root; ikuti pola `exec sudo bash "$0" "$@"` yang sudah ada.
- Untuk perubahan file sistem (Nginx/vsftpd/dll): backup dulu
  (`cp "$f" "$f.bak.$(date +%Y%m%d%H%M%S)"`), `nginx -t` sebelum reload, dan tawarkan
  rollback bila gagal.
- Input port/path: selalu sediakan **default** dan validasi (`[[ "$x" =~ ^[0-9]+$ ]]`).
