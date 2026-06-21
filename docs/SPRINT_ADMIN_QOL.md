# Sprint: Admin quality-of-life

**Status:** Planned — handoff complete; implementation not started.

Use this document to continue work in a **new agent session** without relying on prior chat history.

## Goal

Polish the **admin panel** (`admin.html`) for day-to-day host use without changing guest permissions, upload paths, or registration flows. Primary deliverable: a **dark mode toggle** that works on phones and desktops.

**Depends on:** [docs/SPRINT_EVENTS_UX.md](SPRINT_EVENTS_UX.md) completion (gallery re-tag and admin event merge UI). Do not start this sprint while Events UX remaining items are still open unless the owner explicitly reprioritizes.

**Out of scope:** guest-facing pages (`index.html`, `welcome.html`, `photo.html`), UniFi integration, new admin APIs beyond optional theme persistence.

## Current behavior (after PR #46)

| Area | Current state |
|------|---------------|
| Admin UI | Light theme only — white cards (`#fff`), dark text, blue accent tabs. |
| Theme storage | None; appearance is fixed in `styles.css`. |
| Responsive admin | Tabs wrap; cards and actions stack on narrow viewports; usable on mobile but not optimized for dark environments. |
| Settings tab | Portal URL, link code expiration, admin account info — no appearance preferences. |

**Problems:**
- Long evening admin sessions on a bright panel are hard on the eyes.
- No user preference for theme; hosts cannot match OS dark mode or personal preference.

## Target behavior (this sprint)

### 1. Dark mode toggle

Add a theme control in the admin panel (recommended: **Settings** tab, top of **Overview**, or admin header — pick one and stay consistent).

| Requirement | Detail |
|-------------|--------|
| Modes | `light` (default, current look) and `dark`. |
| Persistence | **`localStorage`** key e.g. `adminTheme` — per browser/device, no server migration required for v1. |
| Apply | Class on `document.body` or `document.documentElement`, e.g. `admin-theme-dark`. |
| Flash prevention | Inline script in `<head>` of `admin.html` (before paint) reads `localStorage` and sets class to avoid light flash on load. |
| Scope | **Admin pages only** (`admin.html`). Guest portal pages unchanged. |

**CSS approach (recommended):**

- Introduce CSS custom properties on `.admin-container` or `:root` for admin tokens:

```css
.admin-container {
  --admin-bg: #f5f5f5;
  --admin-surface: #fff;
  --admin-text: #222;
  --admin-muted: #666;
  --admin-border: #ddd;
  --admin-accent: #0066cc;
}

.admin-theme-dark.admin-container,
body.admin-theme-dark .admin-container {
  --admin-bg: #1a1a1a;
  --admin-surface: #2a2a2a;
  --admin-text: #eee;
  --admin-muted: #aaa;
  --admin-border: #444;
  --admin-accent: #6eb5ff;
}
```

- Refactor existing admin rules incrementally: replace hardcoded `#fff`, `#222`, `#ddd` in admin sections with variables. Priority surfaces: tabs, cards, lists, forms, deployment status blocks, photo grid, Events/Guest Types lists.
- Preserve contrast for status badges (OK/error), QR preview boxes, and permission fieldsets.

**Toggle UI:**

- Checkbox, switch, or button group: “Dark mode”.
- Label clearly; no dependency on OS `prefers-color-scheme` for v1 (optional stretch: default from `matchMedia` on first visit only).

### 2. Responsive / mobile

Dark mode must work at the same breakpoints as the existing admin layout:

- Tabs remain tappable (no new horizontal scroll).
- Cards and form fields readable at 320px width.
- Modal-less admin flows unchanged.

Manual check: Settings, Events, Guests, and Photos tabs in dark mode on phone and laptop widths.

### 3. Tests and documentation

| Item | Action |
|------|--------|
| `test-suite.sh` | Optional: assert `admin.html` contains theme class hook + toggle id (smoke, like hero markup test). |
| `CHANGELOG.md` | Note admin dark mode. |
| `ROADMAP.md` | Mark Admin QoL sprint complete when done. |
| `AGENTS.md` | Point active sprint to next queue item (UniFi). |

No new integration tests required unless theme is stored in `config.json` (not planned for v1).

## Implementation order (recommended PRs)

1. **CSS variables + dark palette** — refactor core admin surfaces; verify light mode unchanged.
2. **Toggle + localStorage + anti-flash script** — Settings (or header) control.
3. **Polish pass** — deployment status, photo cards, Events tab, error/success colors in dark mode.
4. **Docs + optional smoke test** — CHANGELOG, ROADMAP, AGENTS.

**Defer (backlog / later sprints):**
- Server-persisted admin theme in `config.json` (shared across browsers).
- Dark mode for guest pages.
- UniFi external portal ([UNIFI.md](../UNIFI.md) — ask owner for controller details first).

**Optional stretch (this sprint only):**
- Respect `prefers-color-scheme: dark` as initial default when `localStorage` is unset.
- Compact admin tab bar on very small screens.

## Key files

| Area | Files |
|------|-------|
| Admin UI + toggle | `frontend/admin.html` |
| Admin + shared styles | `frontend/styles.css` |
| Tests | `test-suite.sh` (optional smoke) |
| Docs | `ROADMAP.md`, `AGENTS.md`, `CHANGELOG.md` |

## Testing expectations

Automated:

```bash
npm start
bash test-suite.sh
# Admin mutation tests still require:
ADMIN_USER=admin ADMIN_PASS='<password>' bash test-suite.sh
```

Manual:

- Toggle dark mode; reload page — preference persists.
- Light mode still matches pre-sprint appearance.
- All admin tabs readable; no invisible text on cards or deployment status.
- Register guest, Events tab, and photo preview usable in dark mode.

## Dev environment

```bash
sudo mkdir -p /etc/guest-portal && sudo chown -R "$USER":"$USER" /etc/guest-portal
cp config.template.json /etc/guest-portal/config.json
cp storage.template.json /etc/guest-portal/storage.json
echo '{}' > /etc/guest-portal/sessions.json
echo '{}' > /etc/guest-portal/guest-tokens.json

npm install && npm start
```

Open `http://localhost:3000/admin.html` after admin setup.

## Recent context

- Events UX (PR #46): admin Events tab, registration event picker, hero registration modal shipped.
- Events UX **remaining** before this sprint: guest gallery re-tag, admin event merge UI — see [docs/SPRINT_EVENTS_UX.md](SPRINT_EVENTS_UX.md).
- Sprint queue: hardening (done) → Events UX (finishing) → **Admin QoL (this doc)** → UniFi.

## Sprint checklist (mirror ROADMAP)

- [ ] Handoff doc and ROADMAP/AGENTS updates (planning)
- [ ] Admin CSS variables for light/dark tokens
- [ ] Dark mode toggle with localStorage persistence
- [ ] Anti-flash theme script on admin page load
- [ ] Responsive verification (mobile + desktop)
- [ ] Tests and documentation updates
