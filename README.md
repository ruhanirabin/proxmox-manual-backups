# PVEXB Proxmox USB Backup

Reusable Bash tooling for Proxmox USB backups with Home Assistant-compatible triggering, per-node configuration, logging, and Telegram notifications.

`pvexb-` is the canonical prefix for installed files to reduce naming conflicts on shared Proxmox hosts.

The root `VERSION` file is the single source of truth; `CHANGELOG.md` tracks SemVer changes.

## Current Flow

This keeps the existing Home Assistant flow intact:

1. Home Assistant turns on the smart plug for the external USB drive.
2. Home Assistant executes a backup command on the Proxmox node.
3. The script waits for `/mnt/usb-backup`.
4. The script runs `vzdump` for the configured VM/LXC IDs.
5. The script unmounts the USB drive.
6. Home Assistant turns off the plug after its existing timeout window.

The default `POWER_MODE="external"` means Home Assistant or another external automation owns power control.

## Canonical Names

- Main command: `/usr/local/bin/pvexb-backup`
- Telegram helper: `/usr/local/bin/pvexb-send-telegram`
- Config file: `/etc/pvexb.conf`
- Telegram env file: `/root/.pvexb.env`
- Log directory: `/var/log/pvexb`
- Logrotate file: `/etc/logrotate.d/pvexb-backup`
- Optional systemd unit: `pvexb-backup.service`
- Optional systemd timer: `pvexb-backup.timer`

## Compatibility Names

The installer also deploys wrappers for previous names:

- `/usr/local/bin/proxmox-usb-backup`
- `/usr/local/bin/proxmox_usb_backup.sh`
- `/usr/local/bin/unmount_usb_backup.sh`
- `/usr/local/bin/send_telegram.sh`

The runner also falls back from `/etc/pvexb.conf` to `/etc/proxmox-usb-backup.conf`, and the Telegram helper falls back from `/root/.pvexb.env` to `/root/.backup-config.env`.

## Files

- `bin/pvexb-backup` - main runner
- `bin/pvexb-send-telegram` - Telegram Bot API helper
- `bin/proxmox-usb-backup` - compatibility wrapper
- `bin/proxmox_usb_backup.sh` - compatibility wrapper for the original backup script name
- `bin/unmount_usb_backup.sh` - compatibility wrapper for the original unmount script name
- `bin/send_telegram.sh` - compatibility wrapper
- `config/pvexb.conf.example` - per-node backup config
- `config/pvexb.env.example` - Telegram credentials example
- `install.sh` - installer for Proxmox nodes
- `VERSION` - single source of truth for the release version
- `CHANGELOG.md` - SemVer changelog
- `LICENSE` - MIT license
- `.gitignore` - local artifact and legacy-file exclusions
- `AGENTS.md` - concise repo instructions for AI agents
- `tests/proxmox-docker/` - optional privileged Proxmox-in-Docker test harness
- `systemd/pvexb-backup.service` - optional systemd service
- `systemd/pvexb-backup.timer` - optional monthly timer
- `logrotate/pvexb-backup` - six-month log rotation

## Install

Run on each Proxmox host as `root`.

Quick install from GitHub:

```bash
bash -c 'set -euo pipefail; tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT; curl -fsSL https://github.com/ruhanirabin/proxmox-manual-backups/archive/refs/heads/main.tar.gz | tar -xz -C "$tmp" --strip-components=1; cd "$tmp"; chmod +x install.sh; ./install.sh'
```

The one-liner downloads this repository into a temporary directory, runs `install.sh`, and installs `pvexb-backup` plus compatibility wrappers under `/usr/local/bin`.

If you already have a local checkout, run:

```bash
chmod +x install.sh
./install.sh
```

The installer prompts for Telegram `BOT_TOKEN` and `CHAT_ID` when run interactively. You can pass parameters as environment variables before the command:

```bash
BOT_TOKEN="***" CHAT_ID="123456789" ./install.sh
```

One-line install with Telegram credentials:

```bash
BOT_TOKEN="***" CHAT_ID="123456789" bash -c 'set -euo pipefail; tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT; curl -fsSL https://github.com/ruhanirabin/proxmox-manual-backups/archive/refs/heads/main.tar.gz | tar -xz -C "$tmp" --strip-components=1; cd "$tmp"; chmod +x install.sh; ./install.sh'
```

Available installer environment parameters:

- `BOT_TOKEN` and `CHAT_ID` - write Telegram credentials to `/root/.pvexb.env`.
- `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` - legacy aliases for the same credentials.
- `PVEXB_INSTALL_NONINTERACTIVE=true` - skip prompts and create the example Telegram env file if credentials are not supplied.
- `PVEXB_DISABLE_SYSTEMD=false` - do not disable existing `pvexb-backup.service` or `pvexb-backup.timer` during install.
- `PREFIX=/custom/bin`, `CONFIG_FILE=/custom/pvexb.conf`, `TELEGRAM_ENV_FILE=/custom/.pvexb.env`, and `LOG_DIR=/custom/log` - override install paths for advanced setups.

Then review:

```bash
nano /etc/pvexb.conf
nano /root/.pvexb.env
```

If an older install already has `/etc/proxmox-usb-backup.conf` or `/root/.backup-config.env`, `install.sh` copies those into the new `pvexb-` paths on first install.

If the old `/usr/local/bin/proxmox_usb_backup.sh` exists and no config file exists yet, `install.sh` also tries to migrate its hard-coded `VM_LIST`, `MOUNT_POINT`, `STORAGE_ID`, and `MODE` values into `/etc/pvexb.conf`. Before replacing old command names with compatibility wrappers, it backs up non-`pvexb` legacy files under `/usr/local/share/pvexb/legacy-backups/<timestamp>/`.

## Usage

Canonical command:

```bash
/usr/local/bin/pvexb-backup run
```

Existing Home Assistant commands can continue to use:

```bash
/usr/local/bin/proxmox_usb_backup.sh
/usr/local/bin/unmount_usb_backup.sh
```

Recommended new Home Assistant `configuration.yaml` line:

```yaml
shell_command:
  pvexb_backup: "ssh root@proxmox-node /usr/local/bin/pvexb-backup run"
```

Other commands:

```bash
/usr/local/bin/pvexb-backup check
/usr/local/bin/pvexb-backup unmount
/usr/local/bin/pvexb-backup version
```

`check` validates config, waits for the mount, checks Proxmox storage, and checks free space without running `vzdump`.

## Optional Systemd Timer

Home Assistant does not need to be replaced in v1. The installer does not install the systemd unit/timer and, by default, disables existing `pvexb-backup.timer` and `pvexb-backup.service` if they are present so the HA-triggered flow does not double-run.

To check a Proxmox host manually:

```bash
systemctl is-enabled pvexb-backup.timer pvexb-backup.service
systemctl is-active pvexb-backup.timer pvexb-backup.service
```

For Home Assistant-triggered mode, both should be `disabled` and `inactive`.

If you later want local monthly scheduling:

```bash
install -m 0644 systemd/pvexb-backup.service /etc/systemd/system/pvexb-backup.service
install -m 0644 systemd/pvexb-backup.timer /etc/systemd/system/pvexb-backup.timer
systemctl daemon-reload
systemctl enable --now pvexb-backup.timer
```

To stop the installer from disabling systemd units during an install:

```bash
PVEXB_DISABLE_SYSTEMD=false ./install.sh
```

## Exit Codes

- `0` - success
- `2` - invalid command
- `20` - config file missing
- `21` - config invalid
- `30` - another backup is already running
- `31` - command power-on config missing or failed
- `32` - unsupported power mode
- `40` - mount timeout
- `41` - Proxmox storage missing or unavailable
- `42` - free-space check failed
- `43` - free space below threshold
- `50` - required runtime command missing, such as `vzdump`, `pvesm`, `flock`, `mountpoint`, `df`, `awk`, or `umount`
- `60` - one or more backups or unmount failed
- `127` - compatibility wrapper cannot find the canonical `pvexb-*` command

Common recovery:

```bash
./install.sh
nano /etc/pvexb.conf
nano /root/.pvexb.env
/usr/local/bin/pvexb-backup check
```

## Future Power Control

The config already reserves power-control settings:

```bash
POWER_MODE="external"
POWER_ON_CMD=""
POWER_OFF_CMD=""
```

For v1, keep `external`. A later version can implement `POWER_MODE="homeassistant"` to call the Home Assistant API directly, or `POWER_MODE="command"` for local smart-plug commands.
