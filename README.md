# 🏠 Guest Portal

A self-hosted, mobile-friendly landing portal for guest Wi-Fi networks. Provides Smart Home access, secure photo uploads, and cross-device session continuity.

[![Version](https://img.shields.io/badge/version-1.3.0-blue.svg)](https://github.com/bon1wheel636/guest-portal/releases/tag/v1.3.0)

---

## ✨ Features

- 🛏️ Guest registration with room selection and checkout date
- 📸 Photo uploads saved per guest with separate folders
- 🔁 Persistent guest sessions (1-30 days, default 7)
- 📱 Device linking - guests can add phones, tablets, and laptops to their session
- 🔐 Admin panel with:
  - Room management
  - Guest session management (view devices, extend stays, check out)
  - Background image customization
  - Configurable upload path (supports NFS/SMB NAS mounts)
  - Guest photo browsing, download (zip), and deletion
  - Session settings (admin timeout, code expiration)
  - View & revoke session codes
- 👥 Multiple guests per room support
- 🖼️ Customizable landing page background
- 🔐 Secure uploads directory with Basic Auth
- 💾 NAS storage support (NFS/SMB mount for guest photos)
- 🧱 Proxmox LXC container deployment
- 🧪 Comprehensive test suite

---

## 🛠️ Requirements

### For Proxmox Deployment
- Proxmox host with storage and bridge access
- Debian 13 or 12 LXC template for containers (installer prefers 13)
- NGINX reverse proxy (container or manual)

### For Local Development
- Node.js (v18+ recommended)
- npm

---

## 🚀 Setup

### Proxmox production (no git on host)

Run this in the **Proxmox host shell**. It downloads the installer with `curl`, creates the LXC, and configures Guest Portal inside the container:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)"
```

Useful modes:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)" -- --dry-run
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)" -- --update <ctid>
```

See [DEPLOY.md](DEPLOY.md) for the manual LXC path (`setup-container.sh` inside the container) and container minimums.

### Manual LXC + in-container setup

Create a Debian 13 or 12 LXC (1 CPU, 512 MiB RAM, 4 GB disk), enter it as root, then:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/scripts/setup-container.sh)"
```

### Optional host git checkout

```bash
git clone https://github.com/<your-user>/guest-portal.git
cd guest-portal
bash setup.sh
```

### What gets configured

- A Node.js LXC for the backend server
- A systemd service for automatic restarts and boot persistence
- DHCP or static IP network configuration
- Smart Home dashboard links per room
- Secure admin password hashing (bcrypt)
- NAS storage setup (optional):
  1. **NFS mount** — auto-configures NFS mount point with fstab entry
  2. **SMB/CIFS mount** — auto-configures SMB mount with stored credentials
  3. **Skip** — use local storage or configure from admin panel later
- Reverse proxy options (Path A / host installer):
  1. **Nginx Proxy Manager** — step-by-step NPM dashboard instructions
  2. **New NGINX container** — creates a dedicated LXC with auto-configured config
  3. **Skip / Manual** — configure your own proxy later

## 📄 Documentation

- [Deployment Guide](DEPLOY.md)
- [UniFi Guest WiFi Guide](UNIFI.md)
- [Reverse Proxy and HTTPS Guide](PROXY.md)
- [Backup and Restore Guide](BACKUP.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Code Review Findings](CODE_REVIEW_FINDINGS.md)

### Application Pages

| Page | Path | Description |
|------|------|-------------|
| Guest Registration | `/` | Room selection, stay length, device linking |
| Guest Welcome Hub | `/welcome.html` | Stay hub: greeting, Smart Home, upload, device linking |
| My Photos | `/photo.html` | Guest gallery for uploads during the current stay |
| Admin Panel | `/admin.html` | Deployment status, room/session/guest management, settings |

---

## 🔐 Security

- All admin API endpoints protected with bcrypt-authenticated HTTP Basic Auth
- Cryptographically secure token generation (`crypto.randomBytes`)
- `/admin.html` uses browser HTTP Basic Auth only (no duplicate login form)
- Rate limiting on all routes (60 req/min)
- Input validation prevents XSS and path traversal attacks
- Guest uploads require an active guest token before files are accepted
- Guest uploads allow photos, videos, and PDFs only; scripts, archives, executables, and macro documents are rejected
- Admin deployment status checks cover app health, upload storage writability, reverse proxy headers, and optional dashboard URL reachability
- Session codes are one-time and time-limited
- Guest tokens for persistent sessions with expiration dates
- HTTPS support with TLS 1.2+, HSTS, and security headers (via nginx config)
- Graceful shutdown on SIGTERM/SIGINT

---

## 🧪 Testing

Run the comprehensive test suite to validate all endpoints:

```bash
ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

This tests registration, token-authenticated uploads, admin authentication, session management, admin features, and more. Without `ADMIN_PASS`, admin mutation tests are skipped and unauthenticated admin rejection is still tested.

---

## 🔑 Admin Password Setup

There are **three ways** to set up the admin password:

### Option 1: Proxmox Setup Script (Production)
When running `bash setup.sh` on a Proxmox host, you'll be prompted to set the admin username and password. This is the recommended method for production deployments.

Useful setup modes:
```bash
bash setup.sh --dry-run
bash setup.sh --update <ctid>
```
Dry run shows the selected install/update plan without changing containers, files, services, or mounts. Update mode detects an existing container and prompts before changing code, service files, app state ownership, NAS upload path, or restarting the service.

Inside the LXC, routine code updates can also use `updateguest` (see [DEPLOY.md](DEPLOY.md)).

### Option 2: Local Setup Script (Development)
```bash
bash setup-local.sh
```
This interactive script prompts for admin credentials and creates the configuration files.

### Option 3: First-Run Web Setup
If no admin password is configured, visiting `/admin.html` will show an **Initial Admin Setup** form where you can create the admin account directly in the browser.

---

## 📸 Photo Storage & Management

Guest photos are stored locally by default in `/opt/guest-portal/uploads/` in production. You can change the storage path from the admin panel under **Upload Storage Path** to point to an NFS or SMB mount on a NAS.

Guest uploads are intentionally limited to photos, videos, HEIC/HEIF phone images, and PDFs. If a guest wants to leave a letter, ask them to upload a PDF or a photo of the note rather than a Word/Pages document or script-capable file.

### NAS Setup
- **During install:** The setup script offers to configure an NFS or SMB mount automatically
- **After install:** Set the upload path from the admin panel to any mounted directory

### Photo Management
From the admin panel **Guest Photos** section:
- **Browse** uploaded folders with file counts and sizes
- **Download** individual folders or all photos as a `.zip`
- **Delete** individual folders or all photos after backing up

---

## 💻 Local Development

To run the portal locally without Proxmox:

```bash
# Install dependencies
npm install

# Option A: Use the setup script (recommended)
bash setup-local.sh

# Option B: Start server and set up via web UI
npm start
# Then visit http://localhost:3000/admin.html to create admin account
```

Access the portal at `http://localhost:3000`
