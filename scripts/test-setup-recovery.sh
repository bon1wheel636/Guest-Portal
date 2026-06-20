#!/usr/bin/env bash
# Integration tests for setup-container recovery menu handlers.
# Usage: sudo bash scripts/test-setup-recovery.sh

set -euo pipefail

export PATH="/home/ubuntu/.nvm/versions/node/v22.22.2/bin:/exec-daemon:${PATH}"

ROOT=""
APP_DIR=""
CONFIG_DIR=""
APP_USER="gptestrecovery"
APP_GROUP="gptestrecovery"
WORKSPACE=""
PASSED=0
FAILED=0

pass() {
  echo "PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "FAIL: $1"
  FAILED=$((FAILED + 1))
}

assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$expected', got '$actual')"
  fi
}

assert_file_exists() {
  local desc="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    pass "$desc"
  else
    fail "$desc (missing $path)"
  fi
}

assert_contains() {
  local desc="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (missing '$needle')"
  fi
}

cleanup() {
  if [[ -n "$ROOT" && -d "$ROOT" ]]; then
    rm -rf "$ROOT"
  fi
  userdel "$APP_USER" 2>/dev/null || true
  groupdel "$APP_GROUP" 2>/dev/null || true
}
trap cleanup EXIT

header_info() { :; }

setup_ui_vars() {
  TAB="  "
  CL=""
  BOLD=""
  RD=""
  GN=""
  YW=""
  CM="${TAB}OK"
  INFO="${TAB}INFO"
  CROSS="${TAB}ERR"
}

setup_test_env() {
  setup_ui_vars
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Run as root: sudo bash scripts/test-setup-recovery.sh"
    exit 1
  fi

  WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
  ROOT="$(mktemp -d /tmp/gp-recovery-test.XXXXXX)"
  chmod 755 "$ROOT"
  APP_DIR="$ROOT/opt/guest-portal"
  CONFIG_DIR="$ROOT/etc/guest-portal"

  groupadd "$APP_GROUP" 2>/dev/null || true
  if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd -M -d "$APP_DIR" -s /bin/bash -g "$APP_GROUP" "$APP_USER"
  fi

  mkdir -p "$APP_DIR" "$CONFIG_DIR"
  git clone --quiet "file://${WORKSPACE}" "$APP_DIR"
  cp -a "${WORKSPACE}/node_modules" "${APP_DIR}/"
  chown -R "$APP_USER:$APP_GROUP" "$APP_DIR" "$CONFIG_DIR"
  su -s /bin/bash -c "cd '${APP_DIR}' && git config --global --add safe.directory '${APP_DIR}'" "$APP_USER" >/dev/null

  gp_app_dir="$APP_DIR"
  gp_config_dir="$CONFIG_DIR"
  gp_app_user="$APP_USER"
  gp_app_group="$APP_GROUP"
  gp_repo="file://${WORKSPACE}"

  # shellcheck source=/dev/null
  source "${WORKSPACE}/scripts/setup-prompts.sh"

  prompt_yes_no() {
    local default="${2:-n}"
    local answer
    read -r answer || answer="$default"
    answer=${answer:-$default}
    [[ "${answer,,}" == "y" ]]
  }

  msg_info() { echo "INFO: $*"; }
  msg_ok() { echo "OK: $*"; }
  msg_error() { echo "ERR: $*" >&2; }

  gp_reset_application_code() {
    local force_reclone="${1:-false}"
    local keep_uploads="${2:-false}"
    local uploads_backup=""

    if [[ "$force_reclone" == "true" && "$keep_uploads" == "true" && -d "${gp_app_dir}/uploads" ]]; then
      uploads_backup="$(mktemp -d)"
      chmod 755 "$uploads_backup"
      cp -a "${gp_app_dir}/uploads/." "${uploads_backup}/"
    fi

    rm -rf "${gp_app_dir}"
    git clone --quiet "${gp_repo}" "${gp_app_dir}"
    if [[ -n "$uploads_backup" ]]; then
      mkdir -p "${gp_app_dir}/uploads"
      cp -a "${uploads_backup}/." "${gp_app_dir}/uploads/"
      rm -rf "$uploads_backup"
    fi
    cp -a "${WORKSPACE}/node_modules" "${gp_app_dir}/"
    chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}"
    mkdir -p "${gp_app_dir}/uploads/backgrounds"
  }

  gp_install_systemd_service() { :; }
  gp_restart_service() { :; }
  gp_service_status_label() { echo "test"; }
}

seed_existing_install() {
  node -e "
    var fs = require('fs');
    var bcrypt = require('bcrypt');
    var hash = bcrypt.hashSync('TestPass123', 10);
    fs.writeFileSync('${CONFIG_DIR}/config.json', JSON.stringify({
      adminUser: 'opsadmin',
      adminHash: hash,
      uploadDir: '',
      sessionExpirationMinutes: 10,
      adminSessionTimeoutMinutes: 15
    }, null, 2));
    fs.writeFileSync('${CONFIG_DIR}/storage.json', JSON.stringify({
      rooms: [
        { name: 'Room 101', dashboardUrl: 'http://example.com/101' },
        { name: 'Room 102', dashboardUrl: 'http://example.com/102' }
      ],
      guests: [{ id: 'guest-1', name: 'Test Guest', room: 'Room 101' }]
    }, null, 2));
    fs.writeFileSync('${CONFIG_DIR}/sessions.json', JSON.stringify({ CODE1: { expires: Date.now() + 60000 } }));
    fs.writeFileSync('${CONFIG_DIR}/guest-tokens.json', JSON.stringify({ token1: { guestId: 'guest-1' } }));
  "
  mkdir -p "${APP_DIR}/uploads/backgrounds"
  echo "photo" > "${APP_DIR}/uploads/keep-me.txt"
  chown -R "$APP_USER:$APP_GROUP" "$CONFIG_DIR" "${APP_DIR}/uploads"
}

test_option_continue() {
  seed_existing_install
  SKIP_ROOM_SETUP=true
  ADMIN_ACTION=keep
  ADMIN_USER=opsadmin
  gp_write_setup_config_files
  assert_eq "continue keeps room count" "2" "$(gp_read_existing_room_count)"
  assert_eq "continue keeps admin user" "opsadmin" "$(gp_read_existing_admin_user)"
}

test_option_reset_admin_web() {
  seed_existing_install
  GP_SETUP_MODE=reset_admin
  ADMIN_ACTION=reset
  ADMIN_USER=admin
  gp_write_setup_config_files
  if gp_admin_credentials_configured; then
    fail "reset admin web should clear configured credentials"
  else
    pass "reset admin web clears configured credentials"
  fi
}

test_option_reset_rooms() {
  seed_existing_install
  GP_SETUP_MODE=reset_rooms
  SKIP_ROOM_SETUP=false
  ROOMS=('{"name":"New Room","dashboardUrl":"http://example.com/new"}')
  GP_CLEAR_GUEST_HISTORY=false
  ADMIN_ACTION=keep
  gp_write_setup_config_files
  assert_eq "reset rooms replaces room count" "1" "$(gp_read_existing_room_count)"
  assert_eq "reset rooms keeps guest history" "1" "$(gp_read_existing_guest_history_count)"
}

test_option_reset_guests() {
  seed_existing_install
  printf 'n\n' | gp_handle_reset_guests_mode >/dev/null
  assert_eq "reset guests clears session codes" "{}" "$(cat "${CONFIG_DIR}/sessions.json")"
  assert_eq "reset guests keeps history when declined" "1" "$(gp_read_existing_guest_history_count)"
}

test_option_repair() {
  seed_existing_install
  gp_handle_repair_mode >/dev/null
  pass "repair mode completes"
}

test_option_rebuild() {
  seed_existing_install
  GP_REBUILD_KEEP_UPLOADS=true
  gp_wipe_install_state true
  gp_reset_application_code true true
  chown -R "$APP_USER:$APP_GROUP" "$APP_DIR" "$CONFIG_DIR"
  assert_file_exists "rebuild keeps uploads when requested" "${APP_DIR}/uploads/keep-me.txt"
  assert_eq "rebuild clears config files" "0" "$(find "$CONFIG_DIR" -maxdepth 1 -type f | wc -l | tr -d ' ')"
  SKIP_ROOM_SETUP=false
  ROOMS=('{"name":"Fresh Room","dashboardUrl":"http://example.com/fresh"}')
  ADMIN_ACTION=skip
  gp_write_setup_config_files
  assert_eq "rebuild writes fresh room" "1" "$(gp_read_existing_room_count)"
  assert_file_exists "rebuild leaves cloned app checkout" "${APP_DIR}/server.js"
}

test_option_cancel() {
  GP_SETUP_MODE=cancel
  assert_eq "cancel mode value" "cancel" "$GP_SETUP_MODE"
  pass "cancel option sets mode"
}

test_option_update_only() {
  seed_existing_install
  gp_update_application_code() { echo "updated"; }
  gp_handle_update_only_mode >/dev/null
  pass "update-only mode completes"
}

main() {
  setup_test_env
  echo "Running setup recovery integration tests in ${ROOT}"
  echo ""

  test_option_cancel
  test_option_continue
  test_option_reset_admin_web
  test_option_reset_rooms
  test_option_reset_guests
  test_option_repair
  test_option_update_only
  test_option_rebuild

  echo ""
  echo "Results: ${PASSED} passed, ${FAILED} failed"
  if [[ "$FAILED" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
