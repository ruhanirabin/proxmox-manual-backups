# PVEXB — Proxmox Backup Tool

Reusable Bash tooling for Proxmox VM/LXC backups with Home Assistant-compatible triggering, per-node configuration, locking, logging, and Telegram notifications. Supports both USB external drives and network/NAS targets via NFS.

`pvexb-` is the canonical prefix for installed files to reduce naming conflicts on shared Proxmox hosts.

The root `VERSION` file is the single source of truth; `CHANGELOG.md` tracks SemVer changes.

## Features

- Per-VM/LXC backup with per-run logging
- Lock file prevents concurrent runs
- Configurable retention via Proxmox `prune-backups`
- Telegram notifications on success, failure, or partial runs
- Home Assistant, systemd timer, or manual SSH triggering
- Two backup modes: USB external drive or network/NFS NAS
- NAS power management: WOL wake, NFS mount/unmount, post-backup shutdown

---

## Install

Run on each Proxmox host as `root`.

**Quick install from GitHub:**

```bash
bash -c 'set -euo pipefail; tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT; curl -fsSL https://github.com/ruhanirabin/proxmox-manual-backups/archive/refs/heads/main.tar.gz | tar -xz -C "$tmp" --strip-components=1; cd "$tmp"; chmod +x install.sh; ./install.sh'
```

**With Telegram credentials pre-filled:**

```bash
BOT_TOKEN="***" CHAT_ID="123456789" bash -c 'set -euo pipefail; tmp="$(mktemp -d)"; trap "rm -rf \"$tmp\"" EXIT; curl -fsSL https://github.com/ruhanirabin/proxmox-manual-backups/archive/refs/heads/main.tar.gz | tar -xz -C "$tmp" --strip-components=1; cd "$tmp"; chmod +x install.sh; ./install.sh'
```

**From a local checkout:**

```bash
chmod +x install.sh
./install.sh
```

After install, review and edit:

```bash
nano /etc/pvexb.conf
nano /root/.pvexb.env
```

---

## Choose Your Setup

Pick the setup that matches your hardware:

| | USB External Drive | Network NAS |
|---|---|---|
| `POWER_MODE` | `external` (default) | `network` |
| Target | USB drive on smart plug | Synology/QNAP via NFS |
| Power control | External (HA smart plug) | Built-in WOL |
| Mount | HA mounts USB | Script mounts NFS on-demand |

Continue to the matching section below.

---

## Setup: USB Backup

### How It Works

```
HA turns on smart plug
        │
        ▼
HA mounts USB drive → triggers pvexb-backup via SSH
        │
        ▼
pvexb-backup waits for mount → runs vzdump → unmounts
        │
        ▼
HA turns off smart plug (after timeout)
```

PVEXB does **not** mount or power the USB drive. It only waits for the mount point to appear. Power control and mounting are handled externally.

### Proxmox Configuration (`/etc/pve/storage.cfg`)

```
dir: usb-local-backup
    path /mnt/usb-backup
    content backup
    prune-backups keep-last=3
```

Set `STORAGE_ID="usb-local-backup"` in `/etc/pvexb.conf` to match.

### Config Example (`/etc/pvexb.conf`)

```bash
VM_LIST="101 106 131 103 107 104"
MOUNT_POINT="/mnt/usb-backup"
STORAGE_ID="usb-local-backup"
BACKUP_MODE="suspend"
COMPRESS="zstd"
WAIT_SECONDS=600
WAIT_INTERVAL=5
MIN_FREE_GB=100
POWER_MODE="external"
TELEGRAM_ENABLED=true
```

### Home Assistant Triggering

**Recommended: mount + async backup (fire-and-forget):**

```yaml
shell_command:
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'mount /dev/disk/by-uuid/<USB-UUID> /mnt/usb-backup && sleep 5 && nohup /usr/local/bin/pvexb-backup run > /dev/null 2>&1 &'"
```

**Why async?** The HA `shell_command` service has a ~60-second timeout. Multi-VM backups take longer. The `nohup ... &` pattern:
- Mount is synchronous (returns only after mount succeeds)
- Backup starts in the background and the SSH call returns immediately
- HA does not timeout waiting for the backup to complete
- PVEXB handles locking so concurrent runs are prevented
- The smart plug power-off delay must be long enough to cover the full backup + unmount window

Flow:
1. HA turns on smart plug
2. HA mounts the drive (synchronous)
3. HA fires backup in background, gets instant success response
4. HA starts its power-off delay timer
5. PVEXB waits for mount (already done), runs vzdump, unmounts, notifies via Telegram
6. HA turns off smart plug after its delay timer

**Alternative: mount separately, then fire backup**

```yaml
shell_command:
  pvexb_mount: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'mount /dev/disk/by-uuid/<USB-UUID> /mnt/usb-backup'"
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'nohup /usr/local/bin/pvexb-backup run > /dev/null 2>&1 &'"
```

**Using systemd mount unit (with hyphen escaping):**

```yaml
shell_command:
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'systemctl start mnt-usb\\x2dbackup.mount && sleep 10 && nohup /usr/local/bin/pvexb-backup run > /dev/null 2>&1 &'"
```

---

## Setup: Network Backup

### How It Works

```
Trigger (HA / cron / SSH)
        │
        ▼
pvexb-backup run
        │
        ├── WOL to NAS (wakeonlan/etherwake)
        │        │
        │        ▼
        │  ping until NAS responds
        │  (configurable timeout)
        │        │
        │        ▼
        │  mount NFS export → MOUNT_POINT
        │        │
        │        ▼
        │  vzdump for each VM → NFS storage
        │        │
        │        ▼
        │  unmount NFS
        │        │
        │        ▼
        │  shut down NAS (SSH or custom cmd)
        │  [only within NAS_SLEEP_WINDOW]
```

### Important: Sleep vs Shutdown

On Synology and most NAS devices, there is no true "sleep" state. `synopoweroff -s` performs a **full graceful shutdown**. The terms "sleep" and "power off" are used interchangeably in this documentation — they both mean the NAS powers off completely.

If your NAS already has its own schedule to power off (e.g., daily at 1:30am), set `NAS_SLEEP_MODE=disabled` and let the NAS handle its own shutdown.

### NAS Preparation (Synology DSM)

1. **Enable WOL:** Control Panel → Hardware & Power → General → Enable Wake on LAN
2. **Enable NFS:** Control Panel → File Services → NFS → Enable NFS service
3. **Create shared folder** for backups (e.g., `prox-backup-node-02`)
4. **Set NFS permissions** on the shared folder:
   - Hostname/IP: Proxmox node IP
   - Privilege: Read/Write
   - Squash: No mapping (or map to root/admin)
   - Security: sys
5. **Enable SSH:** Control Panel → Terminal & SNMP → Enable SSH service
6. **Note the NAS MAC address** (Control Panel → Info Center → Network)

### Proxmox Configuration (`/etc/pve/storage.cfg`)

**IMPORTANT:** Do NOT define the NFS share as `nfs:` in Proxmox — this causes WebUI hangs when the NAS is off. Use a `dir:` entry pointing at the mount point. The script handles mount/unmount around each backup.

Remove any existing `nfs:` entry, then add:

```
dir: prox-backup
    path /mnt/pve/prox-backup
    content backup
    prune-backups keep-last=3
    shared 0
```

When the NAS is off and NFS is unmounted, Proxmox sees an empty local directory — not a hung NFS connection.

Set `STORAGE_ID="prox-backup"` in `/etc/pvexb.conf` to match.

### Install Dependencies

```bash
apt install -y nfs-common wakeonlan   # or etherwake
```

### Config Example (`/etc/pvexb.conf`)

```bash
VM_LIST="101 102 103"
MOUNT_POINT="/mnt/pve/prox-backup"
STORAGE_ID="prox-backup"
BACKUP_MODE="snapshot"
COMPRESS="zstd"

POWER_MODE="network"
NAS_MAC="00:11:22:33:44:55"
NAS_IP="192.168.68.69"
NAS_SSH_USER="admin"
NFS_EXPORT="/volume1/prox-backup-node-02"
NFS_OPTIONS="soft,noatime,nofail,vers=4.1"
NAS_SLEEP_MODE="ssh"
NAS_SLEEP_WINDOW="Mon-Fri 01:00-07:00"
```

### SSH Key Setup (for NAS shutdown)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/nas_key -N ""
ssh-copy-id -i ~/.ssh/nas_key admin@192.168.68.69
# Then set NAS_SSH_KEY="~/.ssh/nas_key" in /etc/pvexb.conf
```

### Manual Testing

```bash
# Test WOL
wakeonlan 00:11:22:33:44:55
ping -c 3 192.168.68.69

# Test NFS mount
mkdir -p /mnt/pve/prox-backup
mount -t nfs 192.168.68.69:/volume1/prox-backup-node-02 /mnt/pve/prox-backup
ls /mnt/pve/prox-backup
umount /mnt/pve/prox-backup

# Full validation
pvexb-backup check
```

---

## Reference

### Commands

```bash
/usr/local/bin/pvexb-backup run        # Run backup (default action)
/usr/local/bin/pvexb-backup check      # Validate config, check mount/storage/space (no vzdump)
/usr/local/bin/pvexb-backup unmount    # Unmount the backup target
/usr/local/bin/pvexb-backup version    # Show version
```

Compatibility wrappers (legacy names still work):
- `/usr/local/bin/proxmox-usb-backup`
- `/usr/local/bin/proxmox_usb_backup.sh`
- `/usr/local/bin/unmount_usb_backup.sh`
- `/usr/local/bin/send_telegram.sh`

### All Config Variables

**Common (both modes):**

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_LIST` | — | Space-separated VM/LXC IDs to back up |
| `MOUNT_POINT` | `/mnt/usb-backup` | Mount point for backup target |
| `STORAGE_ID` | `usb-local-backup` | Proxmox storage name in `/etc/pve/storage.cfg` |
| `BACKUP_MODE` | `suspend` | vzdump mode: `snapshot`, `suspend`, or `stop` |
| `COMPRESS` | `zstd` | Compression algorithm |
| `WAIT_SECONDS` | `600` | Max seconds to wait for mount |
| `WAIT_INTERVAL` | `5` | Seconds between mount check retries |
| `MIN_FREE_GB` | `100` | Minimum free space required before backup |
| `TELEGRAM_ENABLED` | `true` | Enable Telegram notifications |
| `TELEGRAM_SCRIPT` | `/usr/local/bin/pvexb-send-telegram` | Path to Telegram helper |
| `LOG_DIR` | `/var/log/pvexb` | Log directory |
| `LOG_RETENTION_DAYS` | `180` | Days to retain log files |
| `LOCK_FILE` | `/run/pvexb-backup.lock` | Lock file path |

**Power mode:**

| Variable | Default | Description |
|----------|---------|-------------|
| `POWER_MODE` | `external` | `external`, `command`, or `network` |
| `POWER_ON_CMD` | — | Custom power-on command (when `POWER_MODE=command`) |
| `POWER_OFF_CMD` | — | Custom power-off command (when `POWER_MODE=command`) |

**Network mode (`POWER_MODE=network`):**

| Variable | Default | Description |
|----------|---------|-------------|
| `NAS_MAC` | — | MAC address for WOL (required) |
| `NAS_IP` | — | IP address of the NAS (required) |
| `NAS_SSH_USER` | `root` | SSH user for NAS shutdown |
| `NAS_SSH_KEY` | — | SSH private key path (optional) |
| `NFS_EXPORT` | — | NFS export path on NAS (required) |
| `NFS_OPTIONS` | `soft,noatime,nofail,vers=4.1` | NFS mount options |
| `NAS_SLEEP_MODE` | `disabled` | How to shut down NAS: `disabled`, `ssh`, or `command` |
| `NAS_SLEEP_CMD` | `synopoweroff -s` | Command to shut down NAS |
| `NAS_SLEEP_WINDOW` | — | When to allow shutdown: `Mon-Fri 01:00-07:00`, `daily`, or empty (always) |
| `NAS_PING_TIMEOUT` | `300` | Max seconds to wait for NAS ping response |
| `NAS_PING_INTERVAL` | `5` | Seconds between ping retries |

### Power Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `external` | External system handles power and mount | USB drive on smart plug |
| `command` | Custom local commands via `POWER_ON_CMD` / `POWER_OFF_CMD` | Smart plug CLI, IPMI, relay |
| `network` | Built-in WOL + NFS mount + NAS shutdown | Synology/QNAP NAS |

### Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `2` | Invalid command |
| `20` | Config file missing |
| `21` | Config invalid |
| `30` | Another backup is already running (lock held) |
| `31` | Power-on step failed |
| `32` | Unsupported power mode |
| `40` | Mount timeout / NFS mount failed |
| `41` | Proxmox storage missing or unavailable |
| `42` | Free-space check failed |
| `43` | Free space below threshold |
| `50` | Required runtime command missing |
| `60` | One or more backups or unmount failed |
| `127` | Compatibility wrapper cannot find canonical command |

Common recovery:

```bash
./install.sh
nano /etc/pvexb.conf
nano /root/.pvexb.env
/usr/local/bin/pvexb-backup check
```

### Retention

Controlled by `prune-backups` in `/etc/pve/storage.cfg`:

```
dir: usb-local-backup
    path /mnt/usb-backup
    content backup
    prune-backups keep-last=3
```

This keeps the last 3 backups per VM. Edit `keep-last` to change.

### Optional Systemd Timer

The installer disables `pvexb-backup.timer` and `pvexb-backup.service` by default so HA-triggered mode does not double-run.

To enable local scheduling:

```bash
install -m 0644 systemd/pvexb-backup.service /etc/systemd/system/
install -m 0644 systemd/pvexb-backup.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now pvexb-backup.timer
```

To prevent the installer from disabling systemd units:

```bash
PVEXB_DISABLE_SYSTEMD=false ./install.sh
```

### Troubleshooting

**USB: Drive powered on but not mounted**

PVEXB does not mount the drive — it only waits for it. Mount must happen externally.

```bash
mountpoint -q /mnt/usb-backup && echo "MOUNTED" || echo "NOT MOUNTED"
lsblk -f | grep -v loop
mount /dev/disk/by-uuid/<UUID> /mnt/usb-backup
```

**USB: Backups stopped working after power cycle**

Most common cause: USB drive was powered on but never auto-mounted. Include `mount` in your HA shell_command.

**Network: NAS does not respond to WOL**

- Verify WOL is enabled in NAS settings
- Check the correct MAC address (some NAS devices have multiple NICs)
- Try `etherwake` instead of `wakeonlan` if one fails
- Ensure the NAS and Proxmox node are on the same L2 network

**Network: NFS mount fails**

```bash
# Check NFS service on NAS
showmount -e 192.168.68.69

# Test mount manually with verbose output
mount -v -t nfs 192.168.68.69:/volume1/prox-backup /mnt/pve/prox-backup
```

**Network: Proxmox WebUI hangs**

You have an `nfs:` entry in `/etc/pve/storage.cfg`. Remove it and replace with a `dir:` entry (see Network Setup above).

**Common: Storage error**

```bash
pvesm status --storage <STORAGE_ID>
```

If this fails, check `/etc/pve/storage.cfg` — the `dir` entry must match `STORAGE_ID` in config.

**Common: Low free space**

```bash
df -h <MOUNT_POINT>
```

Clean old backups or reduce `keep-last` in `storage.cfg`.

**Common: Another backup is already running**

Stale lock from a crashed run:

```bash
rm -f /run/pvexb-backup.lock
```

**Common: Telegram not working**

```bash
cat /root/.pvexb.env
/usr/local/bin/pvexb-send-telegram "test"
# Ensure TELEGRAM_ENABLED=true in /etc/pvexb.conf
```

### Logs

- Main log: `/var/log/pvexb/pvexb-backup.log`
- Per-run logs: `/var/log/pvexb/<RUN-ID>-<NODE>.log`
- Watch live: `tail -f /var/log/pvexb/pvexb-backup.log`
- Logrotate: `/etc/logrotate.d/pvexb-backup` (6-month retention)

### systemd Mount Unit Hyphen Escaping

If using a systemd mount unit for `/mnt/usb-backup`, the filename must encode hyphens as `\x2d`:

```
/etc/systemd/system/mnt-usb\x2dbackup.mount
```

Inside the file, use the real path: `Where=/mnt/usb-backup`.

To trigger from SSH, escape the backslash twice: `systemctl start mnt-usb\\\\x2dbackup.mount`.

### File Layout

| File | Purpose |
|------|---------|
| `bin/pvexb-backup` | Main backup runner |
| `bin/pvexb-send-telegram` | Telegram Bot API helper |
| `config/pvexb.conf.example` | Per-node config template |
| `config/pvexb.env.example` | Telegram credentials template |
| `install.sh` | Installer for Proxmox nodes |
| `systemd/pvexb-backup.service` | Optional systemd service |
| `systemd/pvexb-backup.timer` | Optional monthly timer |
| `logrotate/pvexb-backup` | 6-month log rotation |
| `tests/proxmox-docker/` | Proxmox-in-Docker test harness |

### Future Enhancements

- `POWER_MODE="homeassistant"` — call Home Assistant API directly for power control
- Multi-target backups (USB + NAS in a single run)
- Backup verification and integrity checks
- Automatic NAS health monitoring (SMART, disk space alerts)
