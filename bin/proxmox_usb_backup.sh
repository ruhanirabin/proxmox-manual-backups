#!/usr/bin/env bash
#
# PVEXB compatibility wrapper for original Home Assistant backup command
# Version: delegated to ./pvexb-backup or /usr/local/bin/pvexb-backup
# Relative dependencies:
# - ./pvexb-backup

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -x "$SCRIPT_DIR/pvexb-backup" ]; then
  exec "$SCRIPT_DIR/pvexb-backup" run "$@"
fi

if [ -x /usr/local/bin/pvexb-backup ]; then
  exec /usr/local/bin/pvexb-backup run "$@"
fi

echo "ERROR: pvexb-backup not found. Run ./install.sh from the pvexb repo." >&2
exit 127
