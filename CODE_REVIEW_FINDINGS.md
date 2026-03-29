# Code Review Findings — Pre-Deployment

**Date:** 2026-03-29
**Reviewer:** Claude Code
**Branch:** claude/fix-shell-injection-security-r1eBJ

---

## 🔴 Critical (must fix before deploying)

### C1. Admin API endpoints lack auth middleware
**File:** `server.js:377-412, 439-462, 467-509`
`authMiddleware` exists (line 173) but is only applied to `/admin/uploads` (line 405). All `/admin-api/*` mutating routes and sensitive GETs are completely unprotected:
- `POST /admin-api/rooms` — anyone can add/modify rooms
- `DELETE /admin-api/rooms/:name` — anyone can delete rooms
- `POST /admin-api/background` — anyone can upload images
- `DELETE /admin-api/background` — anyone can remove background
- `POST /admin-api/admin-timeout` — anyone can change admin timeout
- `POST /admin-api/uploadDir` — anyone can change upload path
- `POST /admin-api/session-expiration` — open (also a no-op, see M3)
- `GET /admin-api/sessions` — exposes all active session codes publicly
- `GET /admin-api/guest-sessions` — exposes all guest data publicly
- `POST /admin-api/guest-sessions/:id/extend` — anyone can extend stays
- `DELETE /admin-api/guest-sessions/:id` — anyone can check out guests
- `GET /api/guests` — exposes all guest PII with no auth

### C2. Guest token generation is cryptographically weak
**File:** `server.js:143-145`
`Math.random()` is not cryptographically secure. Tokens are predictable (~26 bits of entropy). Use `crypto.randomBytes(32).toString('hex')`.

### C3. Credentials stored in localStorage
**File:** `frontend/admin.html:161-163`
Base64-encoded Basic Auth credentials persist in localStorage indefinitely, accessible to any script on the page. Should use `sessionStorage` at minimum.

### C4. Full guest tokens exposed in admin API response
**File:** `server.js:328`
`fullToken: token` is included in the `/admin-api/guest-sessions` response, making the truncated display meaningless. Remove it.

### C5. No process manager — server won't survive crashes or reboots
**File:** `setup.sh:121`
`nohup node server.js &` won't restart on crash, OOM, or container reboot. Need a systemd service file.

### C6. Background image delete has path traversal risk
**File:** `server.js:454`
`path.join(__dirname, config.backgroundImage)` — if `config.backgroundImage` is tampered with in config.json, this resolves outside the project directory.

---

## 🟠 High (strongly recommended before production)

### H1. Rate limiter applied after static middleware and early routes
**File:** `server.js:49, 151`
`express.static('frontend')` at line 49 and routes at lines 52-110 are all defined before the rate limiter at line 151. Static files and setup/login/health routes bypass rate limiting entirely.

### H2. Config loaded with `require()` — cached by Node
**File:** `server.js:124`
`require(configPath)` caches the module. Should use `JSON.parse(fs.readFileSync(...))` for consistency.

### H3. multer 1.x has known vulnerabilities
**File:** `package.json`
`"multer": "^1.4.5-lts.1"` — npm advisory says multer 1.x has multiple vulnerabilities patched in 2.x.

### H4. File upload endpoint has no auth
**File:** `server.js:188`
`POST /upload` accepts 10 files per request with no authentication or guest token validation.

### H5. No HTTPS in nginx config
**File:** `nginx/guestportal.conf`
Only HTTP on port 80. Session tokens and admin credentials travel in plaintext.

### H6. `setup.sh` pushes entire project directory including node_modules
**File:** `setup.sh:89`
`pct push "$(pwd)" /root/guest-portal -r` includes node_modules/, .git/, and any local .env or config.json.

---

## 🟡 Medium (should fix)

### M1. Duplicate frontend files
`index.html`, `admin.html`, `photo.html`, `styles.css` exist identically in both `/` and `/frontend/`. Server serves from `frontend/`. Root copies are dead weight that will drift.

### M2. `loadGuests()` appends duplicate DOM sections
**File:** `frontend/admin.html:297-312`
Each call appends a new "Registered Guests" div instead of replacing.

### M3. Session expiration endpoint is a no-op
**File:** `server.js:491-493`
Returns 200 but never saves the value. Admin UI shows a working form that silently does nothing.

### M4. `uploadDir` config is never used
**File:** `server.js:407-412`
Endpoint saves `config.uploadDir` but multer destinations are hardcoded.

### M5. `stayDays` NaN handling / missing radix
**File:** `server.js:197`
`parseInt(stayDays)` — missing radix parameter. Edge case with `"0"` handled accidentally.

### M6. `loadTimeout()` fetches wrong endpoint
**File:** `frontend/admin.html:273-278`
Fetches `GET /admin-api/uploadDir` (POST-only) to load timeout. Always fails silently.

### M7. Version mismatch
`package.json` says `1.2.1`, README/CHANGELOG say `v1.3.0`.

### M8. `test_register_valid` expects wrong response
**File:** `test-suite.sh:73-77`
Test expects `"OK"` but `POST /register` returns JSON `{ token, guest }`.

---

## 🟢 Low / Style

### L1. Background image extension not validated against MIME type
**File:** `server.js:422`

### L2. `admin.js` CLI utility is orphaned
Never referenced, not useful for deployment.

### L3. INTEGRITY_MANIFEST is stale
References v1.0.1 file sizes and hashes. Everything has changed.

### L4. No graceful shutdown handler
No `SIGTERM`/`SIGINT` handling for clean exit.

### L5. Synchronous file I/O on every mutation
All `writeFileSync` calls block the event loop under concurrent requests.

### L6. `set -e` in test-suite.sh causes early exit on failure
Test assertions can trigger exit before all tests run.
