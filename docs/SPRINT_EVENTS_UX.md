# Sprint: Events UX

**Status:** Complete.

Use this document for context on shipped event-tagged photo flows.

## Goal

Improve how hosts and guests work with **event-tagged photos**. Hosts manage events in admin; guests pick events at registration and (when permitted) re-tag uploads from the gallery.

**Depends on:** [docs/SPRINT_GUEST_TYPES_HARDENING.md](SPRINT_GUEST_TYPES_HARDENING.md) — scoped `eventSlug` + filename paths.

## Shipped behavior

| Area | Behavior |
|------|----------|
| Event storage | `storage.json` → `events: [{ id, name, createdAt, createdBy }]`. |
| Admin Events tab | List, create, rename, delete, **merge** in `admin.html`; `/admin-api/events`. |
| Rename on disk | Rename updates matching upload subfolders under stay folders. |
| Admin merge | Events tab merge dialog → `PATCH /admin-api/events/:id` with `{ mergeIntoId }`. |
| Registration | Event `<select>` on guest and admin register forms. |
| Hero landing | Registration opens in modal overlay when background image is set. |
| Gallery re-tag | `PATCH /guest/uploads/:eventSlug/:filename` + Move control on `photo.html` when `tagPhotosToEvent` is allowed. |
| Tests | Admin event CRUD, merge, guest re-tag, re-tag 403 in `test-suite.sh`. |

## Key files

| Area | Files |
|------|-------|
| Event storage/helpers | `server.js` |
| Admin Events UI | `frontend/admin.html` |
| Guest gallery re-tag | `frontend/photo.html` |
| Tests | `test-suite.sh` |

## Sprint checklist

- [x] Handoff doc and ROADMAP updates (planning)
- [x] Admin Events tab — list, create, rename, delete
- [x] Registration event picker (guest + admin)
- [x] Hero registration modal overlay (responsive)
- [x] Rename updates on-disk event subfolders
- [x] Guest gallery re-tag upload to a different event
- [x] Admin event merge UI
- [x] Integration tests for re-tag and merge
- [x] Tests and documentation updates (sprint complete)

## Next sprint

[ROADMAP.md](../ROADMAP.md) — **Admin quality-of-life** (dark mode toggle).
