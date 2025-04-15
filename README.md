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

Use `setup.sh` inside your Proxmox LXC container or deploy manually. Configure NGINX to proxy `guestportal.<yourdomain>` to port 3000 of the Node.js container.

---

## 📄 Documentation

- [Deployment Guide](DEPLOY.md)
- [Admin Panel](frontend/admin.html)
- [Guest Registration](frontend/index.html)
- [Photo Upload Page](frontend/photo.html)

---

## 🔐 Security

- Admin uploads protected with bcrypt-authenticated Basic Auth
- Uploads stored in a configurable path
- Session codes are one-time and time-limited
