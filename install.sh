#!/usr/bin/env bash
#
# PVEXB installer
# Version: read from ./VERSION
# Relative dependencies:
# - VERSION
# - bin/pvexb-backup
# - bin/pvexb-send-telegram
# - bin/proxmox-usb-backup
# - bin/proxmox_usb_backup.sh
# - bin/unmount_usb_backup.sh
# - bin/send_telegram.sh
# - config/pvexb.conf.example
# - config/pvexb.env.example
# - logrotate/pvexb-backup

set -euo pipefail

VERSION_FILE="${VERSION_FILE:-VERSION}"
if [ ! -f "$VERSION_FILE" ]; then
  echo "Missing VERSION file: $VERSION_FILE. Run install.sh from the pvexb repo root." >&2
  exit 1
fi

if ! command -v head >/dev/null 2>&1; then
  echo "Missing required command: head" >&2
  exit 1
fi

VERSION="$(head -n 1 "$VERSION_FILE")"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid VERSION value: $VERSION" >&2
  exit 1
fi

PREFIX="${PREFIX:-/usr/local/bin}"
SHARE_DIR="${SHARE_DIR:-/usr/local/share/pvexb}"
CONFIG_FILE="${CONFIG_FILE:-/etc/pvexb.conf}"
TELEGRAM_ENV_FILE="${TELEGRAM_ENV_FILE:-/root/.pvexb.env}"
LEGACY_CONFIG_FILE="${LEGACY_CONFIG_FILE:-/etc/proxmox-usb-backup.conf}"
LEGACY_TELEGRAM_ENV_FILE="${LEGACY_TELEGRAM_ENV_FILE:-/root/.backup-config.env}"
LOG_DIR="${LOG_DIR:-/var/log/pvexb}"
LOGROTATE_DIR="${LOGROTATE_DIR:-/etc/logrotate.d}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_DIR:-/usr/local/share/pvexb/legacy-backups/$TIMESTAMP}"
PVEXB_INSTALL_NONINTERACTIVE="${PVEXB_INSTALL_NONINTERACTIVE:-false}"
PVEXB_DISABLE_SYSTEMD="${PVEXB_DISABLE_SYSTEMD:-true}"

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Missing required repo file: $path. Run install.sh from the pvexb repo root." >&2
    exit 1
  fi
}

preflight_installer() {
  require_command install
  require_command grep
  require_command sed
  require_command head
  require_command date

  require_file "$VERSION_FILE"
  require_file bin/pvexb-backup
  require_file bin/pvexb-send-telegram
  require_file bin/proxmox-usb-backup
  require_file bin/proxmox_usb_backup.sh
  require_file bin/unmount_usb_backup.sh
  require_file bin/send_telegram.sh
  require_file config/pvexb.conf.example
  require_file config/pvexb.env.example
  require_file logrotate/pvexb-backup
}

backup_existing_file() {
  local path="$1"

  if [ ! -f "$path" ]; then
    return 0
  fi

  if grep -q 'pvexb-backup\|pvexb-send-telegram' "$path" 2>/dev/null; then
    return 0
  fi

  install -d "$BACKUP_DIR"
  install -m 0600 "$path" "$BACKUP_DIR/$(basename "$path")"
  echo "Backed up existing legacy file: $path -> $BACKUP_DIR/$(basename "$path")"
}

extract_quoted_assignment() {
  local name="$1"
  local file="$2"
  sed -nE "s/^[[:space:]]*${name}=[\"']?([^\"'#[:space:]]+)[\"']?.*/\\1/p" "$file" | head -n 1
}

create_config_from_legacy_script() {
  local legacy_script="$1"
  local vm_list mount_point storage_id backup_mode

  if [ ! -f "$legacy_script" ]; then
    return 1
  fi

  vm_list="$(sed -nE 's/^[[:space:]]*VM_LIST=\(([^)]*)\).*/\1/p' "$legacy_script" | head -n 1 | tr -d '"' | xargs)"
  mount_point="$(extract_quoted_assignment MOUNT_POINT "$legacy_script")"
  storage_id="$(extract_quoted_assignment STORAGE_ID "$legacy_script")"
  backup_mode="$(extract_quoted_assignment MODE "$legacy_script")"

  if [ -z "$vm_list" ] && [ -z "$mount_point" ] && [ -z "$storage_id" ] && [ -z "$backup_mode" ]; then
    return 1
  fi

  cat > "$CONFIG_FILE" <<EOF
# Migrated by pvexb install.sh from $legacy_script on $(date '+%Y-%m-%d %H:%M:%S').

VM_LIST="${vm_list:-101 106 131 103 107 104}"
MOUNT_POINT="${mount_point:-/mnt/usb-backup}"
STORAGE_ID="${storage_id:-usb-local-backup}"
BACKUP_MODE="${backup_mode:-suspend}"
COMPRESS="zstd"

WAIT_SECONDS=600
WAIT_INTERVAL=5
MIN_FREE_GB=100

LOG_DIR="/var/log/pvexb"
LOG_RETENTION_DAYS=180

TELEGRAM_ENABLED=true
TELEGRAM_SCRIPT="/usr/local/bin/pvexb-send-telegram"

POWER_MODE="external"
POWER_ON_CMD=""
POWER_OFF_CMD=""
EOF

  chmod 0644 "$CONFIG_FILE"
  echo "Created $CONFIG_FILE from legacy script: $legacy_script"
}

telegram_env_has_credentials() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 1
  fi

  grep -Eq '^[[:space:]]*(BOT_TOKEN|TELEGRAM_BOT_TOKEN)=' "$file" \
    && grep -Eq '^[[:space:]]*(CHAT_ID|TELEGRAM_CHAT_ID)=' "$file" \
    && ! grep -Eq 'replace-with-your-telegram-bot-token|CHAT_ID="123456789"|CHAT_ID='\''123456789'\''' "$file"
}

write_telegram_env() {
  local bot_token="$1"
  local chat_id="$2"

  cat > "$TELEGRAM_ENV_FILE" <<EOF
BOT_TOKEN="$bot_token"
CHAT_ID="$chat_id"
EOF
  chmod 0600 "$TELEGRAM_ENV_FILE"
  echo "Configured Telegram credentials in $TELEGRAM_ENV_FILE"
}

configure_telegram_env() {
  local bot_token="${BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}"
  local chat_id="${CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"

  if telegram_env_has_credentials "$TELEGRAM_ENV_FILE"; then
    echo "Telegram credentials already configured in $TELEGRAM_ENV_FILE"
    return 0
  fi

  if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
    write_telegram_env "$bot_token" "$chat_id"
    return 0
  fi

  if [ "$PVEXB_INSTALL_NONINTERACTIVE" = "true" ] || [ ! -t 0 ]; then
    if [ ! -f "$TELEGRAM_ENV_FILE" ]; then
      install -m 0600 config/pvexb.env.example "$TELEGRAM_ENV_FILE"
    fi
    echo "Telegram credentials not configured. Edit $TELEGRAM_ENV_FILE or rerun with BOT_TOKEN and CHAT_ID."
    return 0
  fi

  echo
  echo "Telegram notification setup"
  echo "Leave both values empty to skip for now."
  read -r -p "Telegram bot token: " bot_token
  read -r -p "Telegram chat ID: " chat_id

  if [ -n "$bot_token" ] && [ -n "$chat_id" ]; then
    write_telegram_env "$bot_token" "$chat_id"
  elif [ -z "$bot_token" ] && [ -z "$chat_id" ]; then
    install -m 0600 config/pvexb.env.example "$TELEGRAM_ENV_FILE"
    echo "Skipped Telegram setup. Edit $TELEGRAM_ENV_FILE later."
  else
    install -m 0600 config/pvexb.env.example "$TELEGRAM_ENV_FILE"
    echo "Incomplete Telegram setup skipped. Edit $TELEGRAM_ENV_FILE later."
  fi
}

check_network_dependencies() {
  if [ ! -f "$CONFIG_FILE" ]; then
    return 0
  fi
  
  # Source config to check POWER_MODE (silently, ignore errors)
  local power_mode=""
  power_mode=$(grep -E '^\s*POWER_MODE=' "$CONFIG_FILE" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '"' | tr -d "'")
  
  if [ "$power_mode" != "network" ]; then
    return 0
  fi
  
  echo
  echo "Network backup mode detected."
  
  local missing=0
  if ! command -v wakeonlan >/dev/null 2>&1 && ! command -v etherwake >/dev/null 2>&1; then
    echo "  WARNING: Neither wakeonlan nor etherwake found. Install one: apt-get install wakeonlan"
    missing=1
  fi
  
  if ! command -v mount >/dev/null 2>&1; then
    echo "  WARNING: mount command not found (should be in util-linux)"
    missing=1
  fi
  
  if ! command -v nfs-common >/dev/null 2>&1 && ! dpkg -l nfs-common >/dev/null 2>&1 2>/dev/null; then
    echo "  WARNING: nfs-common package may not be installed. Install: apt-get install nfs-common"
    missing=1
  fi
  
  if [ "$missing" -eq 0 ]; then
    echo "  All network backup dependencies satisfied."
  fi
}

disable_systemd_units_for_ha_mode() {
  if [ "$PVEXB_DISABLE_SYSTEMD" != "true" ]; then
    echo "Skipping systemd disable check because PVEXB_DISABLE_SYSTEMD=$PVEXB_DISABLE_SYSTEMD"
    return 0
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  if systemctl list-unit-files pvexb-backup.timer >/dev/null 2>&1; then
    systemctl disable --now pvexb-backup.timer >/dev/null 2>&1 || true
    echo "Ensured pvexb-backup.timer is disabled for Home Assistant-triggered mode."
  fi

  if systemctl list-unit-files pvexb-backup.service >/dev/null 2>&1; then
    systemctl disable --now pvexb-backup.service >/dev/null 2>&1 || true
    echo "Ensured pvexb-backup.service is disabled for Home Assistant-triggered mode."
  fi
}

preflight_installer

install -d "$PREFIX"
install -d "$SHARE_DIR"
install -d "$LOG_DIR"
install -m 0644 "$VERSION_FILE" "$SHARE_DIR/VERSION"

backup_existing_file "$PREFIX/proxmox_usb_backup.sh"
backup_existing_file "$PREFIX/unmount_usb_backup.sh"
backup_existing_file "$PREFIX/proxmox-usb-backup"
backup_existing_file "$PREFIX/send_telegram.sh"

install -m 0755 bin/pvexb-backup "$PREFIX/pvexb-backup"
install -m 0755 bin/pvexb-send-telegram "$PREFIX/pvexb-send-telegram"

if [ ! -f "$CONFIG_FILE" ] && [ -f "$LEGACY_CONFIG_FILE" ]; then
  install -m 0644 "$LEGACY_CONFIG_FILE" "$CONFIG_FILE"
elif [ ! -f "$CONFIG_FILE" ] && create_config_from_legacy_script "$PREFIX/proxmox_usb_backup.sh"; then
  :
elif [ ! -f "$CONFIG_FILE" ]; then
  install -m 0644 config/pvexb.conf.example "$CONFIG_FILE"
fi

if [ ! -f "$TELEGRAM_ENV_FILE" ] && [ -f "$LEGACY_TELEGRAM_ENV_FILE" ]; then
  install -m 0600 "$LEGACY_TELEGRAM_ENV_FILE" "$TELEGRAM_ENV_FILE"
fi

configure_telegram_env

check_network_dependencies

# Compatibility wrappers for previous command names and existing Home Assistant commands.
install -m 0755 bin/proxmox-usb-backup "$PREFIX/proxmox-usb-backup"
install -m 0755 bin/send_telegram.sh "$PREFIX/send_telegram.sh"
install -m 0755 bin/proxmox_usb_backup.sh "$PREFIX/proxmox_usb_backup.sh"
install -m 0755 bin/unmount_usb_backup.sh "$PREFIX/unmount_usb_backup.sh"

install -d "$LOGROTATE_DIR"
install -m 0644 logrotate/pvexb-backup "$LOGROTATE_DIR/pvexb-backup"

disable_systemd_units_for_ha_mode

echo "Installed pvexb-backup."
echo "Edit $CONFIG_FILE and $TELEGRAM_ENV_FILE before first run."
