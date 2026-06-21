# 📜 Changelog

All notable changes to this project will be documented here.

---

## [Unreleased]

### Added
- Admin Overview now includes Guest Entry Health for `/health`, `/`, `/guest/rooms`, `/welcome.html`, `/photo.html`, and guest room count.
- Admin Guest Photos now includes image previews and per-file upload metadata.
- CSV exports for active guest sessions and registration history.
- Device link code responses now include a same-origin link URL and QR SVG for easier second-device setup, including admin-generated codes for active guest sessions.
- Guest welcome hub at `/welcome.html` with Smart Home link, inline upload, device linking, and Welcome | My Photos navigation.
- First-stay tutorial modal on the welcome hub after registration.
- Returning-device recognition via `/guest/validate` and registration responses (`returningDevice` flag).
- Guest-scoped upload APIs: `GET /guest/uploads`, `GET /guest/uploads/:filename`, and `DELETE /guest/uploads/:filename`.
- Guest photo gallery on `/photo.html` with per-file delete for mistaken uploads.
- Reverse proxy/HTTPS guide for Nginx Proxy Manager, split DNS, DNS challenge certificates, and generic security headers.
- Backup and restore guide for `/etc/guest-portal`, local uploads, NAS-backed uploads, and permission checks.
- Authenticated deployment status endpoint and admin panel view for app health, upload storage, reverse proxy headers, app data counts, and optional dashboard URL reachability checks.
- `setup.sh --dry-run` and `setup.sh --update [ctid]` flows for safer install planning and existing-container updates.
- Test coverage for unauthenticated admin mutations, token-required uploads, token-authenticated PDF uploads, and code upload rejection.
- Admin guest management: register guests on behalf of visitors, view registration history separately from active sessions, remove history entries, purge inactive history, change guest room affiliation, clear linked devices, purge expired sessions, and check out guests.
- In-container `updateguest` command for routine git pull, dependency refresh, and service restart from the LXC console.
- Remote Proxmox install via `install.sh` (no git on host) and in-container `setup-container.sh` for manual LXC installs.
- Installer auto-detects Proxmox templates, prefers Debian 13, and falls back to Debian 12 (replacing hardcoded `12.0-1`).

### Changed
- Post-registration and return visits now land on `/welcome.html` instead of `/photo.html`.
- Guest greeting copy distinguishes first visits ("We're glad you're here") from recognized return devices ("Welcome back").
- Admin panel now uses browser HTTP Basic Auth only; removed duplicate HTML login form and sessionStorage credentials.
- Admin panel reorganized into tabs: Overview, Rooms & Portal, Guests, Photos & Storage, and Settings.
- `updateguest` now runs git and npm as the `guestportal` service user to avoid dubious ownership errors when invoked as root.
- Guest upload UI now documents that phone photos, videos, HEIC/HEIF images, and PDF letters are allowed while code, scripts, archives, and macro documents are blocked.
- Guest upload UI now shows per-file validation, upload progress, and inline success/error messages.
- Proxmox setup now defaults to an unprivileged app LXC, installs the app under `/opt/guest-portal`, and runs `guest-portal.service` as a dedicated `guestportal` user.
- NAS setup now supports existing mounted directories for host-managed NAS mounts and verifies upload paths as the runtime service user.
- Existing-install updates now prompt before code updates, app state ownership fixes, service rewrites, NAS upload path changes, and service restarts.
- Production dependencies updated to clear current `npm audit --omit=dev --audit-level=moderate` findings.
- `.gitignore` expanded to keep runtime uploads, local config, credentials, generated archives, certificates, and temporary files out of version control.
- Deployment status and admin panel now distinguish registration history from active guest sessions instead of showing a misleading "registered guests" total.

### Security
- Guest uploads are restricted by MIME type, file extension, file count, file size, and file signature checks.
- Rejected upload files are removed after validation failure.

### Fixed
- Guest registration now loads rooms from public `/guest/rooms` instead of `/admin-api/rooms`, so room lists work when reverse proxies protect admin API paths.
- Setup scripts now update `adminUser` and `adminHash` on reinstall when credentials are entered during setup, instead of preserving a stale default `admin` username from an existing `config.json`.
- Admin panel Overview and Settings tabs now show the configured HTTP Basic Auth username.
- Re-running `setup-container.sh` on an existing install now detects configured rooms and admin credentials, keeps them by default, and offers review/replace/reset options instead of requiring re-entry.
- Existing installs now show a recovery menu with rebuild, targeted admin/room/guest resets, permission repair, and code-only update options.
- `setup-container.sh` and `updateguest` now run git/npm as the `guestportal` user, bootstrap missing helper scripts from GitHub when needed, and refresh outdated `updateguest` commands before updating.
- `updateguest` now discards local changes to installer scripts before `git pull`, avoiding failures after curl bootstrap downloads into the repo checkout.
- Installer script cleanup before `git pull` now skips files not yet tracked in the current checkout and removes untracked bootstrap copies that would block the update.
- Rebuild install now preserves uploaded photos when requested, fixes app checkout ownership before `npm install`, and reports clone/install failures clearly.

---

## [v1.3.0] - Persistent Guest Sessions & Device Linking

### Added
- Persistent guest sessions with configurable checkout dates (1-30 days, default 7)
- Device linking system - guests can add multiple devices to their session
- Admin guest session management panel (view, extend stays, check out)
- Multiple guests per room support with separate tokens and upload folders
- Background image upload/management from admin panel
- First-run admin setup via web UI
- Local development setup script (`setup-local.sh`)
- Comprehensive test suite (`test-suite.sh`)

### Security
- XSS prevention with `escapeHtml()` function
- Path traversal protection with input sanitization
- Input validation on all user-facing endpoints
- One-time session codes (invalidated after use)

### Fixed
- Session revoke endpoint using correct request parameter
- Deployment documentation paths corrected

---

## [v1.2.0] - Frontend Enhancements & Security Hardening

### Added
- One-time use enforcement for session codes
- Admin-defined session expiration now respected in backend
- Health check endpoint `/health`
- Dark mode toggle with system preference detection
- Photo preview gallery in guest upload view
- Current upload directory display in Admin Panel
- Update-safe deployment detection in setup script

### Changed
- Improved guest session handling and cleanup
- Setup script preserves existing config and storage files

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
