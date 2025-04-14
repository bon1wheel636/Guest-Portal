# ✅ Guest Portal Project Checklist (v1.0.0)

## Core Features
- [x] Guest registration with name + room selection
- [x] Persistent session recognition (cookies/device)
- [x] Smart Home dashboard link per room
- [x] Upload photo files to per-guest dated folder
- [x] Admin authentication using bcrypt + Basic Auth
- [x] Admin interface to:
  - [x] Add/edit/delete rooms
  - [x] View active session codes
  - [x] Revoke session codes
  - [x] Set session code expiration
  - [x] Configure upload base directory

## Session Code System
- [x] Generate 6-character code for linking sessions
- [x] Enter session code from another device to rejoin session
- [x] Auto-expiration after configurable duration (default 10 min)

## Deployment & Configuration
- [x] Proxmox-compatible `setup.sh` with:
  - [x] Create backend LXC container
  - [x] Optional NGINX container setup
  - [x] Static IP or DHCP configuration
  - [x] Auto-detect and recommend firewall rules
  - [ ] Update-safe deployment detection (planned)
- [x] Manual NGINX config support for existing setups

## Security
- [x] Configurable upload directory
- [x] Basic Auth on `/admin/uploads`
- [x] Session codes are one-time + time-limited

## Documentation
- [x] Final README with full usage guide
- [x] Final CHANGELOG for version history
- [x] Manifest with file sizes and checksums (for ZIP builds)

## Packaging & Version Control
- [x] Verified ZIP includes all required files
- [x] README, CHANGELOG, setup, frontend/backend included
- [x] SHA256 checksum provided per release

