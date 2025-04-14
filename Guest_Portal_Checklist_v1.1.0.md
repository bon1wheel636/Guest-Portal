# ✅ Guest Portal Project Checklist (v1.1.0+)

## ✅ Core Features (Completed)
- [x] Guest registration with name + room selection
- [x] Persistent session recognition (localStorage)
- [x] Smart Home dashboard link per room
- [x] Upload photo files to per-guest dated folder
- [x] Admin authentication using bcrypt + Basic Auth
- [x] Admin interface to:
  - [x] Add/edit/delete rooms
  - [x] View active session codes
  - [x] Revoke session codes
  - [x] Set session code expiration (UI only in v1.1.0)
  - [x] Configure upload base directory

## ✅ Session Code System
- [x] Generate 6-character code for linking sessions
- [x] Enter session code from another device to rejoin session
- [x] Auto-expiration after 10 minutes
- [ ] Prevent session code reuse
- [ ] Enforce expiration time setting from Admin UI (placeholder in v1.1.0)

## ✅ Deployment & Configuration
- [x] Proxmox-compatible `setup.sh` with:
  - [x] Create backend LXC container
  - [x] Optional NGINX container setup
  - [x] Static IP or DHCP configuration
  - [x] Auto-detect and recommend firewall rules
- [x] Manual NGINX config support
- [ ] Update-safe deployment detection (planned)

## ✅ Frontend & UI Enhancements
- [ ] Add dark mode toggle
  - [ ] Respect system preference if present
  - [ ] Default to dark mode when not detectable
- [ ] Add health check endpoint (e.g. `/health`)
- [ ] Display current upload base directory in Admin UI
- [ ] Photo preview/gallery viewer per guest folder

## ✅ Admin Features
- [x] Guest registration timestamps shown in Admin view
- [x] Admin login logic via panel with persistent auth

## ✅ Security
- [x] Configurable upload directory
- [x] Basic Auth on `/admin/uploads`
- [x] Session codes are one-time and time-limited (partially enforced)

## ✅ Documentation
- [x] README with full usage guide
- [x] DEPLOY.md with secure container instructions
- [x] File manifest with size and integrity hash (for release ZIPs)
- [ ] Changelog entry for v1.1.0

## ✅ Packaging & Version Control
- [x] Release ZIP includes all required files
- [x] Frontend, backend, setup, and documentation included
- [x] SHA256 checksums verified
