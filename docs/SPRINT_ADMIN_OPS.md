# Sprint: Admin operations and confidence

**Status:** Planned.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Improve day-to-day host operations after the guest UX sprint: make the admin panel better for reviewing uploads and sharing device-link codes, add CSV exports for guest records, and strengthen smoke checks so broken guest entry flows are caught before guests encounter them.

## Current behavior (before sprint)

| Area | Current state |
|------|---------------|
| Guest entry checks | `test-suite.sh` checks endpoints and static pages, but production smoke checks are not surfaced in the admin UI. |
| Admin photo tools | Admin can list upload folders, download zip archives, and delete folders, but cannot preview files visually in the panel. |
| Guest/session records | Admin can view active sessions and registration history, but cannot export those records. |
| Device linking | Guests can generate text link codes from the welcome hub; admin can clear linked devices, but there is no QR code workflow. |
| Documentation | Guest UX sprint handoff exists; next sprint scope is only listed as backlog bullets. |

**Problems:**
- A guest registration regression can reach production even when admin pages still appear healthy.
- Hosts need to download zip files or inspect storage directly to preview guest uploads.
- Guest/session data cannot be handed off or archived as CSV without manual copying.
- Device link codes are easy to mistype on phones and tablets.
- Future agents need a clear sprint entry point now that the guest UX sprint is complete.

## Target behavior (this sprint)

### Production guest smoke checks
- Add a lightweight admin **Guest Entry Health** card or panel.
- Show status for:
  - `/health`
  - `/`
  - `/guest/rooms`
  - `/welcome.html`
  - `/photo.html`
  - guest room count
- Include a short pass/fail message that tells hosts whether guest registration should be usable.
- Extend `test-suite.sh` with checks that cover guest entry flow regressions, including frontend inline script syntax.
- Update deployment docs with a concise post-`updateguest -y` verification checklist.

### Admin-side guest photo preview/gallery
- Enhance the existing admin **Guest Photos** section with a visual preview.
- Preserve existing folder-level download/delete behavior.
- Show useful metadata: filename, size, folder/stay, and upload timestamp when available.
- Allow preview of safe browser-renderable images without exposing unauthenticated admin file paths.
- Keep full folder download/delete as admin-only operations.

### CSV exports
- Add CSV export for **active sessions**.
- Add CSV export for **registration history**.
- Include stable columns such as guest ID, name, room, created/registered timestamp, checkout date, device count, and active/expired status when applicable.
- Escape CSV values correctly instead of building ad hoc comma strings.
- Keep exports behind admin authentication.

### Device-link QR code
- Add QR display for generated device link codes where it helps the host or guest link another device.
- Prefer a small, dependency-free implementation if practical; if adding a dependency is warranted, use the package manager and the latest available version.
- QR code should encode the link code or a same-origin URL that can prefill/submit the link flow, depending on what is safest and simplest in the current UI.
- Preserve the existing text code for accessibility and fallback.

## Implementation order (recommended PRs)

1. **Handoff + structure** — this doc, ROADMAP/AGENTS updates.
2. **Guest entry health checks** — server/admin status data, admin panel UI, `test-suite.sh` smoke coverage, deployment checklist.
3. **Admin photo previews** — authenticated preview/list endpoints or reuse current admin upload data safely; add UI in **Guest Photos**.
4. **CSV export** — active sessions and registration history endpoints/buttons; CSV escaping and tests.
5. **Device-link QR** — QR display for link codes; maintain text fallback.
6. **Docs + release notes** — README, DEPLOY, PROXY if needed, CHANGELOG, ROADMAP checklist updates.

**Defer:** UniFi external portal integration until controller version, auth method, site ID, and authorization model are known.

**Optional/defer:** Dark mode toggle unless visual polish becomes higher priority than host workflow improvements.

## Key files

| Area | Files |
|------|-------|
| Admin UI | `frontend/admin.html`, `frontend/styles.css` |
| Guest entry smoke | `frontend/index.html`, `frontend/welcome.html`, `frontend/photo.html`, `server.js`, `test-suite.sh` |
| Admin APIs | `server.js` |
| Docs | `README.md`, `DEPLOY.md`, `PROXY.md`, `AGENTS.md`, `CHANGELOG.md`, `ROADMAP.md` |

## Server notes

- Admin routes use HTTP Basic Auth via `authMiddleware`.
- Public guest pages should use guest-safe endpoints under `/guest/*`; avoid requiring guest browsers to call `/admin-api/*`.
- Runtime state lives outside the repo under `/etc/guest-portal/`.
- Uploads are stored under `getUploadsDir()`; admin upload routes currently live under `/admin-api/uploads*` and `/admin/uploads`.
- If adding preview/download endpoints, validate paths under the configured upload directory and do not expose arbitrary filesystem paths.

## Testing expectations

Automated:
- Run `bash test-suite.sh` against a running local server.
- Add/maintain tests for:
  - guest entry smoke endpoints
  - inline frontend script syntax
  - authenticated CSV exports
  - upload preview/list behavior
  - QR/link-code behavior if implemented server-side
- Run admin mutation tests with credentials when touching authenticated admin mutations:
  ```bash
  ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
  ```

Manual:
- Because this sprint changes `frontend/admin.html`, manually test the admin UI in a browser.
- Record a short walkthrough showing:
  - Guest Entry Health status
  - admin upload preview/gallery
  - CSV export download
  - QR code/link-code flow

## Dev environment

```bash
# Config (see AGENTS.md)
sudo mkdir -p /etc/guest-portal && sudo chown -R "$USER":"$USER" /etc/guest-portal
cp config.template.json /etc/guest-portal/config.json
cp storage.template.json /etc/guest-portal/storage.json
echo '{}' > /etc/guest-portal/sessions.json
echo '{}' > /etc/guest-portal/guest-tokens.json

npm install && npm start
# Tests: ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

## Deployment (production container)

After merge to `main`:

```bash
updateguest -y
```

Then verify:
- `/health`
- `/`
- `/guest/rooms`
- `/welcome.html`
- `/photo.html`
- Admin **Guest Entry Health** panel

## Recent context

- Guest UX sprint completed the `welcome.html` hub, first-stay tutorial, guest gallery, and guest-scoped upload list/delete APIs.
- A follow-up fix may be needed/merged for the guest registration room dropdown if the inline registration script fails to parse; keep frontend script syntax checks in this sprint.
- UniFi external portal work is intentionally deferred.

## Sprint checklist (mirror ROADMAP)

- [ ] Guest entry health checks and production smoke checklist
- [ ] Admin photo preview/gallery
- [ ] CSV exports for active sessions and registration history
- [ ] Device-link QR code
- [ ] Tests and documentation updates
