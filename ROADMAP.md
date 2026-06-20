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

## Suggested next sprint: guest convenience and integration

- [ ] **Returning guest recognition and welcome messaging**
  - Do not show "Welcome back" immediately after first registration.
  - Show "Welcome back" only when the device is recognized and the guest name matches an active session, so the portal knows they are a returning guest on the same stay.
  - For new guests, unrecognized devices, or uncertain matches, use a first-visit greeting such as "We're glad you're here" (or similar).
  - After a guest returns on a linked/recognized device during their stay, use "Welcome back" for the remainder of that stay.
- [ ] **First-stay guest tutorial**
  - After first registration, show a short onboarding tutorial explaining what guests can do from the portal (room dashboard, photo upload, device linking, etc.).
  - Include a practical tip to bookmark the portal or save it to the home screen so it is easy to find again during the stay.
- [ ] **Guest welcome hub (`welcome.html`) and photo gallery split**
  - Replace today's post-registration landing at `photo.html` with a guest-facing **`welcome.html`** hub (name should reflect welcome/orientation, not photo upload).
  - Make **`welcome.html` the first page guests see after registration** and on return visits during their stay.
  - Keep core stay actions on one page: greeting, Smart Home link, device linking, and a **photo upload section** (not a separate first landing focused on uploads).
  - Use simple navigation (tabs or prominent links) so guests can move between **Welcome** and **My Photos** without feeling like upload is the whole app.
  - Repurpose **`photo.html` as a guest photo gallery** showing what they have already uploaded during this stay.
  - Allow guests to **delete individual uploads one at a time** from the gallery in case they uploaded something by mistake (guest-scoped delete only; admin retains full folder management).
  - Prioritize layout and copy that make upload feel easy, optional, and safe so guests are more likely to use it.
- [ ] **UniFi external portal integration**
  - Add only after controller version, auth method, site ID, and authorization model are known.
  - Keep initial deployment on UniFi's built-in guest/hotspot authorization plus post-auth redirect.
- [ ] **Admin quality-of-life improvements**
  - QR code for device linking.
  - Dark mode toggle.
  - Admin-side guest photo preview/gallery (separate from guest-facing `photo.html` gallery).
  - CSV export for guest/session records.
