# 🚀 Guest Portal Deployment Guide

This document provides complete instructions for installing and deploying the Guest Portal application in a secure and containerized Proxmox environment.

---

## 📦 Setup Instructions

1. **Clone or Extract the Project:**
```bash
git clone https://github.com/bon1wheel636/guest-portal.git
cd guest-portal
```

2. **Run the Setup Script on Proxmox Host:**
```bash
bash setup.sh
```

To preview the install plan without changing anything:
```bash
bash setup.sh --dry-run
```

To update an existing container safely:
```bash
bash setup.sh --update <ctid>
```

The interactive script will walk you through:
- Node.js LXC container creation (name, ID, cores, memory, network)
- Container isolation selection, defaulting to an unprivileged LXC
- Guest room configuration with Home Assistant dashboard URLs
- Admin credentials (bcrypt hashed)
- NAS storage setup (optional) — choose one of:
  1. **NFS mount** — installs nfs-common, mounts the share, adds fstab entry
  2. **SMB/CIFS mount** — installs cifs-utils, stores credentials securely, mounts and adds fstab entry
  3. **Existing mounted directory** — best for host-mounted NAS shares bind-mounted into an unprivileged LXC
  4. **Skip** — use local storage or configure from admin panel later
- Reverse proxy setup — choose one of:
  1. **Nginx Proxy Manager** — prints step-by-step NPM dashboard config
  2. **New NGINX container** — creates a dedicated LXC with TLS-ready config
  3. **Skip / Manual** — configure your own proxy later

The script automatically:
- Installs Node.js and dependencies inside the container
- Creates a dedicated `guestportal` service user
- Deploys a non-root systemd service (`guest-portal.service`) for auto-restart and boot persistence
- Detects the container IP and displays it in the setup summary

Update mode prompts before changing application code, `/etc/guest-portal` ownership or state files, the systemd service, NAS upload path settings, or restarting the service.

3. **Access the Portal:**
- Guest Registration: `https://guestportal.<your-fqdn>/`
- Photo Upload: `https://guestportal.<your-fqdn>/photo.html`
- Admin Panel: `https://guestportal.<your-fqdn>/admin.html`
- Protected Uploads: `https://guestportal.<your-fqdn>/admin/uploads`

For UniFi guest WiFi deployments, use the UniFi hotspot or guest network as the admission gate and set its post-authorization redirect to the Guest Portal registration URL. See [UNIFI.md](UNIFI.md) for the recommended configuration path and the future external portal integration option. See [PROXY.md](PROXY.md) for Nginx Proxy Manager and HTTPS guidance.

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
- [ ] Run `bash setup.sh --dry-run` before future install changes
- [ ] Use `bash setup.sh --update <ctid>` for existing installs and confirm prompts before changes

---

## 📁 Key Paths (Inside Container)

| Path | Description |
|------|-------------|
| `/opt/guest-portal/` | Application code |
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
