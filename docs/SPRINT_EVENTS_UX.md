# Sprint: Events UX

**Status:** Planned — handoff complete; implementation not started.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Improve how hosts and guests work with **event-tagged photos** after PR #40. Add a dedicated **Events** area in the admin panel for full event lifecycle management, and let guests re-tag uploads from the gallery when permitted.

**Depends on:** [docs/SPRINT_GUEST_TYPES_HARDENING.md](SPRINT_GUEST_TYPES_HARDENING.md) — scoped `eventSlug` + filename upload paths should land first so rename/merge/delete can target the correct on-disk folders.

## Current behavior (after PR #40)

| Area | Current state |
|------|---------------|
| Event storage | `storage.json` → `events: [{ id, name, createdAt, createdBy }]`. |
| Event creation | Guests with `createEventNames` via `POST /guest/events`; admins implicitly create when registering a guest with a new event name or via upload flows. |
| Admin UI | No Events tab. Event names appear only in guest registration datalist (`adminEventSuggestions`) and upload metadata. |
| Admin API | No authenticated admin CRUD for events — only guest-scoped list/create. |
| On-disk layout | Uploads land under `{stayFolder}/{eventSlug}/` where `eventSlug` derives from the event name. |
| Gallery | Guests group photos by event; no re-tag flow to move a file between events. |

**Problems:**
- Hosts cannot review, clean up, rename, merge, or delete stale event names from the admin panel.
- Event list grows organically from guest uploads with no central management surface.
- Re-tagging a mis-assigned photo requires admin filesystem intervention.

## Target behavior (this sprint)

### 1. Admin Events tab

Add an **Events** tab to `admin.html` (same pattern as Guest Types and Guests).

**List view:**
- Table or card list of all events from `storage.json`.
- Columns: name, created date, created-by (`guest`, `admin`, or session id where useful).
- Optional: count of active sessions referencing the event name and/or upload folder references (stretch).

**Actions (admin-only):**
- **Create** — add a new event name to the shared list before any guest uses it.
- **Rename** — change display name; update `storage.json` and optionally rename matching upload subfolders (document behavior when folders exist on disk).
- **Merge** — combine two events into one (pick survivor name); update `storage.json` and move/rename files from merged event subfolders under each stay folder.
- **Delete** — remove event from list; define rule for orphaned upload subfolders (block delete if files exist, or warn and leave folders, or offer force-delete — pick one and document).

**Admin API (proposal):**

| Endpoint | Purpose |
|----------|---------|
| `GET /admin-api/events` | List all events with metadata. |
| `POST /admin-api/events` | Create event `{ name }`. |
| `PATCH /admin-api/events/:id` | Rename `{ name }` or merge `{ mergeIntoId }`. |
| `DELETE /admin-api/events/:id` | Delete event (per chosen orphan-folder rule). |

All routes behind existing admin Basic Auth. Reuse `findEventByName`, `sanitizeEventSlug`, and stay-folder helpers from `server.js`.

**UI notes:**
- Confirm destructive actions (delete, merge).
- After rename/merge, refresh guest registration datalists and any admin pickers that use event names.

### 2. Re-tag upload to a different event (guest gallery)

When the guest type allows `tagPhotosToEvent`:

- `photo.html` offers “Move to event…” (or similar) on each upload.
- Server moves file between event subfolders under the **same stay folder** using scoped paths from the hardening sprint.
- Target event must exist in the shared list or be creatable per guest permissions (`createEventNames`).

**API (proposal):** `PATCH /guest/uploads/:eventSlug/:filename` with `{ eventName }` or `{ eventId }`.

### 3. Tests and documentation

Add integration tests for admin event CRUD (create, rename, delete rejection when appropriate, merge). Update `test-suite.sh`, CHANGELOG, ROADMAP checklist, and AGENTS when implementation starts.

## Implementation order (recommended PRs)

1. **Admin event API + Events tab** — list, create, rename, delete; merge if not bundled with rename.
2. **Folder sync on rename/merge** — align disk subfolders with `storage.json` changes.
3. **Guest re-tag from gallery** — scoped move API + `photo.html` UI.
4. **Tests and docs** — `test-suite.sh`, CHANGELOG, ROADMAP, AGENTS.

## Key files

| Area | Files |
|------|-------|
| Event storage/helpers | `server.js` (`findEventByName`, `getOrCreateEvent`, `sanitizeEventSlug`, save/load) |
| Admin Events UI | `frontend/admin.html` |
| Guest gallery re-tag | `frontend/photo.html` |
| Tests | `test-suite.sh` |
| Docs | `ROADMAP.md`, `AGENTS.md`, `CHANGELOG.md` |

## Sprint checklist (mirror ROADMAP)

- [ ] Handoff doc and ROADMAP updates (planning)
- [ ] Admin Events tab — list all events with metadata
- [ ] Admin event create, rename, merge, and delete (UI + API)
- [ ] On-disk subfolder behavior documented and implemented for rename/merge/delete
- [ ] Guest gallery re-tag upload to a different event
- [ ] Tests and documentation updates
