#!/bin/bash
# Shim kompatibilitas — script asli dipindah ke modules/hosting.sh
# Tetap bisa dijalankan dengan: bash setup-hosting.sh
_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$_DIR/modules/hosting.sh" "$@"
