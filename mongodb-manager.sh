#!/bin/bash
# Shim kompatibilitas — modul diarahkan ke submodul baru
# Tetap bisa dijalankan dengan: bash mongodb-manager.sh
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_DIR/modules/mongodb/main.sh" "$@"
