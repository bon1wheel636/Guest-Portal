# Guest Portal

Self-hosted guest Wi-Fi landing portal: a single Node.js/Express server (`server.js`) that serves a static frontend (`frontend/`) and a JSON-based admin/guest API. There is one service only; no database (state is stored in JSON files).

See [README.md](README.md) for product features, deployment, and local development.

## Active sprint

**Admin quality-of-life (planned):** dark mode toggle for `admin.html` — read [docs/SPRINT_ADMIN_QOL.md](docs/SPRINT_ADMIN_QOL.md) at the start of a new session.

**Sprint queue (see [ROADMAP.md](ROADMAP.md)):** ~~hardening~~ → ~~Events UX~~ → [Admin QoL](docs/SPRINT_ADMIN_QOL.md) → UniFi external portal.

**Live UniFi and Home Assistant site (read this before the UniFi sprint):** [docs/LOCAL_SITE.md](docs/LOCAL_SITE.md). That file is gitignored. It has the UDM Pro and Home Assistant OS versions, the internal portal URL, the VLAN map, and the decisions already made with the owner.

Known decisions, also written up in [UNIFI.md](UNIFI.md) for Network 10.6 and Home Assistant Core 2026.10:

- First deployment is UniFi password or voucher admission, then the hotspot **Custom URL** to the internal Guest Portal. The external Integration API is a later phase.
- The portal, Home Assistant, and Nginx Proxy Manager are on the home LAN. Guests reach them only through the proxy on TCP 443 and 80. Home Assistant port 8123 stays closed to the guest VLAN.
- Guest dashboard links are a local proxy hostname, not Nabu Casa. Create that DNS record when the hostname is chosen. One hostname covers every room path.
- Do not mark household dashboards admin-only. Kiosk Mode uses `user_settings` for the guest display name only. Do not use `non_admin_settings`.

Still ask the owner only for items listed as unknown in the local site note: proxy and host IPs, the local Home Assistant hostname, the guest display name, the console URL, the Integration API site id, and the API key. Do not guess them. Do not copy the local site note into git.

Previous sprint (completed): [docs/SPRINT_EVENTS_UX.md](docs/SPRINT_EVENTS_UX.md) — admin Events tab, registration event picker, gallery re-tag, admin merge UI.

Earlier sprint (completed): [docs/SPRINT_GUEST_TYPES_HARDENING.md](docs/SPRINT_GUEST_TYPES_HARDENING.md) — scoped upload paths, permission snapshot/fallback, integration tests.

Track high-level items in [ROADMAP.md](ROADMAP.md) under **Sprint queue**.

## Cursor Cloud specific instructions

### Service & how to run
- Single service: `npm start` (runs `node server.js`) listening on `http://localhost:3000`. There is no separate dev/watch mode and no build step. After editing `server.js` you must restart the process for changes to take effect (no hot reload).
- Frontend pages: `/` (guest registration), `/welcome.html` (guest hub — uploads, text notes, device linking), `/photo.html` (guest photo gallery), `/admin.html` (admin panel). Static files are edited live and just need a browser refresh.
- Guest notes: `GET/PUT/DELETE /guest/note` (requires `X-Guest-Token` and `leaveGuestNote` permission); admin `GET/DELETE /admin-api/guest-notes`. Notes persist in `storage.json` under `guestNotes[]`.

### Config lives outside the repo (non-obvious)
- `server.js` reads/writes config from hardcoded paths under `/etc/guest-portal/`: `config.json`, `storage.json`, `sessions.json`, `guest-tokens.json`. These are NOT in the repo and are gitignored.
- This directory must exist and be writable by the process user, otherwise admin/guest changes silently fail to persist (writes are wrapped in `.catch` that only logs). If missing, recreate it:
  ```bash
  sudo mkdir -p /etc/guest-portal && sudo chown -R "$USER":"$USER" /etc/guest-portal
  cp config.template.json /etc/guest-portal/config.json
  cp storage.template.json /etc/guest-portal/storage.json
  echo '{}' > /etc/guest-portal/sessions.json
  echo '{}' > /etc/guest-portal/guest-tokens.json
  ```
- With the template `config.json` (placeholder `adminHash`), the app reports `setupRequired: true`. Create the admin account via the `/admin.html` first-run form, `POST /admin-api/setup`, or `bash setup-local.sh` (interactive).
- After setup, `/admin.html` and admin API routes use browser HTTP Basic Auth. The configured username is stored in `config.json` as `adminUser` (default `admin`).

### Lint / test / build
- No linter is configured. `npm test` is a no-op stub (`echo "No tests configured"`).
- `bash test-suite.sh` is an HTTP integration suite that runs against an already-running server on port 3000.
- Admin mutation tests require credentials:
  ```bash
  ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
  ```
- Without `ADMIN_PASS`, admin mutation tests are skipped (not failures). Unauthenticated admin rejection is still tested.
