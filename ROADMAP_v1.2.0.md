# 🚧 Guest Portal v1.2.0 Roadmap

## 🔒 Security & Session Enhancements
### 🎯 High Priority
- [ ] **Prevent session code reuse**
  - Invalidate session code after use to ensure one-time use enforcement
- [ ] **Enforce session expiration setting from Admin UI**
  - Make the session expiration configurable from the Admin Panel and respected in the backend logic

## ⚙️ Deployment & Resilience
### 🎯 High Priority
- [ ] **Implement update-safe deployment detection**
  - Allow `setup.sh` to detect existing installations and skip/merge appropriately
  - Prompt before overwriting `config.json` or `storage.json`

## 🎨 Frontend / UX Improvements
### 🔆 Medium Priority
- [ ] **Dark mode toggle**
  - [ ] Respect system preference (e.g., prefers-color-scheme)
  - [ ] Default to dark if no preference
  - [ ] Add toggle button in all pages
- [ ] **Photo preview or gallery viewer**
  - Allow users to view uploaded photos per guest/date folder

### 🧪 Medium Priority
- [ ] **Add `/health` endpoint**
  - Return status JSON for monitoring (`{status: "ok"}`)

- [ ] **Display current upload base directory in Admin UI**
  - Fetch from `/admin-api/uploadDir` and show next to the config input

## 🧹 Additional Refinements (Optional for v1.2.0)
### 🔧 Low Priority
- [ ] Improve guest upload error handling
- [ ] Option to resend/share session code (e.g., QR code or copy button)
- [ ] Show guest registration timestamp in Admin UI
- [ ] Localization/multilingual support (pending revisit)
