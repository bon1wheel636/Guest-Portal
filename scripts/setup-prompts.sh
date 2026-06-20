#!/usr/bin/env bash
# Shared setup prompts for Guest Portal installers.
# Sourced by setup-container.sh after the app repository is present.

gp_config_dir="${gp_config_dir:-/etc/guest-portal}"
gp_app_dir="${gp_app_dir:-/opt/guest-portal}"
gp_app_user="${gp_app_user:-guestportal}"
gp_app_group="${gp_app_group:-guestportal}"
gp_repo="${gp_repo:-https://github.com/bon1wheel636/guest-portal.git}"
GP_SETUP_MODE="${GP_SETUP_MODE:-fresh}"

run_as_app_user() {
  su -s /bin/bash -c "$1" "${gp_app_user}"
}

gp_ensure_git_safe_directory() {
  run_as_app_user "git config --global --add safe.directory '${gp_app_dir}'" 2>/dev/null || true
}

gp_read_existing_room_count() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/storage.json';
    if (!fs.existsSync(path)) process.stdout.write('0');
    else {
      try {
        var rooms = JSON.parse(fs.readFileSync(path, 'utf8')).rooms;
        process.stdout.write(String(Array.isArray(rooms) ? rooms.length : 0));
      } catch (e) {
        process.stdout.write('0');
      }
    }
  "
}

gp_read_existing_guest_history_count() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/storage.json';
    if (!fs.existsSync(path)) process.stdout.write('0');
    else {
      try {
        var guests = JSON.parse(fs.readFileSync(path, 'utf8')).guests;
        process.stdout.write(String(Array.isArray(guests) ? guests.length : 0));
      } catch (e) {
        process.stdout.write('0');
      }
    }
  "
}

gp_list_existing_rooms() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/storage.json';
    if (!fs.existsSync(path)) process.exit(0);
    try {
      var rooms = JSON.parse(fs.readFileSync(path, 'utf8')).rooms || [];
      rooms.forEach(function(room, index) {
        console.log((index + 1) + '. ' + room.name + ' — ' + room.dashboardUrl);
      });
    } catch (e) {}
  "
}

gp_read_existing_admin_user() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/config.json';
    if (!fs.existsSync(path)) {
      process.stdout.write('admin');
      process.exit(0);
    }
    try {
      var config = JSON.parse(fs.readFileSync(path, 'utf8'));
      process.stdout.write(config.adminUser || 'admin');
    } catch (e) {
      process.stdout.write('admin');
    }
  "
}

gp_read_upload_path() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/config.json';
    if (!fs.existsSync(path)) {
      process.stdout.write('${gp_app_dir}/uploads (default local storage)');
      process.exit(0);
    }
    try {
      var uploadDir = JSON.parse(fs.readFileSync(path, 'utf8')).uploadDir || '';
      process.stdout.write(uploadDir || '${gp_app_dir}/uploads (default local storage)');
    } catch (e) {
      process.stdout.write('${gp_app_dir}/uploads (default local storage)');
    }
  "
}

gp_admin_credentials_configured() {
  node -e "
    var fs = require('fs');
    var path = '${gp_config_dir}/config.json';
    if (!fs.existsSync(path)) process.exit(1);
    try {
      var hash = JSON.parse(fs.readFileSync(path, 'utf8')).adminHash;
      if (hash && hash !== '<bcrypt_hash_placeholder>') process.exit(0);
    } catch (e) {}
    process.exit(1);
  "
}

gp_existing_install_detected() {
  [[ -f "${gp_config_dir}/config.json" || -f "${gp_config_dir}/storage.json" ]] && return 0
  [[ -d "${gp_app_dir}/.git" && -f /etc/systemd/system/guest-portal.service ]] && return 0
  return 1
}

gp_service_status_label() {
  if systemctl is-active guest-portal >/dev/null 2>&1; then
    echo "running"
  elif systemctl is-enabled guest-portal >/dev/null 2>&1; then
    echo "installed (not running)"
  elif [[ -f /etc/systemd/system/guest-portal.service ]]; then
    echo "service file present"
  else
    echo "not installed"
  fi
}

gp_show_existing_install_summary() {
  local room_count guest_count admin_user admin_status upload_path service_status
  room_count=$(gp_read_existing_room_count)
  guest_count=$(gp_read_existing_guest_history_count)
  admin_user=$(gp_read_existing_admin_user)
  upload_path=$(gp_read_upload_path)
  service_status=$(gp_service_status_label)

  if gp_admin_credentials_configured; then
    admin_status="configured (${admin_user})"
  else
    admin_status="not configured (web setup required)"
  fi

  echo -e "${TAB}${BOLD}Current install summary${CL}"
  echo -e "${TAB}  App path:        ${gp_app_dir}"
  echo -e "${TAB}  Rooms:           ${room_count}"
  echo -e "${TAB}  Guest history:   ${guest_count} registration entr$( [[ "$guest_count" == "1" ]] && echo y || echo ies )"
  echo -e "${TAB}  Admin account:   ${admin_status}"
  echo -e "${TAB}  Upload storage:  ${upload_path}"
  echo -e "${TAB}  Service:         ${service_status}"
}

gp_prompt_install_recovery_menu() {
  header_info
  echo -e "${TAB}${BOLD}Existing Guest Portal Install Detected${CL}"
  echo ""
  gp_show_existing_install_summary
  echo ""
  echo -e "${INFO}${YW}Choose how to proceed:${CL}"
  echo ""
  echo -e "${TAB}  1)  Continue setup — keep or review existing config (default)"
  echo -e "${TAB}  2)  Rebuild install — wipe config and run a completely fresh install"
  echo -e "${TAB}  3)  Reset admin account only"
  echo -e "${TAB}  4)  Reset rooms only"
  echo -e "${TAB}  5)  Reset guest sessions and registration history"
  echo -e "${TAB}  6)  Fix permissions and restart service"
  echo -e "${TAB}  7)  Update application code only"
  echo -e "${TAB}  8)  Cancel"
  echo ""
  local choice
  read -p "  Select [1-8] (default: 1): " choice
  choice=${choice:-1}

  case "$choice" in
    2) GP_SETUP_MODE="rebuild" ;;
    3) GP_SETUP_MODE="reset_admin" ;;
    4) GP_SETUP_MODE="reset_rooms" ;;
    5) GP_SETUP_MODE="reset_guests" ;;
    6) GP_SETUP_MODE="repair" ;;
    7) GP_SETUP_MODE="update_only" ;;
    8) GP_SETUP_MODE="cancel" ;;
    *) GP_SETUP_MODE="continue" ;;
  esac
}

gp_confirm_rebuild_install() {
  echo ""
  echo -e "${RD}${BOLD}WARNING:${CL} Rebuild removes Guest Portal configuration, guest sessions,"
  echo -e "${TAB}registration history, and session codes."
  echo -e "${TAB}Uploaded photos are kept unless you choose to delete them."
  echo ""
  if ! prompt_yes_no "  Delete uploaded guest photos as well?" "n"; then
    GP_REBUILD_KEEP_UPLOADS=true
  else
    GP_REBUILD_KEEP_UPLOADS=false
  fi
  echo ""
  read -p "  Type 'rebuild' to confirm a fresh install: " confirm_text
  if [[ "$confirm_text" != "rebuild" ]]; then
    echo -e "${TAB}${RD}Rebuild cancelled.${CL}"
    return 1
  fi
  return 0
}

gp_wipe_install_state() {
  local keep_uploads="${1:-true}"

  systemctl stop guest-portal >/dev/null 2>&1 || true
  rm -rf "${gp_config_dir:?}/"*
  mkdir -p "${gp_config_dir}"

  if [[ "$keep_uploads" == "true" ]]; then
    mkdir -p "${gp_app_dir}/uploads/backgrounds"
  else
    rm -rf "${gp_app_dir}/uploads"
    mkdir -p "${gp_app_dir}/uploads/backgrounds"
  fi
}

gp_reset_application_code() {
  local force_reclone="${1:-false}"
  local keep_uploads="${2:-false}"
  local uploads_backup=""

  if [[ "$force_reclone" == "true" && "$keep_uploads" == "true" && -d "${gp_app_dir}/uploads" ]]; then
    uploads_backup="$(mktemp -d)"
    cp -a "${gp_app_dir}/uploads/." "${uploads_backup}/"
  fi

  if [[ "$force_reclone" == "true" || ! -d "${gp_app_dir}/.git" ]]; then
    msg_info "Replacing application directory"
    rm -rf "${gp_app_dir}"
    if ! git clone "${gp_repo}" "${gp_app_dir}" >/dev/null 2>&1; then
      [[ -n "$uploads_backup" ]] && rm -rf "$uploads_backup"
      msg_error "Failed to clone Guest Portal repository into ${gp_app_dir}"
      return 1
    fi
    if [[ -n "$uploads_backup" ]]; then
      mkdir -p "${gp_app_dir}/uploads"
      cp -a "${uploads_backup}/." "${gp_app_dir}/uploads/"
      rm -rf "$uploads_backup"
    fi
    chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}"
    msg_ok "Application re-cloned"
  else
    msg_info "Resetting application checkout"
    chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}"
    gp_ensure_git_safe_directory
    run_as_app_user "cd '${gp_app_dir}' && git fetch origin" >/dev/null 2>&1 || true
    run_as_app_user "cd '${gp_app_dir}' && git reset --hard origin/main" >/dev/null 2>&1 \
      || run_as_app_user "cd '${gp_app_dir}' && git reset --hard HEAD" >/dev/null 2>&1 \
      || true
    run_as_app_user "cd '${gp_app_dir}' && git clean -fd -e uploads" >/dev/null 2>&1 || true
    msg_ok "Application checkout reset"
  fi

  msg_info "Installing Node.js dependencies"
  if ! su -s /bin/bash -c "cd '${gp_app_dir}' && npm install" "${gp_app_user}" >/dev/null 2>&1; then
    msg_error "npm install failed in ${gp_app_dir}"
    return 1
  fi
  mkdir -p "${gp_app_dir}/uploads/backgrounds"
  chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}/uploads" "${gp_config_dir}" 2>/dev/null || true
  msg_ok "Node.js dependencies installed"
}

gp_update_application_code() {
  if command -v updateguest >/dev/null 2>&1; then
    updateguest -y
    return 0
  fi

  msg_info "Updating application code"
  chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}" "${gp_config_dir}"
  su -s /bin/bash -c "cd '${gp_app_dir}' && git pull --ff-only && npm install" "${gp_app_user}"
  mkdir -p "${gp_app_dir}/uploads/backgrounds"
  chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}" "${gp_config_dir}"
  msg_ok "Application code updated"
  systemctl restart guest-portal >/dev/null 2>&1 || true
}

gp_fix_permissions() {
  msg_info "Fixing ownership and permissions"
  mkdir -p "${gp_config_dir}" "${gp_app_dir}/uploads/backgrounds"
  chown -R "${gp_app_user}:${gp_app_group}" "${gp_config_dir}" "${gp_app_dir}/uploads"
  if [[ -d "${gp_app_dir}/.git" ]]; then
    chown -R "${gp_app_user}:${gp_app_group}" "${gp_app_dir}"
  fi
  msg_ok "Ownership and permissions fixed"
}

gp_install_systemd_service() {
  cat > /etc/systemd/system/guest-portal.service << UNIT
[Unit]
Description=Guest Portal Node.js Server
After=network.target

[Service]
Type=simple
User=${gp_app_user}
Group=${gp_app_group}
WorkingDirectory=${gp_app_dir}
ExecStart=/usr/bin/env node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=${gp_config_dir} ${gp_app_dir}/uploads /mnt

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable guest-portal >/dev/null 2>&1
}

gp_restart_service() {
  systemctl restart guest-portal >/dev/null 2>&1 || systemctl start guest-portal >/dev/null 2>&1 || true
}

gp_validate_admin_username() {
  local username="$1"
  username="${username// /}"
  if [[ -z "$username" ]]; then
    username="admin"
  fi
  if ! [[ "$username" =~ ^[a-zA-Z0-9_-]{3,50}$ ]]; then
    return 1
  fi
  ADMIN_USER="$username"
  return 0
}

gp_prompt_admin_password() {
  while true; do
    read -sp "  Admin password: " ADMIN_PASS
    echo
    read -sp "  Confirm password: " ADMIN_PASS_CONFIRM
    echo
    if [[ "$ADMIN_PASS" == "$ADMIN_PASS_CONFIRM" ]]; then
      break
    fi
    echo -e "${TAB}${RD}Passwords do not match. Try again.${CL}"
  done
}

gp_hash_admin_password() {
  local password="$1"
  ADMIN_PASS="$password" node -e 'require("bcrypt").hash(process.env.ADMIN_PASS,10).then(console.log)'
}

gp_prompt_new_admin_credentials() {
  read -p "  Admin username (default: admin): " input_user
  input_user=${input_user:-admin}
  if ! gp_validate_admin_username "$input_user"; then
    echo -e "${TAB}${RD}Username must be 3-50 characters: letters, numbers, underscore, hyphen only.${CL}"
    return 1
  fi

  gp_prompt_admin_password
  msg_info "Hashing admin password"
  ADMIN_HASH=$(gp_hash_admin_password "$ADMIN_PASS")
  msg_ok "Admin credentials configured (${ADMIN_USER})"
  return 0
}

gp_prompt_admin_reset_only() {
  ADMIN_USER=""
  ADMIN_HASH=""
  ADMIN_ACTION="reset"

  header_info
  echo -e "${TAB}${BOLD}Reset Admin Account${CL}"
  echo ""
  if gp_admin_credentials_configured; then
    echo -e "${CM}${GN}Current admin user: ${BOLD}$(gp_read_existing_admin_user)${CL}"
  else
    echo -e "${INFO}${YW}Admin account is not configured yet.${CL}"
  fi
  echo ""
  echo -e "${TAB}  1)  Set a new username and password now"
  echo -e "${TAB}  2)  Reset for web UI setup on next visit"
  echo ""
  local admin_choice
  read -p "  Select [1/2] (default: 2): " admin_choice
  admin_choice=${admin_choice:-2}

  if [[ "$admin_choice" == "1" ]]; then
    ADMIN_ACTION="replace"
    gp_prompt_new_admin_credentials || return 1
  else
    ADMIN_ACTION="reset"
    ADMIN_USER="admin"
    echo -e "${CM}${GN}Admin account reset for web UI setup.${CL}"
  fi
}

gp_prompt_room_configuration() {
  SKIP_ROOM_SETUP=false
  ROOMS=()

  header_info
  echo -e "${TAB}${BOLD}Guest Room Configuration${CL}"
  echo ""
  echo -e "${INFO}${YW}Configure rooms with Home Assistant dashboard URLs.${CL}"
  echo -e "${TAB}  You can also add/remove rooms later from the Admin panel."
  echo ""

  local existing_room_count
  existing_room_count=$(gp_read_existing_room_count)

  if [[ "$GP_SETUP_MODE" != "reset_rooms" && "$existing_room_count" -gt 0 ]]; then
    echo -e "${CM}${GN}${existing_room_count} existing room(s) found:${CL}"
    while IFS= read -r room_line; do
      [[ -n "$room_line" ]] && echo -e "${TAB}  ${room_line}"
    done < <(gp_list_existing_rooms)
    echo ""
    echo -e "${TAB}  1)  Keep existing rooms (skip setup)"
    echo -e "${TAB}  2)  Reconfigure rooms now"
    echo ""
    local room_choice
    read -p "  Select [1/2] (default: 1): " room_choice
    room_choice=${room_choice:-1}

    if [[ "$room_choice" == "1" ]]; then
      SKIP_ROOM_SETUP=true
      echo -e "${CM}${GN}${existing_room_count} room(s) found — skipping guest room setup.${CL}"
      return 0
    fi
  elif [[ "$GP_SETUP_MODE" == "reset_rooms" && "$existing_room_count" -gt 0 ]]; then
    echo -e "${CM}${GN}${existing_room_count} existing room(s) will be replaced.${CL}"
    if prompt_yes_no "  Also clear guest registration history?" "n"; then
      GP_CLEAR_GUEST_HISTORY=true
    fi
    echo ""
  fi

  local room_count
  read -p "  Number of guest rooms to configure now (default: 2): " room_count
  room_count=${room_count:-2}

  local i room_name room_url room_json
  for (( i=1; i<=room_count; i++ )); do
    echo ""
    read -p "  Room ${i} name: " room_name
    read -p "  Room ${i} dashboard URL: " room_url
    room_json=$(ROOM_NAME="$room_name" ROOM_URL="$room_url" node -e "console.log(JSON.stringify({name:process.env.ROOM_NAME,dashboardUrl:process.env.ROOM_URL}))")
    ROOMS+=("$room_json")
  done
}

gp_prompt_admin_configuration() {
  ADMIN_USER=""
  ADMIN_HASH=""
  ADMIN_ACTION="skip"

  header_info
  echo -e "${TAB}${BOLD}Admin Account Setup${CL}"
  echo ""

  if gp_admin_credentials_configured; then
    local existing_admin_user
    existing_admin_user=$(gp_read_existing_admin_user)
    echo -e "${CM}${GN}Admin credentials found for user: ${BOLD}${existing_admin_user}${CL}"
    echo ""
    echo -e "${TAB}  1)  Keep existing credentials"
    echo -e "${TAB}  2)  Replace username and password"
    echo -e "${TAB}  3)  Reset — configure via web UI on next visit"
    echo ""
    local admin_choice
    read -p "  Select [1/2/3] (default: 1): " admin_choice
    admin_choice=${admin_choice:-1}

    case "$admin_choice" in
      2)
        ADMIN_ACTION="replace"
        gp_prompt_new_admin_credentials || return 1
        ;;
      3)
        ADMIN_ACTION="reset"
        ADMIN_USER="admin"
        echo -e "${CM}${GN}Admin credentials will be reset for web UI setup.${CL}"
        ;;
      *)
        ADMIN_ACTION="keep"
        ADMIN_USER="$existing_admin_user"
        echo -e "${CM}${GN}Keeping existing admin credentials for ${BOLD}${existing_admin_user}${CL}"
        ;;
    esac
    return 0
  fi

  echo -e "${INFO}${YW}Set the admin username and password for the admin panel.${CL}"
  echo -e "${TAB}  You can also skip this and set up via the web UI on first visit."
  echo ""
  echo -e "${TAB}  1)  Set credentials now"
  echo -e "${TAB}  2)  Skip — configure via web UI later"
  echo ""
  local admin_choice
  read -p "  Select [1/2] (default: 1): " admin_choice
  admin_choice=${admin_choice:-1}

  if [[ "$admin_choice" == "1" ]]; then
    ADMIN_ACTION="replace"
    gp_prompt_new_admin_credentials || return 1
  else
    ADMIN_ACTION="skip"
    echo -e "${CM}${GN}Admin setup skipped — use the web UI on first visit to /admin.html.${CL}"
  fi
}

gp_reset_guest_sessions_and_history() {
  local clear_history="${1:-false}"

  echo '{}' > "${gp_config_dir}/sessions.json"
  echo '{}' > "${gp_config_dir}/guest-tokens.json"

  if [[ "$clear_history" == "true" ]]; then
    node -e "
      var fs = require('fs');
      var path = '${gp_config_dir}/storage.json';
      var storage = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : { rooms: [], guests: [] };
      if (!Array.isArray(storage.rooms)) storage.rooms = [];
      storage.guests = [];
      fs.writeFileSync(path, JSON.stringify(storage, null, 2));
    "
  fi
}

gp_write_setup_config_files() {
  mkdir -p "$gp_config_dir"

  case "$ADMIN_ACTION" in
    replace)
      ADMIN_USER="$ADMIN_USER" ADMIN_HASH="$ADMIN_HASH" node -e "
        var fs = require('fs');
        var path = '${gp_config_dir}/config.json';
        var config = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : {};
        config.adminUser = process.env.ADMIN_USER;
        config.adminHash = process.env.ADMIN_HASH;
        if (config.uploadDir === undefined) config.uploadDir = '';
        if (!config.sessionExpirationMinutes) config.sessionExpirationMinutes = 10;
        if (!config.adminSessionTimeoutMinutes) config.adminSessionTimeoutMinutes = 15;
        fs.writeFileSync(path, JSON.stringify(config, null, 2));
      "
      ;;
    reset)
      node -e "
        var fs = require('fs');
        var path = '${gp_config_dir}/config.json';
        var config = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : {};
        config.adminUser = 'admin';
        config.adminHash = '<bcrypt_hash_placeholder>';
        if (config.uploadDir === undefined) config.uploadDir = '';
        if (!config.sessionExpirationMinutes) config.sessionExpirationMinutes = 10;
        if (!config.adminSessionTimeoutMinutes) config.adminSessionTimeoutMinutes = 15;
        fs.writeFileSync(path, JSON.stringify(config, null, 2));
      "
      ;;
    keep)
      node -e "
        var fs = require('fs');
        var path = '${gp_config_dir}/config.json';
        if (!fs.existsSync(path)) {
          fs.writeFileSync(path, JSON.stringify({
            adminUser: 'admin',
            adminHash: '<bcrypt_hash_placeholder>',
            uploadDir: '',
            sessionExpirationMinutes: 10,
            adminSessionTimeoutMinutes: 15
          }, null, 2));
        }
      "
      ;;
    skip)
      node -e "
        var fs = require('fs');
        var path = '${gp_config_dir}/config.json';
        if (!fs.existsSync(path)) {
          fs.writeFileSync(path, JSON.stringify({
            adminUser: 'admin',
            adminHash: '<bcrypt_hash_placeholder>',
            uploadDir: '',
            sessionExpirationMinutes: 10,
            adminSessionTimeoutMinutes: 15
          }, null, 2));
        }
      "
      ;;
  esac

  if [[ "$SKIP_ROOM_SETUP" == "true" ]]; then
    node -e "
      var fs = require('fs');
      var path = '${gp_config_dir}/storage.json';
      if (!fs.existsSync(path)) {
        fs.writeFileSync(path, JSON.stringify({ rooms: [], guests: [] }, null, 2));
      }
    "
  else
    local rooms_json
    rooms_json=$(ROOM_DATA="$(printf '%s\n' "${ROOMS[@]}")" node -e "
      var rooms = process.env.ROOM_DATA.trim().split('\n').filter(Boolean);
      console.log(JSON.stringify(rooms.map(function(room) { return JSON.parse(room); })));
    ")
    CLEAR_GUEST_HISTORY="${GP_CLEAR_GUEST_HISTORY:-false}" ROOMS_JSON="$rooms_json" node -e "
      var fs = require('fs');
      var path = '${gp_config_dir}/storage.json';
      var storage = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : { rooms: [], guests: [] };
      if (!Array.isArray(storage.guests)) storage.guests = [];
      if (process.env.CLEAR_GUEST_HISTORY === 'true') storage.guests = [];
      storage.rooms = JSON.parse(process.env.ROOMS_JSON);
      fs.writeFileSync(path, JSON.stringify(storage, null, 2));
    "
  fi

  [[ -f "${gp_config_dir}/sessions.json" ]] || echo '{}' > "${gp_config_dir}/sessions.json"
  [[ -f "${gp_config_dir}/guest-tokens.json" ]] || echo '{}' > "${gp_config_dir}/guest-tokens.json"
  chown -R "${gp_app_user}:${gp_app_group}" "$gp_config_dir" "${gp_app_dir}/uploads"
}

gp_admin_login_message() {
  case "$ADMIN_ACTION" in
    replace|keep)
      if [[ -n "$ADMIN_USER" ]]; then
        echo -e "${CM}${GN}Admin login username: ${BOLD}${ADMIN_USER}${CL}"
      fi
      ;;
    reset|skip)
      echo -e "${INFO}${YW}Visit /admin.html to create your admin account on first login.${CL}"
      ;;
  esac
}

gp_print_recovery_result() {
  local title="$1"
  header_info
  echo -e "${CM}${GN}${BOLD}${title}${CL}"
  echo ""
  gp_show_existing_install_summary
  echo ""
  gp_admin_login_message
}

gp_handle_reset_guests_mode() {
  header_info
  echo -e "${TAB}${BOLD}Reset Guest Sessions and History${CL}"
  echo ""
  gp_show_existing_install_summary
  echo ""
  echo -e "${INFO}${YW}This clears active guest sessions, device tokens, and pending session codes.${CL}"
  local clear_history=false
  if prompt_yes_no "  Also clear registration history?" "y"; then
    clear_history=true
  fi

  msg_info "Resetting guest session data"
  gp_reset_guest_sessions_and_history "$clear_history"
  gp_fix_permissions
  gp_restart_service
  msg_ok "Guest session data reset"

  gp_print_recovery_result "Guest session data reset complete."
}

gp_handle_repair_mode() {
  msg_info "Repairing install"
  gp_fix_permissions
  gp_install_systemd_service
  gp_restart_service
  msg_ok "Install repaired"

  ADMIN_ACTION="keep"
  ADMIN_USER="$(gp_read_existing_admin_user)"
  gp_print_recovery_result "Install repair complete."
}

gp_handle_update_only_mode() {
  gp_update_application_code
  echo ""
  gp_print_recovery_result "Application code update complete."
}

gp_handle_reset_admin_mode() {
  gp_prompt_admin_reset_only || return 1
  msg_info "Updating admin account"
  gp_write_setup_config_files
  gp_fix_permissions
  gp_install_systemd_service
  gp_restart_service
  msg_ok "Admin account updated"
  gp_print_recovery_result "Admin account reset complete."
}

gp_handle_reset_rooms_mode() {
  GP_CLEAR_GUEST_HISTORY=false
  gp_prompt_room_configuration || return 1
  ADMIN_ACTION="keep"
  ADMIN_USER="$(gp_read_existing_admin_user)"
  msg_info "Updating rooms"
  gp_write_setup_config_files
  gp_fix_permissions
  gp_restart_service
  msg_ok "Rooms updated"
  gp_print_recovery_result "Room configuration reset complete."
}
