#!/bin/bash
# Shim kompatibilitas — script asli dipindah ke modules/nodejs-pm2.sh
# Tetap bisa dijalankan dengan: bash nodejs-pm2-manager.sh
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_DIR/modules/nodejs-pm2.sh" "$@"
