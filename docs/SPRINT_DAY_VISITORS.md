# Sprint: Day visitors, events, and entry landing

**Status:** Planned — not started.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Extend the guest portal beyond overnight stays: support **day visitors** with distinct visitor types and upload rules, let hosts and guests organize photos by **event name**, align upload storage folders with those events, and improve the **unregistered entry landing** (`/`, `index.html`) with a background-image hero and a clear registration call-to-action.

## Current behavior (before sprint)

| Area | Current state |
|------|---------------|
| Visitor model | One registration path: overnight guests with `stayDays` (1–30) and a checkout date. No day-visitor or visitor-type concept. |
| Registration UI | `/` (`index.html`) shows the full registration form immediately (name, room, stay length) plus device link code entry. |
| Background image | Admin can upload a background; guest pages apply it as a full-page CSS background on `index.html`, `welcome.html`, and `photo.html`. The registration form still dominates the entry page. |
| Upload permissions | Any guest with a valid token can upload. No per-visitor-type restrictions. |
| Upload folders | Multer creates `{sanitized-name}-{guestId}-{YYYY-MM-DD}/` under the uploads directory. All files for a stay land in that single folder. |
| Event organization | No event names, tags, or grouping. Gallery lists all files for the guest folder flat. |
| Admin guest tools | Admin can register overnight guests, change room, clear devices, extend stay, check out, export CSV, and generate link codes. No visitor type or event management. |

**Problems:**
- Friends and family visiting for a few hours use the same overnight flow as house guests.
- Business or service visits should not offer photo upload, but there is no way to distinguish them.
- Party, graduation, and reunion photos from multiple stays mix together in one folder per guest ID.
- Hosts cannot browse uploads by event in admin storage or ask guests to tag photos to an occasion.
- When a background image is configured, the entry page does not feel like a welcoming landing — the form appears first instead of the photo.

## Target behavior (this sprint)

### Day visitor registration and types

- Add a **visit mode** distinction:
  - **Overnight guest** — existing flow (room, stay days, checkout date).
  - **Day visitor** — same-day visit; shorter session lifetime (default: expires at end of local calendar day or a configurable number of hours — pick one approach during implementation and document it).
- Add **visitor category** (minimum two values):
  - **Personal** — friends, family, social visits. **May upload photos.**
  - **Other** — business, sales, service, contractors, etc. **May not upload photos.**
- Day visitor registration collects: name, visitor category, and **event name** (see below). Room may be optional or use a host-defined "Day visit" pseudo-room — decide during implementation; document the choice.
- Overnight guests keep room + stay days; they do not pick visitor category at registration (treat as overnight/personal for upload purposes unless admin overrides).
- **Admin tools:**
  - Register day visitors from the admin Guests tab.
  - Change visitor category for an active day visitor.
  - Filter or label day visitors vs overnight guests in session lists and CSV exports.
- **Upload enforcement:** server rejects `POST /upload` when the session is a non-personal day visitor (403 with a clear message). Hide or disable upload UI on `welcome.html` / `photo.html` for those sessions.

### Event names and photo grouping

- Introduce an **event name** (free text, sanitized), e.g. "Birthday Party", "Graduation", "Retirement".
- **Day visitors:** pick from existing events or enter a new event name during registration.
- **Overnight guests:** choose or create an event when uploading from the welcome hub; optionally re-tag from the gallery later (stretch — at minimum tag at upload time).
- **Event list:** stored in app state (e.g. `storage.json` → `events: [{ id, name, createdAt, createdBy }]`) . Admin and guests can add new event names; dedupe by normalized name.
- **Gallery grouping:** `photo.html` groups files by event subfolder. Show an "Uncategorized" or "General" group for legacy files without an event path.
- **Upload folder structure** (new uploads):

  ```
  uploads/
    {name}-{guestId}-{date}/           # stay/visit root (existing pattern)
      General/                         # optional default when no event selected
      Birthday-Party/                  # sanitized event slug
      Graduation/
  ```

  - Use a shared `sanitizeName()`-style helper for event slug segments.
  - Keep path validation: resolved paths must stay under the guest's stay folder and uploads root.
  - Existing flat files remain readable; do not break admin folder download/delete.

### Background hero landing page

- **Scope:** unregistered visitors hitting `/` (`index.html`). Registered guests with a stored token still redirect to `welcome.html` as today.
- **When a background image is configured:**
  - Show a **hero view**: background image full viewport, minimal chrome.
  - Place a **Register** button centered **mid-to-low** on the screen (comfortable thumb reach on phones).
  - Button opens registration — modal, slide-up panel, or in-page reveal of the existing form (pick the simplest responsive approach).
  - Keep **device link code** entry accessible (secondary link or compact section on the hero).
- **When no background is configured:** keep today's form-first layout (no regression).
- Do not change post-registration `welcome.html` behavior in this slice except where upload/event features apply.

## Proposed data model (starting point)

Extend `guestTokens[token]` entries:

```json
{
  "id": "guest_…",
  "name": "Alex",
  "room": "Guest Room",
  "visitMode": "overnight",
  "visitorCategory": "personal",
  "eventName": "Birthday Party",
  "checkoutDate": "…",
  "createdAt": "…",
  "devices": []
}
```

Day visitor example:

```json
{
  "visitMode": "day",
  "visitorCategory": "other",
  "eventName": "HVAC service call",
  "checkoutDate": "…same-day expiry…"
}
```

Extend `storage.json`:

```json
{
  "rooms": [],
  "guests": [],
  "events": [
    { "id": "evt_…", "name": "Birthday Party", "createdAt": "…", "createdBy": "admin" }
  ]
}
```

**Implementation note:** exact field names can differ, but `visitMode`, `visitorCategory`, and `eventName` (or `eventId`) must be available to upload middleware, admin APIs, and guest pages.

## Implementation order (recommended PRs)

1. **Handoff + structure** — this doc, ROADMAP/AGENTS updates.
2. **Event list + folder helpers** — `storage.json` events array, sanitize event slug helper, multer destination uses `{stayFolder}/{eventSlug}/`, migration-safe listing for flat legacy files.
3. **Day visitor registration (server + index)** — `visitMode`, `visitorCategory`, day session TTL, registration UI split overnight vs day visitor, event picker on day flow.
4. **Upload permission by category** — server guard on `POST /upload`, guest API flags so UI hides upload for `other` day visitors.
5. **Overnight event tagging** — event picker on welcome hub upload form; pass event to upload; gallery groups by subfolder.
6. **Admin day visitor tools** — register day visitor, change visitor category, show visit mode/type in Guests tab and CSV columns.
7. **Hero landing page** — conditional hero on `index.html` when `/guest/background` returns an image; Register CTA + preserved link-code entry.
8. **Tests + docs** — `test-suite.sh`, README, CHANGELOG, ROADMAP checklist.

**Defer (explicitly out of scope for this sprint):**
- Family/household calendar sync for suggested events.
- UniFi external portal integration.
- Dark mode and other admin QoL items.

**Optional stretch (only if ahead of schedule):**
- Re-tag existing upload to a different event from the gallery.
- Admin UI to rename or merge event names.

## Key files

| Area | Files |
|------|-------|
| Guest entry / hero | `frontend/index.html`, `frontend/styles.css` |
| Guest hub / gallery | `frontend/welcome.html`, `frontend/photo.html` |
| Admin UI | `frontend/admin.html` |
| Server / APIs | `server.js` |
| State templates | `storage.template.json`, `config.template.json` (if day-visit TTL is configurable) |
| Tests | `test-suite.sh` |
| Docs | `README.md`, `DEPLOY.md`, `AGENTS.md`, `CHANGELOG.md`, `ROADMAP.md` |

## Server notes

- Guest tokens live in `/etc/guest-portal/guest-tokens.json`; rooms/guests/events in `storage.json`.
- Upload middleware (`validateGuestUploadToken`, multer `destination`) must read `visitMode`, `visitorCategory`, and event from the guest session.
- Public guest pages use `/guest/*`; do not require guest browsers to call `/admin-api/*`.
- New guest-facing endpoints likely needed, e.g.:
  - `GET /guest/events` — list event names for pickers (public or token-scoped).
  - `POST /guest/events` — guest adds a new event name (rate-limited, sanitized).
  - Extend `/guest/validate` and registration responses with `visitMode`, `visitorCategory`, `canUpload`, and `eventName`.
- Admin endpoints likely needed, e.g.:
  - CRUD or append-only for events.
  - `POST /admin-api/guest-sessions` variant or flag for day visitor registration.
  - `PATCH` visitor category on active session.
- Path traversal rules apply to event slug segments the same as filenames.

## Testing expectations

Automated (`bash test-suite.sh`):
- Day visitor registration returns token with `visitMode: "day"`.
- Personal day visitor can upload; other day visitor receives 403 on upload.
- Upload lands under `{stayFolder}/{eventSlug}/` when event is provided.
- Overnight guest upload with event tag uses event subfolder.
- Guest gallery/list API returns event grouping or path metadata.
- `GET /guest/events` returns known events.
- Admin can change visitor category; upload permission updates accordingly.
- Hero landing: when background is set, `index.html` contains hero markup (static HTML test or script syntax check); when unset, form-first layout unchanged.
- Frontend inline script syntax check still passes for all guest pages.

Admin mutations:
```bash
ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

Manual (browser):
- Register as personal day visitor → upload allowed → files appear under event subfolder in admin Photos.
- Register as other day visitor → no upload UI / upload rejected.
- Register overnight guest → tag upload to event → gallery groups correctly.
- Set admin background → `/` shows hero + Register button → complete registration flow.
- Device link code still works from hero landing.

## Dev environment

```bash
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
- `/` hero (if background configured) and overnight/day registration paths
- `/welcome.html` upload rules by visitor type
- `/photo.html` event grouping
- Admin Guests tab: day visitor registration, visitor type change, event-aware photo folders

## Recent context

- Admin operations sprint completed: guest entry health, photo previews, CSV export, QR/link handoff, portal URL setting, configurable link-code expiration.
- Guest UX sprint completed: `welcome.html` hub, tutorial, gallery, guest-scoped upload APIs.
- Upload folders today use `{name}-{guestId}-{date}` with no event subfolders — plan for backward compatibility with existing flat files.
- Entry landing is `/` (`index.html`), not `welcome.html`; registered guests use `welcome.html`.

## Sprint checklist (mirror ROADMAP)

- [ ] Handoff doc and ROADMAP/AGENTS updates
- [ ] Event list storage and event-scoped upload folder paths
- [ ] Day visitor registration and session model
- [ ] Upload permission enforcement by visitor category
- [ ] Event picker for day visitors and overnight upload tagging
- [ ] Guest gallery grouping by event
- [ ] Admin day visitor registration and visitor type controls
- [ ] Background hero landing on `/` when background image is set
- [ ] Tests and documentation updates
