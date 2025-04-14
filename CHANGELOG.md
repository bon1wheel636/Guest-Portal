# 📜 Changelog

All notable changes to this project will be documented here.

---


---

## [v1.1.0] - Feature Expansion & Admin Enhancements

### Added
- Admin UI support for session expiration configuration (UI only in this version)
- Session code generation now triggers visual display in guest UI
- Cross-device session code usage via guest input form
- Photo upload UI now displays session code for logged-in guests
- Session code viewer + revoke support in Admin UI
- Upload base directory configurable from Admin Panel
- LXC setup script improved with firewall detection and secure prompts

### Changed
- Admin room list now supports live editing and delete
- Setup script supports multiple guest room initialization
- Session expiration now enforced at 10-minute default (static backend)

### Known Gaps
- Session expiration setting in Admin UI is not yet enforced backend-side
- Session codes can currently be reused
- Dark mode toggle, health check endpoint, and guest photo preview pending

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
