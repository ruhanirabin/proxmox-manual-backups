# AGENTS.md

Concise source of truth for AI agents working on this repo.

## Project

PVEXB is a Bash-based Proxmox USB backup runner. It preserves Home Assistant-triggered operation by default and keeps systemd scheduling optional.

## Versioning

- Semantic Versioning only: `MAJOR.MINOR.PATCH`.
- Root `VERSION` is the single source of truth.
- Any behavior, installer, script, docs, or compatibility change must bump `VERSION`.
- Update `CHANGELOG.md` in the same change as `VERSION`.
- Update `README.md` when user-facing commands, files, install behavior, errors, or defaults change.
- Scripts must read version from `../VERSION` in repo or `/usr/local/share/pvexb/VERSION` after install.

## GitHub Sync

- This repository is public on GitHub; keep `main` synchronized after completed version changes unless the user explicitly says not to push.
- Before committing a version change, verify `VERSION`, `CHANGELOG.md`, and any required `README.md` updates are included.
- Use clear commit messages that describe the user-facing change, for example `docs: add GitHub one-line install instructions`.
- Run the validation commands below before committing.
- After a successful commit, push the current branch to `origin`.

## Naming

- Canonical prefix: `pvexb-`.
- Main command: `bin/pvexb-backup`.
- Telegram helper: `bin/pvexb-send-telegram`.
- Keep compatibility wrappers unless explicitly removed.

## Safety

- Failure paths must be actionable: name the missing/bad file or command and say whether to rerun `install.sh` or edit config/env.
- Do not enable `pvexb-backup.timer` by default.
- Home Assistant mode expects systemd service/timer disabled.
- Preserve existing config/env files; migrate instead of overwrite.
- Back up legacy scripts before replacing them with wrappers.

## Validation

Run before handoff:

```bash
bash -n install.sh
bash -n bin/pvexb-backup
bash -n bin/pvexb-send-telegram
bash -n bin/proxmox-usb-backup
bash -n bin/proxmox_usb_backup.sh
bash -n bin/unmount_usb_backup.sh
bash -n bin/send_telegram.sh
bash bin/pvexb-backup version
bash bin/pvexb-send-telegram --version
```
