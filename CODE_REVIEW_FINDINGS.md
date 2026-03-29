# Code Review Findings — Pre-Deployment

**Date:** 2026-03-29
**Reviewer:** Claude Code
**Branch:** claude/fix-shell-injection-security-r1eBJ
**Status:** All items resolved ✅

---

## 🔴 Critical — ✅ All Fixed

| # | Issue | Fix |
|---|-------|-----|
| C1 | Admin API endpoints lack auth middleware | Added `authMiddleware` to all 13 admin routes |
| C2 | Token generation uses `Math.random()` | Replaced with `crypto.randomBytes()` |
| C3 | Credentials stored in `localStorage` | Switched to `sessionStorage` |
| C4 | `fullToken` leaked in API response | Removed from `/admin-api/guest-sessions` |
| C5 | No process manager (nohup) | Added `guest-portal.service` systemd unit |
| C6 | Path traversal in background delete | Added `path.resolve` + `startsWith` validation |

## 🟠 High — ✅ All Fixed

| # | Issue | Fix |
|---|-------|-----|
| H1 | Rate limiter applied after static/routes | Moved limiter before `express.static` |
| H2 | Config loaded with `require()` (cached) | Switched to `JSON.parse(fs.readFileSync())` |
| H3 | multer 1.x has known CVEs | Upgraded to multer 2.1.1 |
| H4 | Upload endpoint has no auth | Requires guest name validation |
| H5 | No HTTPS in nginx config | Added TLS block + HSTS + security headers |
| H6 | `pct push` includes node_modules/.git | Replaced with tar-based copy with exclusions |

## 🟡 Medium — ✅ All Fixed

| # | Issue | Fix |
|---|-------|-----|
| M1 | Duplicate frontend files in root | Deleted root copies (`index.html`, etc.) |
| M2 | `loadGuests()` appends duplicate DOM | Uses static `#guestList` container, clears on each load |
| M3 | Session expiration endpoint is no-op | Now saves `config.sessionExpirationMinutes` |
| M4 | `uploadDir` config never used | Removed dead endpoint, replaced with `GET /admin-api/admin-timeout` |
| M5 | `parseInt` missing radix | Added radix `10` to all `parseInt` calls |
| M6 | `loadTimeout()` fetches wrong endpoint | Fixed to use `GET /admin-api/admin-timeout` |
| M7 | Version mismatch (1.2.1 vs 1.3.0) | Updated `package.json` to `1.3.0` |
| M8 | Test expects wrong response format | Updated to check for `token` + `guest` in JSON |

## 🟢 Low — ✅ All Fixed

| # | Issue | Fix |
|---|-------|-----|
| L1 | Background extension not validated vs MIME | Added `MIME_TO_EXT` map, extension derived from MIME type |
| L2 | `admin.js` CLI utility orphaned | Deleted |
| L3 | `INTEGRITY_MANIFEST` stale | Deleted |
| L4 | No graceful shutdown handler | Added `SIGTERM`/`SIGINT` handlers with 5s timeout |
| L5 | Synchronous file I/O blocks event loop | Replaced `writeFileSync` with `fs.promises.writeFile` |
| L6 | `set -e` in test-suite.sh | Removed to allow all tests to run |

## Additional Fixes

| Issue | Fix |
|-------|-----|
| Shell injection in setup scripts | Password/config passed via env vars + base64 |
| Admin fetch calls missing auth headers | All admin API calls in `admin.html` now include `Authorization` header |
| Setup script has no NPM option | Added 3-way proxy choice: NPM / new NGINX / manual |
| Setup script doesn't auto-detect backend IP | Auto-detects via `hostname -I`, displays in summary |
| NGINX config has placeholder IP | Option 2 now auto-substitutes real IP via `sed` |
