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

The interactive script will walk you through:
- Node.js LXC container creation (name, ID, cores, memory, network)
- Guest room configuration with Home Assistant dashboard URLs
- Admin credentials (bcrypt hashed)
- Reverse proxy setup — choose one of:
  1. **Nginx Proxy Manager** — prints step-by-step NPM dashboard config
  2. **New NGINX container** — creates a dedicated LXC with TLS-ready config
  3. **Skip / Manual** — configure your own proxy later

The script automatically:
- Installs Node.js and dependencies inside the container
- Deploys a systemd service (`guest-portal.service`) for auto-restart and boot persistence
- Detects the container IP and displays it in the setup summary

3. **Access the Portal:**
- Guest Registration: `https://guestportal.<your-fqdn>/`
- Photo Upload: `https://guestportal.<your-fqdn>/photo.html`
- Admin Panel: `https://guestportal.<your-fqdn>/admin.html`
- Protected Uploads: `https://guestportal.<your-fqdn>/admin/uploads`

---

## 🧪 Testing Checklist

- [ ] Register as a guest and test room selection
- [ ] Upload photos, verify guest folders are created
- [ ] Verify Smart Home links per room
- [ ] Log into `/admin.html` and manage rooms
- [ ] Confirm password protection on `/admin/uploads`
- [ ] Verify admin API endpoints return 401 without credentials
- [ ] Test device linking between two devices
- [ ] Extend and check out a guest session from admin panel
- [ ] Run `bash test-suite.sh` to validate all endpoints
- [ ] Verify `systemctl status guest-portal` shows active
- [ ] Confirm service restarts after `systemctl restart guest-portal`

---

## 📁 Key Paths (Inside Container)

| Path | Description |
|------|-------------|
| `/root/guest-portal/` | Application code |
| `/etc/guest-portal/config.json` | Admin credentials, settings |
| `/etc/guest-portal/storage.json` | Rooms and guest data |
| `/etc/guest-portal/sessions.json` | Active session codes |
| `/etc/guest-portal/guest-tokens.json` | Persistent guest tokens |
| `/root/guest-portal/uploads/` | Guest photos and background images |

## 🌐 Deploy to GitHub (Optional)

```bash
git tag v1.3.0
git push origin v1.3.0
```
