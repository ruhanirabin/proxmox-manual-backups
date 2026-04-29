#!/usr/bin/env bash
#
# PVEXB compatibility wrapper for previous Telegram helper name
# Version: delegated to ./pvexb-send-telegram or /usr/local/bin/pvexb-send-telegram
# Relative dependencies:
# - ./pvexb-send-telegram

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [ -x "$SCRIPT_DIR/pvexb-send-telegram" ]; then
  exec "$SCRIPT_DIR/pvexb-send-telegram" "$@"
fi

if [ -x /usr/local/bin/pvexb-send-telegram ]; then
  exec /usr/local/bin/pvexb-send-telegram "$@"
fi

echo "ERROR: pvexb-send-telegram not found. Run ./install.sh from the pvexb repo." >&2
exit 127
