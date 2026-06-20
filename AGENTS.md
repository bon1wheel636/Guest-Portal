# Guest Portal

Self-hosted guest Wi-Fi landing portal: a single Node.js/Express server (`server.js`) that serves a static frontend (`frontend/`) and a JSON-based admin/guest API. There is one service only; no database (state is stored in JSON files).

See [README.md](README.md) for product features, deployment, and local development.

## Active sprint

**Guest UX sprint (in progress):** read [docs/SPRINT_GUEST_UX.md](docs/SPRINT_GUEST_UX.md) first in a new session. It contains current vs target guest flows, implementation order, key files, and checklist — so you do not need prior chat context.

Track high-level items in [ROADMAP.md](ROADMAP.md) under **In progress sprint: guest convenience and integration**.

## Cursor Cloud specific instructions

### Service & how to run
- Single service: `npm start` (runs `node server.js`) listening on `http://localhost:3000`. There is no separate dev/watch mode and no build step. After editing `server.js` you must restart the process for changes to take effect (no hot reload).
- Frontend pages: `/` (guest registration), `/welcome.html` (guest hub — **in progress**, replaces post-registration `photo.html` landing), `/photo.html` (becoming guest photo gallery), `/admin.html` (admin panel). Static files are edited live and just need a browser refresh.

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
