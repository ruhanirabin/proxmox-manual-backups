# Proxmox Docker Test Harness

Optional, privileged test harness for manual PVEXB checks against a Proxmox-like container.

This is based on the local compose project from `J:\Proxmox Test`, adapted so the repo mounts read-only at `/opt/pvexb` and a fake USB mount exists at `/mnt/usb-backup`.

## Start

```bash
cd tests/proxmox-docker
mkdir -p ISOs VM-Backup USB-Backup
docker compose up -d
```

Web UI: `https://localhost:8006`

SSH:

```bash
ssh -p 2222 root@localhost
```

Default password from compose: `123`

## Manual PVEXB Install Inside Container

```bash
cd /opt/pvexb
PVEXB_INSTALL_NONINTERACTIVE=true ./install.sh
```

If storage `usb-local-backup` does not exist, create it inside the container:

```bash
pvesm add dir usb-local-backup --path /mnt/usb-backup --content backup
```

Then run:

```bash
pvexb-backup check
```

Full `vzdump` backup tests require a VM/LXC that exists inside the test Proxmox container and a matching `VM_LIST` in `/etc/pvexb.conf`.

## Stop

```bash
docker compose down
```

The runtime folders `ISOs/`, `VM-Backup/`, and `USB-Backup/` are ignored by git.
