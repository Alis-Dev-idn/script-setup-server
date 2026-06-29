# Route Map — Script Setup Server

> Sumber kebenaran tunggal untuk pohon menu (route map) panel.
> **Wajib diperbarui setiap kali ada perubahan menu/alur.** Lihat [CLAUDE.md](CLAUDE.md).

`setup-server.sh` adalah pintu masuk yang men-`source` tiap modul; tiap modul juga
bisa dijalankan langsung lewat shim-nya (`setup-hosting.sh`, `mongodb-manager.sh`,
`nodejs-pm2-manager.sh`).

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
|-- 4. Nginx Extra                          -> modules/nginx-extra.sh (nginx_extra_main)
|     |-- 1. Setup WSS Reverse Proxy
|     |     |-- [1] Domain existing         (sisip location WSS, default path /ws, port 3001)
|     |     +-- [2] Domain khusus baru       (server block 80->443, default path /, port 3001)
|     |-- 2. Setup MQTT TLS                 (Nginx stream: mqtts 8883 -> broker plain 127.0.0.1:1883)
|     |-- 3. Setup/Refresh Auto-Renew Hook  (deploy-hook reload nginx & mosquitto)
|     |-- 4. List Konfigurasi
|     |-- 5. Hapus Konfigurasi              ([1] stream MQTT / [2] site WSS)
|     +-- 6. Kembali
|
+-- 5. Keluar
```
