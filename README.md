# PVEXB Proxmox USB Backup

Reusable Bash tooling for Proxmox backups with Home Assistant-compatible triggering, per-node configuration, logging, and Telegram notifications. Supports both USB external drive and network/NAS backup targets.

`pvexb-` is the canonical prefix for installed files to reduce naming conflicts on shared Proxmox hosts.

The root `VERSION` file is the single source of truth; `CHANGELOG.md` tracks SemVer changes.

## Current Flow

This keeps the existing Home Assistant flow intact:

1. Home Assistant turns on the smart plug for the external USB drive.
2. Home Assistant mounts the USB drive and executes a backup command on the Proxmox node.
3. The script waits for `/mnt/usb-backup` to be mounted (if not already).
4. The script runs `vzdump` for the configured VM/LXC IDs.
5. The script unmounts the USB drive.
6. Home Assistant turns off the plug after its existing timeout window.

The default `POWER_MODE="external"` means Home Assistant or another external automation owns power control. Set `POWER_MODE="network"` to use a WOL-capable NAS with NFS instead.

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

Other commands:

```bash
/usr/local/bin/pvexb-backup check
/usr/local/bin/pvexb-backup unmount
/usr/local/bin/pvexb-backup version
```

`check` validates config, waits for the mount, checks Proxmox storage, and checks free space without running `vzdump`.

## External Triggering

PVEXB does **not** mount or power the USB drive. It only waits for the mount point to appear. Power control and mounting are handled by an external system (Home Assistant, another agent, or manual SSH).

### Home Assistant

**Simple approach: direct mount + backup in one SSH call**

```yaml
shell_command:
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'mount /dev/disk/by-uuid/<USB-UUID> /mnt/usb-backup && sleep 5 && /usr/local/bin/proxmox_usb_backup.sh'"
```

Replace `<USB-UUID>` with the UUID from `lsblk -f` on the Proxmox node. The flow:

1. HA turns on smart plug
2. HA runs the shell command (mount, settle, backup)
3. PVEXB waits for mount (already mounted, so proceeds), runs vzdump, unmounts
4. HA turns off smart plug after its timeout

**Alternative: mount separately, then backup**

```yaml
shell_command:
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 /usr/local/bin/proxmox_usb_backup.sh"
```

In this case, HA must mount the drive before calling the backup command (e.g., via a separate shell_command or a mount script).

**Systemd mount unit approach** (if you have a properly configured unit):

```yaml
shell_command:
  pvexb_backup: "ssh -i /config/ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.71.1 'systemctl start mnt-usb\\x2dbackup.mount && sleep 10 && /usr/local/bin/proxmox_usb_backup.sh'"
```

Note the `\\x2d` escaping for hyphens in the systemd unit name.

### Other Automation Systems / AI Agents

Any external system can trigger PVEXB via SSH:

```bash
# Step 1: Power on USB drive (smart plug, relay, etc.)
# Step 2: Mount the drive
ssh root@proxmox-node "mount /dev/disk/by-uuid/<USB-UUID> /mnt/usb-backup"
sleep 5

# Step 3: Run backup
ssh root@proxmox-node "/usr/local/bin/pvexb-backup run"

# Step 4: Power off USB drive after backup completes
```

PVEXB handles the wait-for-mount, per-VM backup, auto-unmount, and notifications. The external system only needs to handle power control and initial mount.

## Retention

Backup retention is controlled by the Proxmox storage definition in `/etc/pve/storage.cfg`:

```
dir: usb-local-backup
    path /mnt/usb-backup
    content backup
    prune-backups keep-last=3
```

This means `vzdump` keeps the last 3 backups per VM. Edit `keep-last` to change the retention count.

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

## Troubleshooting

### USB drive is powered on but not mounted

PVEXB does **not** mount the drive -- it only waits for it. The drive must be mounted by something else before PVEXB runs.

```bash
# Check if mounted
mountpoint -q /mnt/usb-backup && echo "MOUNTED" || echo "NOT MOUNTED"

# Find the USB partition and its UUID
lsblk -f | grep -v loop

# Mount manually
mount /dev/sdX1 /mnt/usb-backup
# Or by UUID:
mount /dev/disk/by-uuid/<UUID> /mnt/usb-backup
```

### Why did my backups stop working?

The most common reason: the USB drive was powered on but **never auto-mounted** after a power cycle. The old script only waited for the mount point -- if nothing mounted it, backups silently failed.

**Fix:** ensure the drive gets mounted before PVEXB runs. The simplest approach is to include `mount` in your HA shell_command (see External Triggering above).

### PVEXB check fails with storage error

```bash
pvesm status --storage usb-local-backup
```

If this fails, the Proxmox storage definition in `/etc/pve/storage.cfg` is missing or misconfigured. Ensure the `dir` storage entry exists and points to `/mnt/usb-backup`.

### Low free space error

```bash
df -h /mnt/usb-backup
```

PVEXB enforces `MIN_FREE_GB` (default 100GB) before starting backups. Clean old backups or reduce retention with `prune-backups` in `/etc/pve/storage.cfg`.

### Another backup is already running

PVEXB uses a lock file at `/run/pvexb-backup.lock` to prevent concurrent runs. If a previous run crashed and left a stale lock:

```bash
rm -f /run/pvexb-backup.lock
```

### Telegram notifications not working

1. Check credentials: `cat /root/.pvexb.env`
2. Test the helper directly: `/usr/local/bin/pvexb-send-telegram "test"`
3. Ensure `TELEGRAM_ENABLED=true` in `/etc/pvexb.conf`
4. Check the Telegram log: `cat /var/log/pvexb/pvexb-telegram.log`

### Logs

- Main log: `/var/log/pvexb/pvexb-backup.log`
- Per-run logs: `/var/log/pvexb/<RUN-ID>-<NODE>.log`
- Watch live: `tail -f /var/log/pvexb/pvexb-backup.log`

### systemd mount unit with hyphens in path

If you use a systemd mount unit for `/mnt/usb-backup`, the unit filename **must** use `\x2d` to encode the hyphen:

```
/etc/systemd/system/mnt-usb\x2dbackup.mount
```

The backslash-x2d is literal in the filename. Inside the file, use the real path:

```
Where=/mnt/usb-backup
```

To trigger it from SSH/HA, escape the backslash twice:

```bash
systemctl start mnt-usb\\x2dbackup.mount
```

## Power Modes

PVEXB supports three power/backup modes via the `POWER_MODE` variable in `/etc/pvexb.conf`:

| Mode | Description | Use Case |
|------|-------------|----------|
| `external` | An external system (Home Assistant, manual SSH) handles power and mount | USB drive on smart plug |
| `command` | Custom local commands defined by `POWER_ON_CMD` / `POWER_OFF_CMD` | Smart plug via CLI, IPMI, relay |
| `network` | Built-in WOL + NFS mount to a wakeable NAS | Synology/QNAP NAS with NFS share |

### Network Backup Mode

`POWER_MODE=network` allows PVEXB to back up directly to a network-attached storage device (NAS) using NFS, with automatic power management. The NAS stays asleep (saving power and reducing noise) until a backup is triggered, at which point PVEXB wakes it via Wake-on-LAN, mounts the NFS share, runs the backups, unmounts, and optionally puts the NAS back to sleep.

#### Architecture

```
Trigger (HA / systemd / SSH)
        │
        ▼
  SSH to Proxmox node
        │
        ▼
  pvexb-backup run
        │
        ├── POWER_MODE=network ──► WOL to NAS (MAC: NAS_MAC)
        │                                │
        │                                ▼
        │                          ping until NAS_IP responds
        │                          (NAS_PING_TIMEOUT / NAS_PING_INTERVAL)
        │                                │
        │                                ▼
        │                          mount NFS (NAS_IP:NFS_EXPORT → MOUNT_POINT)
        │                                │
        │                                ▼
        │                          vzdump → NFS storage
        │                                │
        │                                ▼
        │                          unmount NFS
        │                                │
        │                                ▼
        │                          sleep NAS (SSH or custom cmd)
        │                          [if within NAS_SLEEP_WINDOW]
        │
        └── POWER_MODE=external ───► wait for mount → vzdump → unmount
```

#### Network Config Variables

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `NAS_MAC` | Yes | MAC address of NAS Ethernet port for WOL | `00:11:22:33:44:55` |
| `NAS_IP` | Yes | IP address of the NAS | `192.168.71.50` |
| `NAS_SSH_USER` | Optional | SSH user for NAS sleep command (default: `root`) | `admin` |
| `NAS_SSH_KEY` | Optional | SSH private key path for NAS authentication | `~/.ssh/nas_key` |
| `NFS_EXPORT` | Yes | NFS export path on the NAS | `/volume1/proxmox-backups` |
| `NFS_OPTIONS` | Optional | NFS mount options (default: `soft,noatime,nofail,vers=4.1`) | `soft,timeo=30` |
| `NAS_SLEEP_MODE` | Optional | How to sleep NAS: `disabled`, `ssh`, or `command` (default: `disabled`) | `ssh` |
| `NAS_SLEEP_CMD` | Optional | Command to sleep NAS (default: `synopoweroff -s`) | `poweroff` |
| `NAS_SLEEP_WINDOW` | Optional | When to allow sleep: `Mon-Fri 01:00-07:00`, `daily`, or empty (always) | `Mon-Fri 01:00-07:00` |
| `NAS_PING_TIMEOUT` | Optional | Max seconds to wait for NAS ping (default: `300`) | `180` |
| `NAS_PING_INTERVAL` | Optional | Seconds between ping retries (default: `5`) | `10` |

#### Setup Checklist

**Synology DSM (NAS side):**

1. **Enable WOL:** Control Panel → Hardware & Power → General → Enable Wake on LAN (WOL)
2. **Enable NFS:** Control Panel → File Services → NFS → Enable NFS service (v3 or v4)
3. **Create shared folder** for backups (e.g., `proxmox-backups`)
4. **Set NFS permissions** on the shared folder:
   - Hostname/IP: Proxmox node IP (e.g., `192.168.71.1`)
   - Privilege: Read/Write
   - Squash: No mapping (or map to root/admin user)
   - Security: sys
5. **Enable SSH:** Control Panel → Terminal & SNMP → Enable SSH service
6. **Note the NAS MAC address** (Control Panel → Info Center → Network)

**Proxmox node side:**

1. **Install dependencies:**
   ```bash
   apt install -y nfs-common wakeonlan   # or etherwake
   ```
2. **Configure `/etc/pvexb.conf`:**
   ```bash
   POWER_MODE="network"
   NAS_MAC="00:11:22:33:44:55"
   NAS_IP="192.168.71.50"
   NAS_SSH_USER="admin"
   NFS_EXPORT="/volume1/proxmox-backups"
   NFS_OPTIONS="soft,noatime,nofail,vers=4.1"
   NAS_SLEEP_MODE="ssh"
   NAS_SLEEP_WINDOW="Mon-Fri 01:00-07:00"
```
3. **Set up SSH key for NAS sleep** (if using `NAS_SLEEP_MODE=ssh`):
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/nas_key -N ""
   ssh-copy-id -i ~/.ssh/nas_key admin@192.168.71.50
   # Then set NAS_SSH_KEY="~/.ssh/nas_key" in /etc/pvexb.conf
   ```
4. **Test WOL manually:**
   ```bash
   wakeonlan 00:11:22:33:44:55
   ping -c 3 192.168.71.50
   ```
5. **Test NFS mount:**
   ```bash
   mkdir -p /mnt/pve/prox-backup
   mount -t nfs 192.168.71.50:/volume1/proxmox-backups /mnt/pve/prox-backup
   ls /mnt/pve/prox-backup
   umount /mnt/pve/prox-backup
   ```
6. **Run `pvexb-backup check`** to validate full configuration.

### USB vs Network Backup Comparison

| Feature | USB (`external`) | Network (`network`) |
|---------|-------------------|---------------------|
| **Target** | USB drive on smart plug | NAS via NFS |
| **Power control** | External (HA, smart plug) | Built-in WOL |
| **Mount type** | Local device mount | NFS network mount |
| **Speed** | USB 3.0 (~100-500 MB/s) | Gigabit Ethernet (~100 MB/s) |
| **Noise/Power** | Drive spins only when plug is on | NAS sleeps between backups |
| **Setup complexity** | Low (plug + mount) | Medium (WOL + NFS + SSH) |
| **Best for** | Single node, simple setup | Multi-node, centralized storage |
| **Sleep support** | Via smart plug automation | Built-in NAS sleep command |

## Future Enhancements

Future versions may add:

- `POWER_MODE="homeassistant"` — call Home Assistant API directly for power control
- Multi-target backups (USB + NAS in a single run)
- Backup verification and integrity checks
- Automatic NAS health monitoring (SMART, disk space alerts)
