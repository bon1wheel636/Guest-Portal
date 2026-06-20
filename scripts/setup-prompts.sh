#!/usr/bin/env bash
# Shared setup prompts for Guest Portal installers.
# Sourced by setup-container.sh after the app repository is present.

gp_config_dir="${gp_config_dir:-/etc/guest-portal}"

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

  if [[ "$existing_room_count" -gt 0 ]]; then
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
        if ! gp_prompt_new_admin_credentials; then
          return 1
        fi
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
    if ! gp_prompt_new_admin_credentials; then
      return 1
    fi
  else
    ADMIN_ACTION="skip"
    echo -e "${CM}${GN}Admin setup skipped — use the web UI on first visit to /admin.html.${CL}"
  fi
}

gp_write_setup_config_files() {
  local app_user="${1:-guestportal}"
  local app_group="${2:-guestportal}"
  local app_uploads_dir="${3:-/opt/guest-portal/uploads}"

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
    ROOMS_JSON="$rooms_json" node -e "
      var fs = require('fs');
      var path = '${gp_config_dir}/storage.json';
      var storage = fs.existsSync(path) ? JSON.parse(fs.readFileSync(path, 'utf8')) : { rooms: [], guests: [] };
      if (!Array.isArray(storage.guests)) storage.guests = [];
      storage.rooms = JSON.parse(process.env.ROOMS_JSON);
      fs.writeFileSync(path, JSON.stringify(storage, null, 2));
    "
  fi

  [[ -f "${gp_config_dir}/sessions.json" ]] || echo '{}' > "${gp_config_dir}/sessions.json"
  [[ -f "${gp_config_dir}/guest-tokens.json" ]] || echo '{}' > "${gp_config_dir}/guest-tokens.json"
  chown -R "${app_user}:${app_group}" "$gp_config_dir" "$app_uploads_dir"
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
