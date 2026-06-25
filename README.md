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
|   |-- common.sh                # Warna, logging, helper umum
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

Lihat README lengkap di GitHub.
