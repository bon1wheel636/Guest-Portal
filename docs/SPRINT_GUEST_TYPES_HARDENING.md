# Sprint: Guest types hardening and test coverage

**Status:** Planned — handoff complete; implementation not started.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Harden the guest types, permissions, and event-scoped upload features shipped in PR #40. Fix edge cases found in post-merge review, close remaining test gaps from [docs/SPRINT_DAY_VISITORS.md](SPRINT_DAY_VISITORS.md), and make permission resolution safer when guest type definitions change or disappear.

## Current behavior (after PR #40)

| Area | Current state |
|------|---------------|
| Guest upload APIs | `GET/DELETE /guest/uploads/:filename` resolve files by **filename only** across all event subfolders under a stay folder. |
| Duplicate names | Multer names files `{timestamp}-{original}`; collisions across `General/` and event folders are unlikely but possible if timestamps match or files are copied in manually. When duplicated, download/delete may hit the **wrong file** (first match wins). |
| Missing guest type | `resolveGuestType()` falls back to `type_overnight` with **full legacy permissions** when `guestTypeId` is absent from storage or the type was removed from `guestTypes`. A previously restricted guest could gain upload/Smart Home access. |
| Permission source | Effective permissions are always read **live** from the current guest type definition in `storage.json`. Admin edits to a type immediately affect all active sessions on that type (intentional), but missing types over-correct upward. |
| Integration tests | Core permission 403s and guest type CRUD are covered. **Not yet tested:** event subfolder uploads, legacy sessions without `guestTypeId`, day-personal registration with event, `deleteOwnPhotos: false`. |
| Admin type change | Changing session type to `day` resets checkout from now + `defaultDayVisitHours`. Switching `day` → `overnight` does not recalculate checkout (minor inconsistency). |

**Problems:**
- Gallery download/delete can target the wrong file when the same basename exists in multiple event folders.
- Deleted or corrupted guest type ids grant overly permissive fallback instead of a safe minimum.
- Test suite does not prove event folder layout or several permission paths documented in the day-visitors sprint.

## Target behavior (this sprint)

### 1. Event-scoped file identity (duplicate filename fix)

Guest upload list, download, and delete must address files **uniquely within a stay**, including event subfolder.

**API shape (recommended):**

| Endpoint | Purpose |
|----------|---------|
| `GET /guest/uploads` | Returns `{ files: [{ name, event, eventSlug, size, uploadedAt }] }` — include stable `eventSlug` used on disk. |
| `GET /guest/uploads/:eventSlug/:filename` | Download/preview a file in a specific event folder. |
| `DELETE /guest/uploads/:eventSlug/:filename` | Delete a file in a specific event folder. |

**Legacy compatibility:**
- Keep `GET/DELETE /guest/uploads/:filename` for one release cycle: resolve only **flat** files at stay-folder root (`General` legacy layout). Return **409 or 400** if multiple matches exist in subfolders (force client to use scoped path).
- `photo.html` passes `eventSlug` from list response when downloading/deleting.

**Server helpers:**
- Refactor `findGuestUploadFile(guestId, filename)` → `findGuestUploadFile(guestId, filename, eventSlug)` where `eventSlug` defaults to scanning flat files only for legacy route.
- `listGuestUploadFiles` already returns `event`; add `eventSlug` matching folder names on disk.

**Admin uploads listing:** unchanged or add `event` column in file metadata if not already shown (admin paths already walk subfolders).

### 2. Safe permission fallback when guest type is missing

When a session's `guestTypeId` cannot be loaded from `storage.json`:

| Case | Behavior |
|------|----------|
| No `guestTypeId` on session (legacy) | Continue mapping to `type_overnight` defaults (unchanged). |
| `guestTypeId` set but type missing/disabled | Use **restricted fallback** — not full overnight permissions. |

**Restricted fallback permissions (proposal):**

```json
{
  "uploadPhotos": false,
  "deleteOwnPhotos": false,
  "viewPhotoGallery": false,
  "smartHomeControls": false,
  "linkDevice": false,
  "extendStay": false,
  "selectStayLength": false,
  "selectEventAtRegistration": false,
  "tagPhotosToEvent": false,
  "createEventNames": false,
  "viewWelcomeHub": true,
  "signOut": true
}
```

**Optional hardening (pick one and document):**

- **A. Session permission snapshot (preferred):** On registration and when admin changes `guestTypeId`, copy `permissions` onto the session object in `guest-tokens.json`. `getGuestPermissions()` uses snapshot when type is missing; otherwise live type (admin edits still apply when type exists).
- **B. Snapshot always:** Permissions frozen at registration — admin type edits do not affect active sessions (behavior change; only choose if product wants immutable stays).

**Recommendation:** **A** — snapshot on write, live resolve when type exists. Matches “changing type in admin updates effective permissions” while preventing privilege escalation when a type is deleted.

**UI:** `/guest/validate` includes `guestTypeName: "Unknown (restricted)"` or similar when fallback applies.

### 3. Remaining integration tests

Add to `test-suite.sh`:

| Test | Assert |
|------|--------|
| Event subfolder upload | Register with type allowing `tagPhotosToEvent`, upload with `eventName`, verify file path under `{stayFolder}/{eventSlug}/` via admin listing or filesystem. |
| Legacy session | Token in `guest-tokens.json` without `guestTypeId` uploads successfully; `/guest/validate` returns overnight-equivalent permissions. |
| Day personal registration | Register with `type_day_personal` + `eventName`; session has `eventName`; checkout ~8h out. |
| Delete forbidden | Register `type_day_business` (or patch session), `DELETE /guest/uploads/...` → 403. |
| Scoped delete (after API change) | Two files same basename in different event folders — delete one via scoped path leaves the other. |

Keep existing 59 tests green.

### 4. Admin session type change polish (small)

When admin `PATCH`es `guestTypeId`:

- **To day:** keep current behavior (reset checkout from now + hours).
- **To overnight:** optionally extend checkout to at least `now + defaultStayDays` if current checkout is sooner (avoid stranding a promoted guest with minutes left).

Document chosen rule in README or sprint doc; implement if low effort.

## Implementation order (recommended PRs)

1. **Handoff + ROADMAP/AGENTS** — this doc; move follow-up items from backlog to in-progress sprint.
2. **Scoped upload paths** — server route + helper refactor; update `photo.html` to use `eventSlug`.
3. **Permission snapshot + safe fallback** — write snapshot on registration/type change; update `resolveGuestType` / `getGuestPermissions`.
4. **Integration tests** — add five tests above; fix any regressions.
5. **Docs** — CHANGELOG, ROADMAP checklist, optional README note on upload URL shape.

**Defer (stay in backlog):**
- Event calendar integration.
- Re-tag upload to different event from gallery.
- Admin merge/rename events.
- UniFi external portal, dark mode.

**Optional stretch:**
- Deprecation header or log warning on unscoped `/:filename` routes.
- Admin Photos UI: show event subfolder in file cards.

## Key files

| Area | Files |
|------|-------|
| Upload path resolution | `server.js` (`listGuestUploadFiles`, `findGuestUploadFile`, guest upload routes) |
| Permission resolver | `server.js` (`resolveGuestType`, `getGuestPermissions`, `createGuestRegistration`, session PATCH) |
| Guest gallery | `frontend/photo.html` |
| Tests | `test-suite.sh` |
| Docs | `ROADMAP.md`, `AGENTS.md`, `CHANGELOG.md` |

## Server notes

- Sessions live in `/etc/guest-portal/guest-tokens.json`; guest types in `storage.json`.
- Path validation: `eventSlug` must pass same sanitization as upload destination (`sanitizeEventSlug` / `sanitizeName`).
- Do not expose other guests' files — all lookups scoped by `guestId` stay folders (unchanged).
- If adding snapshot field, use `permissionsSnapshot` on session object; omit from public registration responses unless needed (validate already returns effective permissions).

## Testing expectations

Automated:

```bash
ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

All existing tests plus new cases listed in §3.

Manual:

- Upload two different photos to two events; delete one from gallery; confirm the other remains.
- Disable/delete a custom guest type in storage (or admin disable + remove id manually in dev); confirm active session loses upload/Smart Home but can still sign out.
- Register day personal with event; confirm admin Photos shows event subfolder.

## Dev environment

```bash
sudo mkdir -p /etc/guest-portal && sudo chown -R "$USER":"$USER" /etc/guest-portal
cp config.template.json /etc/guest-portal/config.json
cp storage.template.json /etc/guest-portal/storage.json
echo '{}' > /etc/guest-portal/sessions.json
echo '{}' > /etc/guest-portal/guest-tokens.json

npm install && npm start
```

## Deployment (production container)

```bash
updateguest -y
```

Verify scoped gallery delete, restricted fallback (spot-check in admin after disabling a type), and `bash test-suite.sh` against production with admin creds if feasible.

## Recent context

- Guest types sprint merged in **PR #40** ([docs/SPRINT_DAY_VISITORS.md](SPRINT_DAY_VISITORS.md)).
- Post-merge review identified duplicate filename risk, missing-type privilege escalation, and four missing integration tests.
- ROADMAP tracks these under “Follow-ups from day visitors sprint (PR #40 review)” until this sprint starts.

## Sprint checklist (mirror ROADMAP)

- [ ] Handoff doc and ROADMAP/AGENTS updates (planning)
- [ ] Event-scoped guest upload download/delete paths (`eventSlug` + filename)
- [ ] Guest gallery uses scoped paths; legacy flat-file route documented
- [ ] Permission snapshot on session write; safe fallback when type missing
- [ ] Remaining integration tests (event folder, legacy session, day personal, delete 403, scoped delete)
- [ ] Admin type change checkout polish (day ↔ overnight)
- [ ] Tests and documentation updates
