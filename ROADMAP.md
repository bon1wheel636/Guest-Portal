# Guest Portal Roadmap

This roadmap tracks shareable project work only. Keep private domains, NAS hostnames, Cloudflare keys, Home Assistant URLs, and UniFi controller details in local configuration or deployment notes outside git.

## Completed baseline

- [x] Persistent guest sessions and device linking
- [x] Admin Basic Auth with bcrypt password hashes
- [x] Configurable upload path for NAS mounts
- [x] Protected admin upload browser/download/delete flows
- [x] Guest uploads require an active guest token
- [x] Guest uploads reject scripts and executable file types
- [x] UniFi guest WiFi deployment guidance
- [x] Dependency audit currently passes for production dependencies
- [x] Least-privilege LXC defaults with a non-root `guestportal` service user
- [x] Generic Nginx Proxy Manager, split DNS, and DNS challenge HTTPS guidance
- [x] Backup/restore guidance for config, app state, uploads, and NAS permissions
- [x] Authenticated deployment status checks for app health, proxy headers, upload storage, data counts, and dashboard URL reachability
- [x] Setup dry-run and existing-install update mode with prompts before sensitive changes
- [x] Guest upload UX with per-file validation, progress, and clearer PDF/photo guidance
- [x] Admin guest and session management (register guests, change rooms, clear devices, check out, purge expired sessions, registration history cleanup)

## Completed sprint: deployment safety foundation

- [x] **Use least-privilege LXC defaults**
  - Prefer unprivileged containers where NAS mount requirements allow it.
  - Run the Node service as a dedicated non-root user.
  - Document the tradeoff if a privileged container is required for a specific NAS mount.
- [x] **Harden reverse proxy deployment**
  - Add generic Nginx Proxy Manager guidance for internal DNS, HTTPS, HSTS, and upload size limits.
  - Keep domain names and Cloudflare tokens out of repo files.
  - Document Cloudflare DNS challenge setup using placeholders only.
- [x] **Add backup and restore guidance**
  - Document what to back up from `/etc/guest-portal`.
  - Document how to restore config, rooms, guest sessions, and upload metadata.
  - Include NAS share permission and quota checks.

## Completed sprint: deployment checks and update safety

- [x] **Add deployment health checks**
  - Add a lightweight authenticated admin status view.
  - Document checks for service status, reverse proxy reachability, NAS writability, and Home Assistant URL reachability.
- [x] **Improve setup/update safety**
  - Detect existing installs.
  - Prompt before changing config, storage, service files, or NAS mount settings.
  - Add a dry-run option for setup changes.
- [x] **Improve guest upload UX**
  - Show per-file validation errors.
  - Show upload progress for large videos.
  - Add clearer guidance for PDF letters and phone photo uploads.

## Completed sprint: admin guest management

- [x] **Clarify registration history vs active sessions**
  - Deployment status and admin panel now show separate counts.
  - Registration history explains that repeated registrations add new rows.
- [x] **Admin guest controls**
  - Register guests on behalf of visitors.
  - Change room affiliation for active sessions.
  - Clear linked devices, extend stays, check out, and purge expired sessions.
  - Remove or bulk-clean registration history entries.
- [x] **In-container update command**
  - `updateguest` runs git pull, npm install, ownership fixes, and service restart from the LXC console.

## Completed sprint: guest convenience and integration

**Handoff:** [docs/SPRINT_GUEST_UX.md](docs/SPRINT_GUEST_UX.md).

- [x] **Returning guest recognition and welcome messaging**
  - Do not show "Welcome back" immediately after first registration.
  - Show "Welcome back" only when the device is recognized and the guest name matches an active session, so the portal knows they are a returning guest on the same stay.
  - For new guests, unrecognized devices, or uncertain matches, use a first-visit greeting such as "We're glad you're here" (or similar).
  - After a guest returns on a linked/recognized device during their stay, use "Welcome back" for the remainder of that stay.
- [x] **First-stay guest tutorial**
  - After first registration, show a short onboarding tutorial explaining what guests can do from the portal (room dashboard, photo upload, device linking, etc.).
  - Include a practical tip to bookmark the portal or save it to the home screen so it is easy to find again during the stay.
- [x] **Guest welcome hub (`welcome.html`) and photo gallery split**
  - Replace today's post-registration landing at `photo.html` with a guest-facing **`welcome.html`** hub (name should reflect welcome/orientation, not photo upload).
  - Make **`welcome.html` the first page guests see after registration** and on return visits during their stay.
  - Keep core stay actions on one page: greeting, Smart Home link, device linking, and a **photo upload section** (not a separate first landing focused on uploads).
  - Use simple navigation (tabs or prominent links) so guests can move between **Welcome** and **My Photos** without feeling like upload is the whole app.
  - Repurpose **`photo.html` as a guest photo gallery** showing what they have already uploaded during this stay.
  - Allow guests to **delete individual uploads one at a time** from the gallery in case they uploaded something by mistake (guest-scoped delete only; admin retains full folder management).
  - Prioritize layout and copy that make upload feel easy, optional, and safe so guests are more likely to use it.
- [x] **Guest-scoped upload list/delete APIs** (supports gallery; see sprint doc)

## Completed sprint: admin operations and confidence

**Handoff:** [docs/SPRINT_ADMIN_OPS.md](docs/SPRINT_ADMIN_OPS.md).

- [x] **Guest entry health checks**
  - Add an admin Guest Entry Health card or panel covering `/health`, `/`, `/guest/rooms`, `/welcome.html`, `/photo.html`, and guest room count.
  - Extend automated smoke coverage for guest entry endpoints and frontend inline script syntax.
  - Document a post-`updateguest -y` verification checklist.
- [x] **Admin photo preview/gallery**
  - Add visual previews to the admin Guest Photos section without removing existing folder-level zip download/delete behavior.
  - Show useful file metadata such as filename, size, folder/stay, and upload timestamp where available.
  - Keep preview/download routes authenticated and scoped under the configured upload directory.
- [x] **CSV exports**
  - Export active sessions as CSV.
  - Export registration history as CSV.
  - Escape CSV values correctly and keep exports behind admin auth.
- [x] **Device-link QR code**
  - Show a QR code alongside generated link codes where it helps guests or hosts link another device.
  - Keep the existing text code as the accessibility and fallback path.
- [x] **Admin guest handoff and portal URL**
  - Per-guest link code/QR generation from the admin Guests tab.
  - Configurable public portal URL for correct FQDN in generated links.
- [x] **Device link code expiration**
  - Configurable expiration for guest- and admin-generated link codes and QR codes.
  - Removed non-functional admin auto-logout setting; documented HTTP Basic Auth sign-out.
- [x] **Tests and documentation updates**
  - Update `test-suite.sh`, README, DEPLOY/PROXY if needed, CHANGELOG, ROADMAP, and AGENTS.

## In progress sprint: guest types, permissions, events, and entry landing

**Handoff:** [docs/SPRINT_DAY_VISITORS.md](docs/SPRINT_DAY_VISITORS.md) — read this at the start of a new agent session (avoids relying on full chat context).

- [ ] **Configurable guest types (admin)**
  - Add a Guest Types section in the admin panel to create, edit, enable/disable, and reorder types.
  - Each type defines visit mode (`overnight` or `day`), session defaults (stay days or day-visit hours), whether room is required, and a **permission checkbox matrix**.
  - Seed defaults: Overnight Guest, Day Visitor — Personal, Day Visitor — Business (hosts can customize).
  - Permissions include at minimum: upload photos, delete own photos, view photo gallery, Smart Home controls, link device, extend stay (future), select stay length, select event at registration, tag photos to event, create event names, view welcome hub, sign out.
  - Gray out visit-mode-inapplicable permissions in the admin UI (e.g. stay length only for overnight).
- [ ] **Permission enforcement (server + guest UI)**
  - Resolve effective permissions from the guest's assigned type on every guest-scoped route.
  - Return permission flags in `/guest/validate` and registration responses so `welcome.html` / `photo.html` hide disabled sections.
  - Admin can change a guest's type on an active session; CSV and session lists show type and visit mode.
  - Legacy sessions without a type id map to the default overnight type.
- [ ] **Event names and photo grouping**
  - Event name field (free text) with guest/admin creation when permitted by type.
  - Day types may require event at registration; overnight types tag at upload when allowed.
  - Event-scoped upload subfolders under each stay folder; gallery groups by event.
- [ ] **Background hero landing page**
  - When a background image is set, `/` (`index.html`) shows a hero with a mid-to-low Register button; device link entry preserved.
  - Registration from hero uses guest type picker and permission-driven fields.
- [ ] **Tests and documentation updates**
  - Update `test-suite.sh`, README, CHANGELOG, ROADMAP, and AGENTS.

## Backlog

### Deferred from day visitors sprint

- [ ] **Event calendar integration (low priority)**
  - Optional sync with a family or household calendar for suggested event names and dates.

### Other backlog

- [ ] **UniFi external portal integration**
  - Add only after controller version, auth method, site ID, and authorization model are known.
  - Keep initial deployment on UniFi's built-in guest/hotspot authorization plus post-auth redirect.
- [ ] **Admin quality-of-life improvements**
  - Dark mode toggle.
