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

## Suggested next sprint: deployment checks and update safety

### High priority

- [ ] **Add deployment health checks**
  - Add a lightweight authenticated admin status view.
  - Document checks for service status, reverse proxy reachability, NAS writability, and Home Assistant URL reachability.
- [ ] **Improve setup/update safety**
  - Detect existing installs.
  - Prompt before changing config, storage, service files, or NAS mount settings.
  - Add a dry-run option for setup changes.

### Medium priority

- [ ] **Improve guest upload UX**
  - Show per-file validation errors.
  - Show upload progress for large videos.
  - Add clearer guidance for PDF letters and phone photo uploads.

### Lower priority

- [ ] **UniFi external portal integration**
  - Add only after controller version, auth method, site ID, and authorization model are known.
  - Keep initial deployment on UniFi's built-in guest/hotspot authorization plus post-auth redirect.
- [ ] **Admin quality-of-life improvements**
  - QR code for device linking.
  - Dark mode toggle.
  - Guest photo preview/gallery.
  - CSV export for guest/session records.
