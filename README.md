# 🏠 Guest Portal

A self-hosted, mobile-friendly landing portal for guest Wi-Fi networks. Provides Smart Home access, secure photo uploads, and cross-device session continuity.

[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](https://github.com/<your-user>/guest-portal/releases/tag/v1.0.0)

---

## ✨ Features

- 🛏️ Guest registration with room selection
- 📸 Photo uploads saved by guest name and date
- 🔁 Session continuity using cookies and 6-character session codes (one-time use)
- 🔐 Admin panel with:
  - Room management
  - Upload base path configuration
  - Session expiration setting (admin-configurable)
  - View & revoke session codes
- 🔐 Secure uploads directory with Basic Auth
- 🧱 Proxmox LXC container deployment
- 🌐 GitHub Pages-ready documentation site

---

## 🛠️ Requirements

- Proxmox host with storage and bridge access
- Debian 12 template for containers
- NGINX reverse proxy (container or manual)
- Node.js + bcrypt inside backend container

---

## 🚀 Setup

To deploy the Guest Portal, run the setup script directly from your **Proxmox host shell**. It will create the required containers and push the project files automatically.

### 1. Clone or unzip the project

```bash
git clone https://github.com/<your-user>/guest-portal.git
cd guest-portal
```

### 2. Run the setup script from the host

```bash
cd lxc-setup
bash setup.sh
```

- This script creates and configures:
  - A Node.js container for the backend server
  - Optionally, an NGINX container for reverse proxying
- It supports:
  - DHCP or static IP network configuration
  - Smart Home dashboard links per room
  - Secure admin password hashing (bcrypt)
  - Session expiration and upload directory settings
## 📄 Documentation

- [Deployment Guide](DEPLOY.md)
- [Admin Panel](admin.html)
- [Guest Registration](index.html)
- [Photo Upload Page](photo.html)

---

## 🔐 Security

- Admin uploads protected with bcrypt-authenticated Basic Auth
- Uploads stored in a configurable path
- Session codes are one-time and time-limited
