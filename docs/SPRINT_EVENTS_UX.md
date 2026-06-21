# Sprint: Events UX

**Status:** In progress — core admin/guest event flows shipped in PR #46; gallery re-tag and admin merge UI remain.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Improve how hosts and guests work with **event-tagged photos**. Hosts manage events in admin; guests pick events at registration and (when permitted) re-tag uploads from the gallery.

**Depends on:** [docs/SPRINT_GUEST_TYPES_HARDENING.md](SPRINT_GUEST_TYPES_HARDENING.md) — scoped `eventSlug` + filename paths (merged in PR #44).

## Responsive design (required)

All Events UX surfaces must work on **phones and desktops** (same breakpoints/patterns as existing guest and admin pages).

| Surface | Mobile | Desktop |
|---------|--------|---------|
| Admin Events tab | Card/stacked list; full-width actions; touch-friendly buttons | Table or wide card grid; inline actions |
| Guest gallery re-tag | Compact control per photo; native-friendly selects/dialogs | Same flows with hover-capable affordances where useful |
| Registration modal | Bottom-anchored dialog; full-width fields | Centered modal dialog |

## Current behavior (after PR #46)

| Area | Current state |
|------|---------------|
| Event storage | `storage.json` → `events: [{ id, name, createdAt, createdBy }]`. |
| Admin Events tab | **Shipped** — list, create, rename, delete in `admin.html`; `/admin-api/events`. |
| Rename on disk | **Shipped** — rename updates matching upload subfolders under stay folders. |
| Admin merge | **API only** — `PATCH /admin-api/events/:id` with `{ mergeIntoId }`; no admin UI yet. |
| Registration | **Shipped** — event `<select>` on guest and admin register forms; optional for overnight, required for day-personal. |
| Hero landing | **Shipped** — registration opens in modal overlay when background image is set. |
| Gallery | Groups by event; download/delete use scoped paths; **no re-tag** to move between events. |
| Tests | Admin event CRUD covered in `test-suite.sh`; no re-tag or merge UI tests yet. |

**Remaining problems:**
- Guests cannot fix a mis-tagged photo without admin filesystem help.
- Hosts cannot merge duplicate event names from the admin UI (API exists).

## Target behavior (remaining work)

### 1. Guest gallery re-tag

When the guest type allows `tagPhotosToEvent`:

- `photo.html` offers “Move to event…” (or similar) on each upload row.
- Server moves file between event subfolders under the **same stay folder** using scoped paths from the hardening sprint.
- Target event must exist in the shared list or be creatable per guest permissions (`createEventNames`).

**API:** `PATCH /guest/uploads/:eventSlug/:filename` with `{ eventName }` or `{ eventId }`.

**Server notes:**
- Validate target event; resolve slug with `sanitizeEventSlug`.
- Refuse cross-guest or cross-stay moves.
- Return updated `{ eventSlug, name, event }` in response for gallery refresh.

### 2. Admin event merge UI

- Events tab: **Merge** action on each event (pick survivor from list).
- Calls existing `PATCH /admin-api/events/:id` with `{ mergeIntoId }`.
- Confirm before merge; refresh list and registration pickers after success.

### 3. Tests and documentation

| Test | Assert |
|------|--------|
| Guest re-tag | Upload to event A, PATCH move to event B, list shows new `eventSlug`, file gone from A folder |
| Re-tag forbidden | Type without `tagPhotosToEvent` → 403 |
| Admin merge UI | Optional HTTP test via `mergeIntoId` if not covered |

Update `CHANGELOG.md`, ROADMAP checklist, and AGENTS when complete.

## Implementation order (recommended PRs)

1. **Guest re-tag API + `photo.html` UI** — PATCH handler, move file on disk, permission checks.
2. **Admin merge UI** — Events tab merge flow.
3. **Tests and docs** — `test-suite.sh`, CHANGELOG, ROADMAP, AGENTS.

**Already shipped (PR #45–#46):**
- Admin Events tab CRUD, registration event picker, hero registration modal, rename folder sync.

**Defer to [docs/SPRINT_ADMIN_QOL.md](SPRINT_ADMIN_QOL.md):**
- Admin dark mode.

## Key files

| Area | Files |
|------|-------|
| Event storage/helpers | `server.js` (`findEventByName`, `sanitizeEventSlug`, `mergeEventFoldersOnDisk`, guest upload routes) |
| Admin Events UI | `frontend/admin.html` |
| Guest gallery re-tag | `frontend/photo.html` |
| Tests | `test-suite.sh` |
| Docs | `ROADMAP.md`, `AGENTS.md`, `CHANGELOG.md` |

## Sprint checklist (mirror ROADMAP)

- [x] Handoff doc and ROADMAP updates (planning)
- [x] Admin Events tab — list, create, rename, delete
- [x] Registration event picker (guest + admin)
- [x] Hero registration modal overlay (responsive)
- [x] Rename updates on-disk event subfolders
- [ ] Guest gallery re-tag upload to a different event
- [ ] Admin event merge UI
- [ ] Integration tests for re-tag (and merge if not covered)
- [ ] Tests and documentation updates (sprint complete)
