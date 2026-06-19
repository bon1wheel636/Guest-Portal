# 🚀 Guest Portal Deployment Guide

This document provides complete instructions for installing and deploying the Guest Portal application in a secure and containerized Proxmox environment.

---

## 📦 Setup Instructions

Choose one of the install paths below. **Git is not required on the Proxmox host** for either path.

### Path A — Remote installer from Proxmox host (recommended)

Run this directly in the **Proxmox host shell**. It downloads the installer with `curl` and creates the Guest Portal LXC for you:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)"
```

Preview the plan without making changes:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)" -- --dry-run
```

Update an existing container from the host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)" -- --update <ctid>
```

Host requirements: `curl`, `bash`, and Proxmox `pct`. Git stays inside the container.

### Path B — Manual LXC, then setup inside the container

Use this if you prefer to create the LXC yourself (Proxmox UI, Terraform, another tool) and only run Guest Portal setup inside it.

**Container minimums**

| Setting | Recommended |
|---------|-------------|
| OS template | Debian 13 preferred (`debian-13-standard`); Debian 12 used if 13 is not downloaded |
| CPU | 1 core |
| RAM | 512 MiB |
| Disk | 4 GB |
| Network | DHCP or static on your guest VLAN bridge |
| Features | `nesting=1` if you plan container-managed tooling later |
| Isolation | Unprivileged (recommended) |

**Steps**

1. Create and start the LXC from the Proxmox UI or your own automation.
2. Enter the container console as root:

```bash
pct enter <ctid>
```

3. Run the in-container installer (installs `git`, clones the app, configures systemd):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/scripts/setup-container.sh)"
```

Preview only:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/scripts/setup-container.sh)" -- --dry-run
```

Refresh an existing in-container install:

```bash
updateguest
```

or:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/scripts/setup-container.sh)" -- --update
```

Path B does **not** create a separate NGINX LXC. Point Nginx Proxy Manager or your own reverse proxy at the container IP on port `3000`. See [PROXY.md](PROXY.md).

### What the installers configure

Both paths walk you through (or the host installer delegates to the container for):
- Node.js LXC container creation (name, ID, cores, memory, network)
- Container isolation selection, defaulting to an unprivileged LXC
- Guest room configuration with Home Assistant dashboard URLs
- Admin credentials (bcrypt hashed)
- NAS storage setup (optional) — choose one of:
  1. **NFS mount** — installs nfs-common, mounts the share, adds fstab entry
  2. **SMB/CIFS mount** — installs cifs-utils, stores credentials securely, mounts and adds fstab entry
  3. **Existing mounted directory** — best for host-mounted NAS shares bind-mounted into an unprivileged LXC
  4. **Skip** — use local storage or configure from admin panel later
- Reverse proxy setup (Path A only) — choose one of:
  1. **Nginx Proxy Manager** — prints step-by-step NPM dashboard config
  2. **New NGINX container** — creates a dedicated LXC with TLS-ready config
  3. **Skip / Manual** — configure your own proxy later

The script automatically:
- Installs Node.js and dependencies inside the container
- Creates a dedicated `guestportal` service user
- Deploys a non-root systemd service (`guest-portal.service`) for auto-restart and boot persistence
- Detects the container IP and displays it in the setup summary

Update mode prompts before changing application code, `/etc/guest-portal` ownership or state files, the systemd service, NAS upload path settings, or restarting the service.

### Optional — git checkout on the host

If you are developing or want a local copy of the scripts on the Proxmox host:

```bash
git clone https://github.com/bon1wheel636/guest-portal.git
cd guest-portal
bash setup.sh
```

This is optional. Production installs do not need git on the host.

### Access the portal
- Guest Registration: `https://guestportal.<your-fqdn>/`
- Photo Upload: `https://guestportal.<your-fqdn>/photo.html`
- Admin Panel: `https://guestportal.<your-fqdn>/admin.html`
- Protected Uploads: `https://guestportal.<your-fqdn>/admin/uploads`

For UniFi guest WiFi deployments, use the UniFi hotspot or guest network as the admission gate and set its post-authorization redirect to the Guest Portal registration URL. See [UNIFI.md](UNIFI.md) for the recommended configuration path and the future external portal integration option. See [PROXY.md](PROXY.md) for Nginx Proxy Manager and HTTPS guidance.

---

## Troubleshooting install

### Installer stops at "Creating LXC container..." with no error

Older installer versions hid `pct create` failures. Re-run with the latest `install.sh`, which now prints the Proxmox error.

**Most common causes:**

1. **Hardcoded template version mismatch** (fixed in current installer)

The old installer targeted `debian-12-standard_12.0-1` exactly. If you only have a newer build (for example `12.12-1` or `13.1-2`), `pct create` failed silently. The current installer auto-selects the newest local `debian-13-standard` template, or falls back to `debian-12-standard`.

2. **No Debian 13 or 12 template downloaded**

```bash
pveam update
pveam available | grep -E 'debian-13|debian-12'
pveam download local debian-13-standard
pveam list local
```

2. **Storage name differs** (not `local-lvm`)

```bash
pvesm status
```

The installer auto-selects `local-lvm` or `local-zfs`. If neither exists, create container storage in Proxmox or use Path B (manual LXC + `setup-container.sh`).

3. **Wrong bridge** (default `vmbr0`)

```bash
ip -br link show type bridge
```

Re-run the installer and choose **Advanced Settings** to set the correct bridge.

4. **Container ID already in use**

```bash
pct list
```

Pick an unused ID in Advanced Settings, or delete the partial container if one was half-created.

**Manual test** (replace `100` and template/storage names with yours):

```bash
pct create 100 local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname guest-portal-test \
  --cores 1 --memory 512 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --rootfs local-lvm:4 \
  --unprivileged 1
```

If that command prints an error, fix that issue before rerunning the installer.

---

### From the Proxmox host (full installer)

Use the remote installer with `--update`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)" -- --update <ctid>
```

Or, if you have a git checkout on the host:

```bash
bash setup.sh --update <ctid>
```

### From inside the Guest Portal LXC

After install or update, the container includes an `updateguest` command:

```bash
updateguest
```

Preview the steps without making changes:

```bash
updateguest --dry-run
```

Skip the confirmation prompt:

```bash
updateguest -y
```

You can also run it from the Proxmox host without entering the container:

```bash
pct exec <ctid> -- updateguest
```

`updateguest` will:

1. `git pull --ff-only` in `/opt/guest-portal`
2. Run `npm install`
3. Ensure upload directories and ownership are correct
4. Refresh the `updateguest` command itself
5. Restart the `guest-portal` service

Use `setup.sh --update` when you also need to rewrite the systemd service, fix `/etc/guest-portal` ownership, or change the NAS upload path with prompts. Use `updateguest` for routine code updates from the LXC console.

---

## 📸 Photo Storage

Guest photos are stored locally by default in `/opt/guest-portal/uploads/`. To store photos on a NAS:

### During Setup
The setup script offers NFS and SMB mount options that automatically configure the mount point, fstab entry, and upload path in the application config. For unprivileged LXCs, prefer mounting the NAS share on the Proxmox host and bind-mounting it into the container, then choose the existing mounted directory option.

### After Setup
From the admin panel under **Upload Storage Path**, you can change the upload directory to any mounted path (e.g. `/mnt/nas/guest-photos`). The directory must exist and be writable.

### Photo Management
From the admin panel **Guest Photos** section:
- Browse uploaded folders with file counts and sizes
- Download individual folders or all photos as a `.zip`
- Delete individual folders or all photos after backing up

Only photos, videos, and PDFs are accepted. Keep the NAS share dedicated to guest uploads, quota-limited, and mounted with restrictive options such as `noexec,nodev,nosuid` when possible.

See [BACKUP.md](BACKUP.md) for config backup, restore, and NAS permission checks.

---

## 🧪 Testing Checklist

- [ ] Register as a guest and test room selection
- [ ] Upload photos with a registered guest session and verify guest folders are created
- [ ] Verify `/upload` returns 401 without `X-Guest-Token`
- [ ] Verify script/code uploads are rejected
- [ ] Verify Smart Home links per room
- [ ] Log into `/admin.html` and manage rooms
- [ ] In `/admin.html`, verify Deployment Status shows app health and upload storage writable
- [ ] Use **Check Dashboard URLs** in Deployment Status to verify Home Assistant dashboard reachability
- [ ] Confirm reverse proxy headers show HTTPS after Nginx Proxy Manager is configured
- [ ] Confirm password protection on `/admin/uploads`
- [ ] Verify admin API endpoints return 401 without credentials
- [ ] Test device linking between two devices
- [ ] Extend and check out a guest session from admin panel
- [ ] Set upload path to a NAS mount and verify uploads go there
- [ ] Download guest photos as zip from admin panel
- [ ] Delete a guest photo folder from admin panel
- [ ] Reset upload path to default and verify it works
- [ ] Run `ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh` to validate all endpoints
- [ ] Verify `systemctl status guest-portal` shows active
- [ ] Confirm service restarts after `systemctl restart guest-portal`
- [ ] Run remote installer dry-run: `bash -c "$(curl -fsSL .../install.sh)" -- --dry-run`
- [ ] Use `bash setup.sh --update <ctid>` for existing installs and confirm prompts before changes
- [ ] Run `updateguest --dry-run` inside the LXC, then `updateguest` for routine code updates

---

## 📁 Key Paths (Inside Container)

| Path | Description |
|------|-------------|
| `/opt/guest-portal/` | Application code |
| `/usr/local/bin/updateguest` | In-container update command |
| `/etc/guest-portal/config.json` | Admin credentials, upload path, settings |
| `/etc/guest-portal/storage.json` | Rooms and guest data |
| `/etc/guest-portal/sessions.json` | Active session codes |
| `/etc/guest-portal/guest-tokens.json` | Persistent guest tokens |
| `/opt/guest-portal/uploads/` | Guest photos (default, configurable) |
| `/mnt/nas/guest-photos/` | Guest photos (if NAS mount configured) |
| `/etc/guest-portal/.smbcredentials` | SMB credentials (if SMB mount used) |

## 🌐 Deploy to GitHub (Optional)

```bash
git tag v1.3.0
git push origin v1.3.0
```
