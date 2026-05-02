# Changelog

All notable changes follow Semantic Versioning.

## [1.0.1] - 2026-05-02

### Changed
- Home Assistant `shell_command` examples now use `nohup ... &` for fire-and-forget
  async backup execution to avoid HA's ~60s command timeout on multi-VM backups

## [1.0.0] - 2026-05-02

### Added
- **POWER_MODE=network**: Support for NFS-based backups to a sleeping/wakeable NAS
  - WOL (Wake-on-LAN) to power on NAS before backup
  - Automatic NFS mount/unmount around backup window
  - Configurable NAS sleep after backup (SSH or custom command)
  - Sleep window scheduling (e.g., weekdays 1AM-7AM only)
  - New config variables: NAS_MAC, NAS_IP, NAS_SSH_USER, NFS_EXPORT, NFS_OPTIONS,
    NAS_SLEEP_MODE, NAS_SLEEP_CMD, NAS_SLEEP_WINDOW, NAS_PING_TIMEOUT, NAS_PING_INTERVAL
- Network dependency checks in install.sh (wakeonlan/etherwake, nfs-common)
- Network config section in pvexb.conf.example

### Changed
- POWER_MODE validation now accepts: external, command, network
- vzdump output now always logged to run log (removed --quiet flag)
- Version bump to 1.0.0 for new network backup architecture

### Compatibility
- POWER_MODE=external (USB) flow is fully unchanged -- existing node-01 setups continue to work
- All existing config variables, file names, and commands remain the same
- install.sh preserves existing config files and creates backups of legacy files

## [0.7.8] - 2026-05-01

- Added comprehensive troubleshooting section to README covering: mount failures, silent backup detection, storage errors, low free space, stale locks, Telegram issues, systemd hyphen escaping, and log locations.
- Added external triggering section with Home Assistant, systemd, and SSH/agent integration examples including direct mount approach.
- Added retention documentation explaining prune-backups in storage.cfg.
- Clarified that PVEXB does not mount or power the USB drive — only waits for mount.

## [0.7.7] - 2026-05-01

- Fixed GitHub one-line install: added `chmod +x install.sh` after tar extraction since `.tar.gz` archives from GitHub do not preserve executable permissions.

## [0.7.6] - 2026-04-29

- Added agent instructions for committing and syncing completed version changes to the public GitHub repository.

## [0.7.5] - 2026-04-29

- Added Proxmox host one-line GitHub install documentation with installer environment parameter examples.

## [0.7.4] - 2026-04-29

- Added an optional Proxmox-in-Docker test harness under `tests/proxmox-docker/`.
- Ignored test harness runtime data directories.

## [0.7.3] - 2026-04-29

- Added MIT license.
- Added `.gitignore` with common local artifacts and legacy `old-files/` exclusion.

## [0.7.2] - 2026-04-29

- Improved graceful failure messages for missing configs, missing dependencies, invalid Telegram env, and missing canonical wrapper targets.
- Added installer preflight checks for required repo files, commands, and SemVer source.
- Added agent instructions requiring version, changelog, and README updates for behavior changes.

## [0.7.1] - 2026-04-29

- Added `pvexb-` canonical naming with backward-compatible wrappers.
- Added install-time migration from legacy scripts/config/env files.
- Added Telegram credential setup during install.
- Added Home Assistant-safe systemd disabling by default.
- Added centralized version tracking via `VERSION`.
- Added script headers with relative dependency markers.
