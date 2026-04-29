# Changelog

All notable changes follow Semantic Versioning.

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
