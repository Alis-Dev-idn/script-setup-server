#!/bin/bash
# Shim kompatibilitas — modul diarahkan ke submodul baru
# Tetap bisa dijalankan dengan: bash setup-hosting.sh
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_DIR/modules/hosting/main.sh" "$@"
