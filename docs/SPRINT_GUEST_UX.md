# Sprint: Guest convenience and integration (UX)

**Status:** Complete.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Improve the guest-facing experience after registration: correct welcome messaging, a clearer main hub page, easier photo uploads, and a guest photo gallery with mistake recovery.

## Current behavior (before sprint)

| Route | File | Purpose today |
|-------|------|----------------|
| `/` | `frontend/index.html` | Register or link device via code |
| `/photo.html` | `frontend/photo.html` | **Post-registration landing** — shows "Welcome back!", upload form, Smart Home link, device linking |
| `/admin.html` | `frontend/admin.html` | Admin panel (HTTP Basic Auth) |

**Problems:**
- `photo.html` is a poor name for the main guest hub.
- "Welcome back!" shows immediately after first registration (`photo.html` line 11 / JS greeting).
- Upload, Smart Home, and device linking are one long page with upload prominence.
- No guest-facing view of uploaded files; no guest delete of a single mistaken upload.
- Guest delete/list APIs do not exist (admin only: `/admin-api/uploads/*`).

**Registration redirect:** `index.html` sends guests to `photo.html` after register, link-device, or valid stored token (5 places).

## Target behavior (this sprint)

| Route | File | Purpose after sprint |
|-------|------|---------------------|
| `/` | `index.html` | Unchanged entry |
| `/welcome.html` | **new** | Main guest hub after registration/return |
| `/photo.html` | repurposed | **My Photos** gallery for current stay |
| `/admin.html` | admin.html | Unchanged |

### `welcome.html` hub
- First page after registration and on return during stay.
- Sections on one page: **greeting**, **first-stay tutorial** (when applicable), **Smart Home**, **device linking**, **upload** (inline section — not the whole page identity).
- Nav: tabs or clear links — **Welcome** | **My Photos** (`photo.html`).

### Greeting rules
- **Not** "Welcome back" immediately after first registration.
- **"We're glad you're here"** (or similar) for: new registration, unrecognized device, uncertain match.
- **"Welcome back"** only when device is recognized **and** guest name matches active session (return visit during same stay).

**Implementation hint:** `guestTokens[token].devices` tracks devices (`userAgent`, `addedAt`). Registration adds the first device. Extend `/guest/validate` (and register response) with a flag such as `returningDevice` by matching `User-Agent` to a prior device entry **before** treating post-register redirect as a return. Client may also use `sessionStorage` flag `welcomeSeen` set after first hub load.

### First-stay tutorial
- Show once after first registration (same session / `sessionStorage` or server flag).
- Explain: Smart Home link, upload section, device linking, bookmark/home-screen tip.

### `photo.html` gallery
- List files in the guest's upload folder for their session (token-scoped).
- Allow **delete one file at a time** (guest token required; path validation under their folder only).
- Admin retains folder-level delete/download in admin panel.

## Implementation order (recommended PRs)

1. **Handoff + structure** — this doc, ROADMAP/AGENTS updates (done in handoff PR).
2. **`welcome.html` hub** — move hub content from `photo.html`; update `index.html` redirects; keep upload inline.
3. **Greeting + tutorial** — API flags + client copy/modal on `welcome.html`.
4. **Guest photo APIs** — `GET /guest/uploads`, `DELETE /guest/uploads/:filename` (token auth, folder scoped).
5. **`photo.html` gallery** — UI consuming guest APIs; link from welcome nav.
6. **Tests + docs** — `test-suite.sh`, README, DEPLOY, AGENTS, CHANGELOG.

**Defer:** UniFi external portal, admin QoL (QR, CSV, admin gallery) — separate later work per ROADMAP.

## Key files

| Area | Files |
|------|--------|
| Guest pages | `frontend/index.html`, `frontend/welcome.html` (new), `frontend/photo.html`, `frontend/styles.css` |
| Server | `server.js` — register, validate, upload, new guest upload list/delete routes |
| Tests | `test-suite.sh` |
| Docs | `README.md`, `DEPLOY.md`, `AGENTS.md`, `CHANGELOG.md`, `ROADMAP.md` |

## Server notes

- Uploads: `POST /upload` with guest token header/body (`validateGuestUploadToken`).
- Guest folders: `{sanitizedName}-{guestId}-{date}/` under `getUploadsDir()` (see multer storage in `server.js`).
- Admin upload routes: `/admin-api/uploads*` — do not expose admin paths to guests; add parallel guest-scoped routes.
- Config/state: `/etc/guest-portal/` (`config.json`, `storage.json`, `guest-tokens.json`, `sessions.json`).

## Dev environment

```bash
# Config (see AGENTS.md)
sudo mkdir -p /etc/guest-portal && sudo chown -R "$USER":"$USER" /etc/guest-portal
cp config.template.json /etc/guest-portal/config.json
cp storage.template.json /etc/guest-portal/storage.json
echo '{}' > /etc/guest-portal/sessions.json
echo '{}' > /etc/guest-portal/guest-tokens.json

npm install && npm start
# Tests: ADMIN_USER=admin ADMIN_PASS='...' bash test-suite.sh
```

## Deployment (production container)

After merge to `main`:

```bash
updateguest -y
```

No special migration; static frontend + server restart.

## Recent infra context (do not re-litigate in this sprint)

- Setup recovery menu: `setup-container.sh` options 1–8 (PRs #24–#28).
- `updateguest` runs git/npm as `guestportal`; bootstrap script handling fixed.
- Admin auth: HTTP Basic only; custom `adminUser` in `config.json`.

## Sprint checklist (mirror ROADMAP)

- [x] Returning guest recognition and welcome messaging
- [x] First-stay guest tutorial
- [x] Guest welcome hub (`welcome.html`) and photo gallery split
- [x] Guest-scoped list/delete upload APIs
- [x] Tests and documentation updates
