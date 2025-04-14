# 📜 Changelog

All notable changes to this project will be documented here.

---

## [v1.0.2] - Patch Release

### Added
- Update-safe deployment logic: `setup.sh` now preserves `config.json` and `storage.json` if they already exist in the container
- Dynamic container ID suggestion: `setup.sh` checks for existing container IDs and recommends the next available to avoid conflicts



## [v1.0.2] - Patch Release

### Added
- Update-safe deployment logic: `setup.sh` now skips overwriting `config.json` and `storage.json` if they already exist
- Dynamic container ID suggestion: `setup.sh` recommends the next available LXC ID based on current host usage

## [v1.0.0] - Initial Release

### Added
- Full guest registration system with local cookie/device tracking
- Room-specific Smart Home dashboard linking
- Photo upload feature with name-date based folder creation
- Admin UI for room management (add, update, delete)
- Secure bcrypt-protected admin upload viewer
- LXC deployment script for Proxmox with static IP and bridge setup
- Optional NGINX reverse proxy configuration
- GitHub Pages-ready documentation index
- Session code generation (`POST /session`) and retrieval (`GET /session/:code`)
- Guest cross-device session linking using 6-character codes
- Admin panel enhancements:
  - View and revoke session codes
  - Set session code expiration time
  - Configure upload base directory path
- UI enhancements in `index.html`, `photo.html`, and `admin.html`
- Backend updates in `server.js` to support all new APIs

---

## [v0.9.5] - Pre-Release Candidate

- Included all final features for test packaging and staging

---

## [v0.9] - Baseline Upload

- Initial version with:
  - Registration form
  - Photo uploads per guest/date
  - Smart Home room routing
  - Admin login and room editor
