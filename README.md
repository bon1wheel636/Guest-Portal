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
  - Upload base path configuration
  - Background image customization
  - View & revoke session codes
- 👥 Multiple guests per room support
- 🖼️ Customizable landing page background
- 🔐 Secure uploads directory with Basic Auth
- 🧱 Proxmox LXC container deployment
- 🧪 Comprehensive test suite

---

## 🛠️ Requirements

### For Proxmox Deployment
- Proxmox host with storage and bridge access
- Debian 12 template for containers
- NGINX reverse proxy (container or manual)

### For Local Development
- Node.js (v18+ recommended)
- npm

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
- Uploads stored in a configurable path with per-guest folders
- Session codes are one-time and time-limited
- Input validation prevents XSS and path traversal attacks
- Guest tokens for persistent sessions with expiration dates

---

## 🧪 Testing

Run the comprehensive test suite to validate all endpoints:

```bash
bash test-suite.sh
```

This tests registration, photo uploads, session management, admin features, and more.

---

## 🔑 Admin Password Setup

There are **three ways** to set up the admin password:

### Option 1: Proxmox Setup Script (Production)
When running `bash setup.sh` on a Proxmox host, you'll be prompted to set the admin username and password. This is the recommended method for production deployments.

### Option 2: Local Setup Script (Development)
```bash
bash setup-local.sh
```
This interactive script prompts for admin credentials and creates the configuration files.

### Option 3: First-Run Web Setup
If no admin password is configured, visiting `/admin.html` will show an **Initial Admin Setup** form where you can create the admin account directly in the browser.

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
