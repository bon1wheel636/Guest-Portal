#!/bin/bash
# Guest Portal in-container maintenance utility.
# Run as root inside the Guest Portal LXC: updateguest

set -euo pipefail

APP_DIR="/opt/guest-portal"
APP_USER="guestportal"
APP_GROUP="guestportal"
LEGACY_DIR="/root/guest-portal"
SERVICE_NAME="guest-portal"

CONFIG_DIR="${CONFIG_DIR:-/etc/guest-portal}"
DRY_RUN=false
NO_RESTART=false
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: updateguest [command] [options]

With no command, in a terminal, show the maintenance menu.

Commands:
  update     Pull code, install dependencies, fix ownership, and restart
  admin      Reset the admin sign-in, or clear it for the first-run form
  repair     Fix ownership of the app and /etc/guest-portal, then restart
  restart    Restart the guest-portal service
  status     Show the checkout, service, and admin account
  help       Show this help

Update options:
  --dry-run      Show planned steps without making changes
  --no-restart   Do not restart the service
  -y, --yes      Skip the confirmation prompt

Admin:
  updateguest admin            Choose a recovery action
  updateguest admin clear -y   Clear the account for the first-run form

Existing update flags still work:
  updateguest -y
  updateguest --dry-run

Examples:
  updateguest
  updateguest update -y
  updateguest update --dry-run
  updateguest status
EOF
}

update_usage() {
  cat <<'EOF'
Usage: updateguest update [options]

Options:
  --dry-run      Show planned steps without making changes
  --no-restart   Update code and dependencies but do not restart the service
  -y, --yes      Skip confirmation prompt
  -h, --help     Show this help
EOF
}

admin_usage() {
  cat <<'EOF'
Usage: updateguest admin [clear] [-y]

With no arguments, in a terminal, choose a recovery action.
clear -y removes the admin password so /admin.html shows the first-run form.
UniFi settings, rooms, and guest visits stay in place.
EOF
}

log() {
  printf '%s\n' "$*"
}

run_as_app_user() {
  su -s /bin/bash -c "$1" "${APP_USER}"
}

ensure_git_safe_directory() {
  local app_path="$1"
  run_as_app_user "git config --global --add safe.directory '${app_path}'" 2>/dev/null || true
}

# npm install rewrites package-lock.json when the container's npm differs from
# the one that committed it. Curl bootstrap can also drop installer scripts
# into the checkout. Either change blocks the next fast-forward.
KNOWN_CHECKOUT_DRIFT=(
  "scripts/updateguest.sh"
  "scripts/setup-prompts.sh"
  "scripts/setup-container.sh"
  "package-lock.json"
)

restore_checkout_path() {
  local path="$1"
  run_as_app_user "cd '${APP_PATH}' && if git ls-files --error-unmatch '${path}' >/dev/null 2>&1; then git checkout -- '${path}'; elif [[ -e '${path}' ]]; then rm -rf '${path}'; fi" || true
}

discard_known_checkout_drift() {
  local path status_line
  for path in "${KNOWN_CHECKOUT_DRIFT[@]}"; do
    status_line="$(run_as_app_user "cd '${APP_PATH}' && git status --porcelain -- '${path}'" || true)"
    if [[ -n "${status_line}" ]]; then
      log "Discarding local changes to ${path} so git pull can fast-forward..."
      restore_checkout_path "$path"
    fi
  done
}

discard_blocking_checkout_changes() {
  # Guest data lives in /etc/guest-portal and under gitignored uploads/.
  run_as_app_user "cd '${APP_PATH}' && git checkout -- ." || true
  run_as_app_user "cd '${APP_PATH}' && git clean -fd -e uploads" || true
  discard_known_checkout_drift
}

pull_output_is_local_block() {
  local err_file="$1"
  grep -Eq 'would be overwritten|Please commit your changes or stash|Please move or remove them' "$err_file"
}

pull_ff_only() {
  local err_file status
  err_file="$(mktemp)"
  status=0
  run_as_app_user "cd '${APP_PATH}' && git pull --ff-only" 2>"$err_file" || status=$?
  if [[ -s "$err_file" ]]; then
    cat "$err_file" >&2
  fi
  if [[ "$status" -eq 0 ]]; then
    rm -f "$err_file"
    return 0
  fi
  if pull_output_is_local_block "$err_file"; then
    rm -f "$err_file"
    return 10
  fi
  rm -f "$err_file"
  return "$status"
}

pull_latest_code() {
  local status
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] Pulling latest code..."
    return 0
  fi

  log "Pulling latest code..."
  discard_known_checkout_drift
  status=0
  pull_ff_only || status=$?
  if [[ "$status" -eq 0 ]]; then
    return 0
  fi
  if [[ "$status" -ne 10 ]]; then
    log "Error: git pull failed in ${APP_PATH}."
    exit "$status"
  fi

  log "Local checkout changes blocked git pull. Restoring tracked files and retrying..."
  run_as_app_user "cd '${APP_PATH}' && git status --porcelain --untracked-files=all" || true
  discard_blocking_checkout_changes
  status=0
  pull_ff_only || status=$?
  if [[ "$status" -ne 0 ]]; then
    log "Error: git pull --ff-only failed after restoring the checkout in ${APP_PATH}."
    exit "$status"
  fi
}

restore_generated_lockfile() {
  local status_line
  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi
  status_line="$(run_as_app_user "cd '${APP_PATH}' && git status --porcelain -- package-lock.json" || true)"
  if [[ -n "${status_line}" ]]; then
    log "Restoring package-lock.json after npm install..."
    restore_checkout_path "package-lock.json"
  fi
}

run_step() {
  local description="$1"
  shift
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] $description"
    log "          $*"
    return 0
  fi
  log "$description"
  "$@"
}

resolve_app_dir() {
  if [[ -d "${APP_DIR}/.git" ]]; then
    printf '%s' "$APP_DIR"
    return 0
  fi
  if [[ -d "${LEGACY_DIR}/.git" ]]; then
    printf '%s' "$LEGACY_DIR"
    return 0
  fi
  return 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "Error: updateguest must be run as root inside the Guest Portal container."
    exit 1
  fi
}

require_app() {
  if ! APP_PATH="$(resolve_app_dir)"; then
    log "Error: no Guest Portal git checkout found at ${APP_DIR} or ${LEGACY_DIR}."
    log "Run setup.sh from the Proxmox host or clone the repository into ${APP_DIR}."
    exit 1
  fi
}

require_terminal() {
  if [[ -t 0 ]]; then
    return 0
  fi
  log "This action needs a terminal."
  log "From the Proxmox host: pct exec <ctid> -- updateguest update -y"
  exit 1
}

reset_action_flags() {
  DRY_RUN=false
  NO_RESTART=false
  ASSUME_YES=false
}

confirm_action() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == "true" ]]; then
    return 0
  fi
  require_terminal
  local confirm
  read -r -p "${prompt} [y/N] " confirm
  [[ "${confirm,,}" == "y" ]]
}

config_file() {
  printf '%s/config.json' "${CONFIG_DIR}"
}

own_config_file() {
  local path="$1"
  chown "${APP_USER}:${APP_GROUP}" "${path}" 2>/dev/null || true
}

read_admin_user() {
  CONFIG_FILE="$(config_file)" node -e '
    var fs = require("fs");
    var path = process.env.CONFIG_FILE;
    if (!fs.existsSync(path)) process.exit(0);
    var config = JSON.parse(fs.readFileSync(path, "utf8"));
    process.stdout.write(config.adminUser || "");
  '
}

admin_account_state() {
  CONFIG_FILE="$(config_file)" node -e '
    var fs = require("fs");
    var path = process.env.CONFIG_FILE;
    if (!fs.existsSync(path)) {
      process.stdout.write("missing");
      process.exit(0);
    }
    var config = JSON.parse(fs.readFileSync(path, "utf8"));
    var hash = config.adminHash || "";
    if (!hash || hash === "<bcrypt_hash_placeholder>") process.stdout.write("unset");
    else process.stdout.write("configured");
  '
}

write_admin_account() {
  local username="$1"
  local hash="$2"
  mkdir -p "${CONFIG_DIR}"
  CONFIG_FILE="$(config_file)" ADMIN_USER="$username" ADMIN_HASH="$hash" node -e '
    var fs = require("fs");
    var path = process.env.CONFIG_FILE;
    var config = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, "utf8")) : {};
    config.adminUser = process.env.ADMIN_USER;
    config.adminHash = process.env.ADMIN_HASH;
    if (config.uploadDir === undefined) config.uploadDir = "";
    if (!config.sessionExpirationMinutes) config.sessionExpirationMinutes = 10;
    fs.writeFileSync(path, JSON.stringify(config, null, 2) + "\n");
  '
  own_config_file "$(config_file)"
}

clear_admin_sessions() {
  mkdir -p "${CONFIG_DIR}"
  printf '%s\n' '{}' > "${CONFIG_DIR}/admin-sessions.json"
  own_config_file "${CONFIG_DIR}/admin-sessions.json"
}

hash_admin_password() {
  local password="$1"
  if [[ ! -d "${APP_PATH}/node_modules/bcrypt" ]]; then
    log "Error: bcrypt is not installed in ${APP_PATH}. Run: updateguest update -y"
    exit 1
  fi
  (
    cd "${APP_PATH}"
    ADMIN_PASS="$password" node -e "require('bcrypt').hash(process.env.ADMIN_PASS, 10).then(function (hash) { process.stdout.write(hash); })"
  )
}

valid_admin_username() {
  local username="$1"
  [[ "$username" =~ ^[a-zA-Z0-9_-]{3,50}$ ]]
}

prompt_new_admin_account() {
  local current username password confirm hash
  current="$(read_admin_user || true)"
  if [[ -n "$current" ]]; then
    log "Current admin user: ${current}"
  else
    log "No admin user is saved."
  fi
  read -r -p "New username [${current:-admin}]: " username
  username="${username:-${current:-admin}}"
  if ! valid_admin_username "$username"; then
    log "Username must be 3-50 letters, numbers, underscores, or hyphens."
    return 1
  fi
  while true; do
    read -r -s -p "New password: " password
    printf '\n'
    if [[ "${#password}" -lt 8 ]]; then
      log "Password must be at least 8 characters."
      continue
    fi
    read -r -s -p "Confirm password: " confirm
    printf '\n'
    if [[ "$password" == "$confirm" ]]; then
      break
    fi
    log "Passwords do not match."
  done
  log "Saving admin account..."
  hash="$(hash_admin_password "$password")"
  write_admin_account "$username" "$hash"
  clear_admin_sessions
  log "Admin user is now ${username}."
  log "UniFi settings, rooms, and guest visits were left in place."
}

clear_admin_account() {
  write_admin_account "admin" "<bcrypt_hash_placeholder>"
  clear_admin_sessions
  log "Admin account cleared."
  log "Open /admin.html and use the first-run form. UniFi settings, rooms, and guest visits were left in place."
}

restart_service() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[dry-run] Restarting ${SERVICE_NAME} service..."
    return 0
  fi
  log "Restarting ${SERVICE_NAME} service..."
  systemctl restart "${SERVICE_NAME}"
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Service status: active"
    return 0
  fi
  log "Warning: ${SERVICE_NAME} is not active. Check: systemctl status ${SERVICE_NAME}"
  return 1
}

run_update() {
  reset_action_flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --no-restart) NO_RESTART=true; shift ;;
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) update_usage; return 0 ;;
      *)
        log "Unknown option: $1"
        update_usage
        return 1
        ;;
    esac
  done

  require_root
  require_app

  if [[ "$ASSUME_YES" != "true" && "$DRY_RUN" != "true" ]]; then
    log "This will update Guest Portal in ${APP_PATH}, run npm install, fix ownership,"
    if [[ "$NO_RESTART" == "true" ]]; then
      log "and leave the ${SERVICE_NAME} service running without a restart."
    else
      log "and restart the ${SERVICE_NAME} service."
    fi
    if ! confirm_action "Proceed?"; then
      log "Update cancelled."
      return 0
    fi
  fi

  log ""
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Guest Portal update plan"
  else
    log "Updating Guest Portal"
  fi
  log "Application path: ${APP_PATH}"
  log ""

  run_step "Fixing ownership..." chown -R "${APP_USER}:${APP_GROUP}" "${APP_PATH}" "${CONFIG_DIR}"
  ensure_git_safe_directory "${APP_PATH}"
  pull_latest_code
  run_step "Installing npm dependencies..." run_as_app_user "cd '${APP_PATH}' && npm install"
  restore_generated_lockfile
  run_step "Ensuring upload directories exist..." bash -c "mkdir -p '${APP_PATH}/uploads/backgrounds'"
  run_step "Ensuring service user exists..." bash -c "
    groupadd --system '${APP_GROUP}' 2>/dev/null || true
    id -u '${APP_USER}' >/dev/null 2>&1 || useradd --system --gid '${APP_GROUP}' --home-dir '${APP_DIR}' --shell /usr/sbin/nologin '${APP_USER}'
  "
  run_step "Finalizing ownership..." chown -R "${APP_USER}:${APP_GROUP}" "${APP_PATH}" "${CONFIG_DIR}"

  if [[ -f "${APP_PATH}/scripts/updateguest.sh" ]]; then
    run_step "Refreshing updateguest command..." install -m 755 "${APP_PATH}/scripts/updateguest.sh" /usr/local/bin/updateguest
  fi

  if [[ "$NO_RESTART" != "true" ]]; then
    run_step "Restarting ${SERVICE_NAME} service..." systemctl restart "${SERVICE_NAME}"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log ""
    log "Dry run complete. No changes were made."
    return 0
  fi

  log ""
  log "Update complete."
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    log "Service status: active"
    return 0
  fi
  log "Warning: ${SERVICE_NAME} is not active. Check: systemctl status ${SERVICE_NAME}"
  return 1
}

run_status() {
  require_root
  require_app
  local commit="unknown" service_state account user
  commit="$(run_as_app_user "cd '${APP_PATH}' && git rev-parse --short HEAD" || true)"
  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    service_state="active"
  else
    service_state="inactive"
  fi
  account="$(admin_account_state)"
  user="$(read_admin_user || true)"
  log "Application path: ${APP_PATH}"
  log "Commit: ${commit:-unknown}"
  log "Service: ${service_state}"
  log "Admin account: ${account}"
  if [[ -n "$user" ]]; then
    log "Admin user: ${user}"
  fi
}

run_restart() {
  reset_action_flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) log "Usage: updateguest restart [-y]"; return 0 ;;
      *) log "Unknown option: $1"; return 1 ;;
    esac
  done
  require_root
  if ! confirm_action "Restart ${SERVICE_NAME}?"; then
    log "Restart cancelled."
    return 0
  fi
  restart_service
}

run_repair() {
  reset_action_flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) log "Usage: updateguest repair [-y]"; return 0 ;;
      *) log "Unknown option: $1"; return 1 ;;
    esac
  done
  require_root
  require_app
  if ! confirm_action "Fix ownership of ${APP_PATH} and ${CONFIG_DIR}, then restart ${SERVICE_NAME}?"; then
    log "Repair cancelled."
    return 0
  fi
  log "Fixing ownership..."
  chown -R "${APP_USER}:${APP_GROUP}" "${APP_PATH}" "${CONFIG_DIR}"
  restart_service
}

run_admin() {
  reset_action_flags
  local action="menu"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      clear) action="clear"; shift ;;
      -y|--yes) ASSUME_YES=true; shift ;;
      -h|--help) admin_usage; return 0 ;;
      *)
        log "Unknown option: $1"
        admin_usage
        return 1
        ;;
    esac
  done

  require_root
  require_app

  if [[ "$action" == "clear" ]]; then
    if ! confirm_action "Clear the admin account so /admin.html shows the first-run form?"; then
      log "Admin recovery cancelled."
      return 0
    fi
    clear_admin_account
    restart_service
    return 0
  fi

  require_terminal
  while true; do
    log ""
    log "Admin account recovery"
    log "Admin account: $(admin_account_state)"
    local current
    current="$(read_admin_user || true)"
    if [[ -n "$current" ]]; then
      log "Admin user: ${current}"
    fi
    log "A sign-in lockout clears when the service restarts, or after 10 minutes."
    log "UniFi settings, rooms, and guest visits stay in place."
    log ""
    log "  1) Set a new username and password"
    log "  2) Clear the account for the first-run form"
    log "  3) Restart the service to clear a sign-in lockout"
    log "  4) Back"
    log ""
    local choice
    read -r -p "Select [1-4]: " choice
    case "$choice" in
      1)
        if prompt_new_admin_account; then
          restart_service
        fi
        ;;
      2)
        ASSUME_YES=false
        if confirm_action "Clear the admin account so /admin.html shows the first-run form?"; then
          clear_admin_account
          restart_service
        else
          log "Admin recovery cancelled."
        fi
        ;;
      3)
        restart_service
        ;;
      4)
        return 0
        ;;
      *)
        log "Choose 1, 2, 3, or 4."
        ;;
    esac
  done
}

run_menu() {
  require_terminal
  while true; do
    log ""
    log "Guest Portal"
    log "Application path: ${APP_PATH}"
    log ""
    log "  1) Update application"
    log "  2) Preview update"
    log "  3) Admin account recovery"
    log "  4) Fix ownership and restart"
    log "  5) Restart service"
    log "  6) Show status"
    log "  7) Exit"
    log ""
    local choice
    read -r -p "Select [1-7]: " choice
    case "$choice" in
      1) run_update || true ;;
      2) run_update --dry-run || true ;;
      3) run_admin || true ;;
      4) ASSUME_YES=true run_repair -y || true ;;
      5) ASSUME_YES=true run_restart -y || true ;;
      6) run_status || true ;;
      7) log "Done."; return 0 ;;
      *) log "Choose 1 through 7." ;;
    esac
  done
}

dispatch() {
  if [[ $# -eq 0 ]]; then
    require_root
    require_app
    run_menu
    return 0
  fi

  local command="$1"
  case "$command" in
    -h|--help|help)
      usage
      ;;
    update)
      shift
      run_update "$@"
      ;;
    admin)
      shift
      run_admin "$@"
      ;;
    repair)
      shift
      run_repair "$@"
      ;;
    restart)
      shift
      run_restart "$@"
      ;;
    status)
      shift
      if [[ $# -gt 0 ]]; then
        log "status does not take options."
        return 1
      fi
      run_status
      ;;
    --dry-run|--no-restart|-y|--yes)
      run_update "$@"
      ;;
    *)
      log "Unknown command: ${command}"
      usage
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  dispatch "$@"
fi
