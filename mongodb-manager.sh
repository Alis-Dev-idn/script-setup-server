#!/bin/bash
# Shim kompatibilitas — script asli dipindah ke modules/mongodb.sh
# Tetap bisa dijalankan dengan: bash mongodb-manager.sh
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_DIR/modules/mongodb.sh" "$@"
