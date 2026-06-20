#!/bin/bash
# Guest Portal in-container update utility.
# Run as root inside the Guest Portal LXC: updateguest

set -euo pipefail

APP_DIR="/opt/guest-portal"
APP_USER="guestportal"
APP_GROUP="guestportal"
LEGACY_DIR="/root/guest-portal"
SERVICE_NAME="guest-portal"

DRY_RUN=false
NO_RESTART=false
ASSUME_YES=false

usage() {
  cat <<'EOF'
Usage: updateguest [options]

Update the Guest Portal application from git, refresh npm dependencies,
fix ownership, and restart the service.

Options:
  --dry-run      Show planned steps without making changes
  --no-restart   Update code and dependencies but do not restart the service
  -y, --yes      Skip confirmation prompt
  -h, --help     Show this help

Examples:
  updateguest
  updateguest --dry-run
  updateguest -y
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-restart)
      NO_RESTART=true
      shift
      ;;
    -y|--yes)
      ASSUME_YES=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  log "Error: updateguest must be run as root inside the Guest Portal container."
  exit 1
fi

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

if ! APP_PATH="$(resolve_app_dir)"; then
  log "Error: no Guest Portal git checkout found at ${APP_DIR} or ${LEGACY_DIR}."
  log "Run setup.sh from the Proxmox host or clone the repository into ${APP_DIR}."
  exit 1
fi

if [[ "$ASSUME_YES" != "true" && "$DRY_RUN" != "true" ]]; then
  log "This will update Guest Portal in ${APP_PATH}, run npm install, fix ownership,"
  if [[ "$NO_RESTART" == "true" ]]; then
    log "and leave the ${SERVICE_NAME} service running without a restart."
  else
    log "and restart the ${SERVICE_NAME} service."
  fi
  read -r -p "Proceed? [y/N] " confirm
  if [[ "${confirm,,}" != "y" ]]; then
    log "Update cancelled."
    exit 0
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

run_step "Fixing ownership..." chown -R "${APP_USER}:${APP_GROUP}" "${APP_PATH}" /etc/guest-portal
ensure_git_safe_directory "${APP_PATH}"
run_step "Pulling latest code..." run_as_app_user "cd '${APP_PATH}' && git pull --ff-only"
run_step "Installing npm dependencies..." run_as_app_user "cd '${APP_PATH}' && npm install"
run_step "Ensuring upload directories exist..." bash -c "mkdir -p '${APP_PATH}/uploads/backgrounds'"
run_step "Ensuring service user exists..." bash -c "
  groupadd --system '${APP_GROUP}' 2>/dev/null || true
  id -u '${APP_USER}' >/dev/null 2>&1 || useradd --system --gid '${APP_GROUP}' --home-dir '${APP_DIR}' --shell /usr/sbin/nologin '${APP_USER}'
"
run_step "Finalizing ownership..." chown -R "${APP_USER}:${APP_GROUP}" "${APP_PATH}" /etc/guest-portal

if [[ -f "${APP_PATH}/scripts/updateguest.sh" ]]; then
  run_step "Refreshing updateguest command..." install -m 755 "${APP_PATH}/scripts/updateguest.sh" /usr/local/bin/updateguest
fi

if [[ "$NO_RESTART" != "true" ]]; then
  run_step "Restarting ${SERVICE_NAME} service..." systemctl restart "${SERVICE_NAME}"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log ""
  log "Dry run complete. No changes were made."
  exit 0
fi

log ""
log "Update complete."
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  log "Service status: active"
else
  log "Warning: ${SERVICE_NAME} is not active. Check: systemctl status ${SERVICE_NAME}"
  exit 1
fi
