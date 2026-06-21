# Sprint: Guest types, permissions, events, and entry landing

**Status:** Implemented.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Extend the guest portal beyond a single overnight-guest flow: let hosts define **configurable guest types** with **permission checkboxes** in the admin panel, support **day visitors** and **overnight guests** under those types, organize photos by **event name**, align upload storage with events, and improve the **unregistered entry landing** (`/`, `index.html`) with a background-image hero.

## Current behavior (before sprint)

| Area | Current state |
|------|---------------|
| Visitor model | One registration path: overnight guests with `stayDays` (1–30) and a checkout date. No guest-type or permission model. |
| Permissions | All active guests can upload, delete own uploads, use Smart Home links, link devices, and generate link codes. No per-type restrictions. |
| Registration UI | `/` (`index.html`) shows the full registration form immediately (name, room, stay length) plus device link code entry. |
| Background image | Admin can upload a background; guest pages apply it as a full-page CSS background. The registration form still dominates the entry page. |
| Upload folders | Multer creates `{sanitized-name}-{guestId}-{YYYY-MM-DD}/` under the uploads directory. All files for a stay land in that single folder. |
| Event organization | No event names, tags, or grouping. Gallery lists all files flat. |
| Admin guest tools | Admin can register overnight guests, change room, clear devices, extend stay, check out, export CSV, and generate link codes. No guest-type configuration. |

**Problems:**
- Friends, family, contractors, and overnight guests all share one capability set.
- Hosts cannot say "business visitors may Wi-Fi in but not upload photos or open Smart Home."
- Party and reunion photos mix in one folder with no event grouping.
- The entry page does not use the configured background as a welcoming landing.

## Target behavior (this sprint)

### Configurable guest types (admin)

Add a **Guest Types** section in the admin panel (Settings tab or its own sub-section). Hosts can **add, edit, reorder, and disable** guest types without code changes.

Each guest type defines:

| Field | Purpose |
|-------|---------|
| `id` | Stable identifier (e.g. `type_overnight`, `type_day_personal`) |
| `name` | Display label (e.g. "Overnight Guest", "Day Visitor — Personal") |
| `description` | Optional helper text shown at registration |
| `visitMode` | `overnight` or `day` — controls session shape and which permissions are applicable |
| `defaultStayDays` | For overnight types only (1–30; used as registration default) |
| `defaultDayVisitHours` | For day types only (session length in hours, or end-of-day — pick one and document) |
| `requiresRoom` | Whether room selection is shown/required at registration |
| `permissions` | Object of booleans (see below) |
| `enabled` | Whether the type appears in registration pickers |

**Permission checkboxes** (admin toggles per guest type):

| Permission key | Guest-facing effect | Typical overnight | Typical day personal | Typical day business |
|----------------|---------------------|-------------------|----------------------|----------------------|
| `uploadPhotos` | Show upload UI; allow `POST /upload` | ✓ | ✓ | ✗ |
| `deleteOwnPhotos` | Show delete in gallery; allow `DELETE /guest/uploads/:file` | ✓ | ✓ | ✗ |
| `viewPhotoGallery` | Show **My Photos** nav and gallery page | ✓ | ✓ | ✗ |
| `smartHomeControls` | Show Smart Home link on welcome hub (requires room/dashboard) | ✓ | optional | ✗ |
| `linkDevice` | Show device link code section; allow `POST /guest/link-code` and link-device flow | ✓ | ✓ | optional |
| `extendStay` | Guest can request/view extend UI (if built); admin extend still always available | ✗ | ✗ | ✗ |
| `selectStayLength` | Show stay-days input at registration | ✓ | ✗ | ✗ |
| `selectEventAtRegistration` | Show event picker during registration | optional | ✓ | optional |
| `tagPhotosToEvent` | Show event picker when uploading (overnight) | ✓ | ✓ | ✗ |
| `createEventNames` | Allow guest to add a new event name to the shared list | ✓ | ✓ | ✗ |
| `viewWelcomeHub` | Access `welcome.html` after registration (baseline; disable only for minimal kiosk types) | ✓ | ✓ | ✓ |
| `signOut` | Show sign-out control on welcome hub | ✓ | ✓ | ✓ |

**UI rules for permission checkboxes:**
- Gray out or hide permissions that do not apply to the selected `visitMode` (e.g. `selectStayLength` and `extendStay` only for `overnight`; `defaultDayVisitHours` only for `day`).
- Show a short hint under Smart Home: "Requires room assignment and a room dashboard URL."
- Seed **sensible defaults** on first run (see data model below); hosts can customize.

**Enforcement:**
- Server is the source of truth: every guest-scoped route checks the session's resolved guest type permissions.
- `/guest/validate`, registration responses, and session payloads include a `permissions` object (or individual `canUpload`, `canDeletePhotos`, etc.) so guest pages hide disabled sections without extra round trips.
- Changing a guest's type in admin updates their effective permissions immediately for new actions (existing uploads remain).

### Day visitors and overnight guests under guest types

- Registration (guest and admin) picks an **enabled guest type** instead of hard-coded "personal/other."
- **Overnight types** use room + stay days + checkout date (existing model, driven by type defaults).
- **Day types** use shorter TTL from `defaultDayVisitHours` (or end-of-day); room optional based on `requiresRoom`.
- Admin Guests tab: show guest type name, visit mode, and effective permissions summary; allow **changing guest type** on an active session.
- CSV exports include guest type id/name and visit mode columns.

### Event names and photo grouping

- **Event name** (free text, sanitized): "Birthday Party", "Graduation", "Retirement", etc.
- Types with `selectEventAtRegistration` prompt during registration; types with `tagPhotosToEvent` prompt at upload time.
- Types with `createEventNames` may add new events; otherwise pick from existing list only.
- **Event list** in `storage.json` → `events: [{ id, name, createdAt, createdBy }]`.
- **Gallery grouping** on `photo.html` by event subfolder; "General" for legacy flat files.
- **Upload folder structure:**

  ```
  uploads/
    {name}-{guestId}-{date}/
      General/
      Birthday-Party/
      Graduation/
  ```

- Path validation unchanged; legacy flat files remain readable.

### Background hero landing page

- **Scope:** unregistered visitors on `/` (`index.html`). Registered guests with a token still redirect to `welcome.html`.
- **When a background image is configured:** hero view (full viewport image, minimal chrome), **Register** button centered mid-to-low, device link code entry preserved as secondary action.
- **When no background:** keep today's form-first layout.
- Registration opened from hero respects guest type picker and permission-driven fields.

## Proposed data model (starting point)

### `storage.json` — guest types (new)

```json
{
  "rooms": [],
  "guests": [],
  "events": [],
  "guestTypes": [
    {
      "id": "type_overnight",
      "name": "Overnight Guest",
      "description": "Staying one or more nights",
      "visitMode": "overnight",
      "defaultStayDays": 7,
      "requiresRoom": true,
      "enabled": true,
      "permissions": {
        "uploadPhotos": true,
        "deleteOwnPhotos": true,
        "viewPhotoGallery": true,
        "smartHomeControls": true,
        "linkDevice": true,
        "extendStay": false,
        "selectStayLength": true,
        "selectEventAtRegistration": false,
        "tagPhotosToEvent": true,
        "createEventNames": true,
        "viewWelcomeHub": true,
        "signOut": true
      }
    },
    {
      "id": "type_day_personal",
      "name": "Day Visitor — Personal",
      "description": "Friends and family visiting for the day",
      "visitMode": "day",
      "defaultDayVisitHours": 8,
      "requiresRoom": false,
      "enabled": true,
      "permissions": {
        "uploadPhotos": true,
        "deleteOwnPhotos": true,
        "viewPhotoGallery": true,
        "smartHomeControls": false,
        "linkDevice": true,
        "extendStay": false,
        "selectStayLength": false,
        "selectEventAtRegistration": true,
        "tagPhotosToEvent": true,
        "createEventNames": true,
        "viewWelcomeHub": true,
        "signOut": true
      }
    },
    {
      "id": "type_day_business",
      "name": "Day Visitor — Business",
      "description": "Sales, service, or business appointments",
      "visitMode": "day",
      "defaultDayVisitHours": 4,
      "requiresRoom": false,
      "enabled": true,
      "permissions": {
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
    }
  ]
}
```

### `guestTokens[token]` — session (extended)

```json
{
  "id": "guest_…",
  "name": "Alex",
  "room": "Guest Room",
  "guestTypeId": "type_overnight",
  "visitMode": "overnight",
  "eventName": "Birthday Party",
  "checkoutDate": "…",
  "createdAt": "…",
  "devices": []
}
```

Resolve permissions at request time: load guest type from `storage.json` by `guestTypeId` (fallback to a safe default if type deleted/disabled).

**Migration:** existing sessions without `guestTypeId` map to `type_overnight` with full legacy permissions.

## Implementation order (recommended PRs)

1. **Handoff + structure** — this doc, ROADMAP/AGENTS updates (done in planning PR).
2. **Guest types storage + admin UI** — `guestTypes` in `storage.json`, seed defaults, admin CRUD with permission checkboxes and visit-mode-aware field visibility.
3. **Permission resolver + API flags** — server helper `getGuestPermissions(guest)`, enforce on upload/delete/link/smart-home-related routes; extend `/guest/validate` and registration responses with permissions + guest type metadata.
4. **Event list + folder helpers** — events array, event slug helper, multer destination `{stayFolder}/{eventSlug}/`, legacy-safe listing.
5. **Registration flows** — public `index.html` and admin guest registration use guest type picker; fields shown/hidden by type (`requiresRoom`, stay length, event).
6. **Guest UI by permissions** — `welcome.html` / `photo.html` show/hide sections (upload, gallery nav, Smart Home, link device) from API flags.
7. **Admin session type controls** — change guest type on active session; show type in lists and CSV.
8. **Hero landing page** — conditional hero on `index.html` when background is set.
9. **Tests + docs** — `test-suite.sh`, README, CHANGELOG, ROADMAP checklist.

**Defer:**
- Family/household calendar sync for events.
- Guest self-service extend stay (permission exists for future use; admin extend stay remains).
- UniFi external portal, dark mode.

**Optional stretch:**
- Re-tag upload to different event from gallery.
- Admin merge/rename events.
- Duplicate guest type as template.

## Key files

| Area | Files |
|------|-------|
| Guest types admin | `frontend/admin.html`, `frontend/styles.css` |
| Guest entry / hero | `frontend/index.html` |
| Guest hub / gallery | `frontend/welcome.html`, `frontend/photo.html` |
| Server / APIs | `server.js` |
| State templates | `storage.template.json`, `config.template.json` (if day-visit hours become global default) |
| Tests | `test-suite.sh` |
| Docs | `README.md`, `AGENTS.md`, `CHANGELOG.md`, `ROADMAP.md` |

## Server notes

- Guest types and events live in `/etc/guest-portal/storage.json`; sessions in `guest-tokens.json`.
- Add admin routes, e.g. `GET/POST/PATCH/DELETE /admin-api/guest-types`.
- Add public `GET /guest/guest-types` (enabled types only, no admin-only fields) for registration pickers.
- Permission checks belong in middleware or shared helpers used by upload, delete, link-code, and validate routes.
- Smart Home is a link to room dashboard — gate on `smartHomeControls` **and** valid `dashboardUrl` for the guest's room.
- Do not expose disabled admin capabilities through guest API paths.

## Testing expectations

Automated:
- Default guest types seeded on empty storage.
- Admin can create/edit guest type with permission matrix.
- Registration with type lacking `uploadPhotos` → upload returns 403.
- Type with `uploadPhotos` + `tagPhotosToEvent` → file lands under event subfolder.
- Type with `linkDevice: false` → link-code endpoint returns 403.
- Type with `deleteOwnPhotos: false` → delete returns 403.
- `/guest/validate` returns permissions matching guest type.
- Changing guest type on session changes effective permissions.
- Legacy sessions without `guestTypeId` behave as overnight guest.
- Hero landing markup when background configured.
- Frontend inline script syntax checks pass.

```bash
ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

Manual:
- Admin Settings → create "Contractor" day type with upload off, link device off.
- Register as that type → welcome hub hides upload, gallery, Smart Home, link device.
- Register as day personal → event at registration, upload works, event subfolder in admin Photos.
- Edit guest type permissions live → guest page reflects on next validate/refresh.

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

Verify guest type defaults appear in admin, registration offers types, permissions enforce correctly, and hero landing works when background is set.

## Recent context

- Sprint handoff merged in PR #38 on top of PR #36 roadmap items.
- Prior plan used hard-coded Personal/Other categories; **this revision replaces that with configurable guest types and permission checkboxes.**
- Admin operations and guest UX sprints are complete; build on existing welcome hub, gallery, and guest upload APIs.

## Sprint checklist (mirror ROADMAP)

- [x] Handoff doc and ROADMAP/AGENTS updates (planning)
- [x] Guest types storage, defaults, and admin CRUD with permission checkboxes
- [x] Server permission resolver and route enforcement
- [x] Event list storage and event-scoped upload folder paths
- [x] Registration flows driven by guest type (public + admin)
- [x] Guest UI sections shown/hidden by permissions
- [x] Admin guest type assignment and CSV/list columns
- [x] Background hero landing on `/` when background image is set
- [x] Tests and documentation updates
