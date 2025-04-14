# 🚀 Guest Portal Deployment Guide

This document provides complete instructions for installing and deploying the Guest Portal application in a secure and containerized Proxmox environment.

---

## ✅ Changelog

| Version | Changes |
|---------|---------|
| v1.0.0  | Initial secure and functional release with bcrypt auth, LXC setup, Smart Home access, photo upload, and admin panel |

---

## 📦 Setup Instructions

1. **Extract the ZIP:**
```bash
unzip guest-portal-v1.0.0-final.zip
cd guest-portal-final
```

2. **Run the Setup Script on Proxmox Host:**
```bash
cd lxc-setup
bash setup.sh
```

- Choose whether to create new LXC containers or use existing ones
- Configure static IPs and bridge (recommended)
- Set up guest rooms and Smart Home dashboard URLs
- Secure admin access (bcrypt hashed password)

3. **Access the Portal:**
- 🧑‍💻 Guest: `https://guestportal.<your-fqdn>`
- 📸 Upload: `https://guestportal.<your-fqdn>/photo.html`
- ⚙️ Admin: `https://guestportal.<your-fqdn>/admin.html`
- 🔐 Protected Uploads: `https://guestportal.<your-fqdn>/admin/uploads`

---

## 🧪 Testing Checklist

- [ ] Register as a guest and test room selection
- [ ] Upload photos, verify guest folders are created
- [ ] Verify Smart Home links per room
- [ ] Log into `/admin.html` and manage rooms
- [ ] Confirm password protection on `/admin/uploads`

---

## 🌐 Deploy to GitHub (Optional)

To publish the code:

```bash
git init
git add .
git commit -m "Initial secure release of Guest Portal"
gh repo create guest-portal --private --source=. --remote=origin
git push -u origin main
```

To create a release, tag it:
```bash
git tag v1.0.0
git push origin v1.0.0
```
