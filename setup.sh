#!/usr/bin/env bash
# Guest Portal LXC Setup Script
# https://github.com/bon1wheel636/guest-portal

set -euo pipefail

# ─── Colors & Formatting ───────────────────────────────────────────────────

YW="\033[33m"
BL="\033[36m"
RD="\033[01;31m"
GN="\033[1;92m"
DGN="\033[32m"
BGN="\033[4;92m"
CL="\033[m"
BOLD="\033[1m"
TAB="  "
CM="${TAB}✔️${TAB}"
CROSS="${TAB}✖${TAB}"
INFO="${TAB}💡${TAB}"
CONTAINERID="${TAB}🆔${TAB}"
HOSTNAME_ICON="${TAB}🏠${TAB}"
DISKSIZE="${TAB}💾${TAB}"
CPUCORE="${TAB}🧠${TAB}"
RAMSIZE="${TAB}🛠️${TAB}"
BRIDGE_ICON="${TAB}🌉${TAB}"
NETWORK="${TAB}📡${TAB}"
GATEWAY="${TAB}🌐${TAB}"
CREATING="${TAB}🚀${TAB}"
STORAGE="${TAB}📸${TAB}"
PROXY="${TAB}🔒${TAB}"

msg_info() { echo -ne "${TAB}⏳${TAB}${YW}${1}...${CL}"; }
msg_ok() { echo -e "\r${CM}${GN}${1}${CL}"; }
msg_error() { echo -e "\r${CROSS}${RD}${1}${CL}" >&2; }

DRY_RUN=false
UPDATE_MODE=false
UPDATE_CT_ID=""

usage() {
  echo "Usage: bash install.sh [--branch <name>] [--dry-run] [--update [ctid]]"
  echo "       bash setup.sh [--dry-run] [--update [ctid]]"
  echo ""
  echo "  On Proxmox, prefer install.sh so git is not required on the host:"
  echo "    bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)\""
  echo ""
  echo "  --dry-run       Show the selected plan and stop before making changes"
  echo "  --update [ctid] Update an existing Guest Portal LXC instead of creating a new one"
  echo "  --help          Show this help"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --update)
      UPDATE_MODE=true
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        UPDATE_CT_ID="$2"
        shift 2
      else
        shift
      fi
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      msg_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

header_info() {
  clear
  echo -e "${BL}"
  echo '   ____                 _     ____            _        _ '
  echo '  / ___|_   _  ___  ___| |_  |  _ \ ___  _ __| |_ __ _| |'
  echo ' | |  _| | | |/ _ \/ __| __| | |_) / _ \|  __| __/ _` | |'
  echo ' | |_| | |_| |  __/\__ \ |_  |  __/ (_) | |  | || (_| | |'
  echo '  \____|\__,_|\___||___/\__| |_|   \___/|_|   \__\__,_|_|'
  echo -e "${CL}"
  echo -e "${TAB}${DGN}Proxmox LXC Installer${CL}"
  echo ""
}

# ─── Pre-flight Checks ─────────────────────────────────────────────────────

header_info

if [[ "$(id -u)" -ne 0 ]]; then
  msg_error "This script must be run as root on a Proxmox host."
  exit 1
fi

if ! command -v pct &>/dev/null; then
  msg_error "pct command not found. Run this script on a Proxmox host."
  exit 1
fi

# ─── Defaults ───────────────────────────────────────────────────────────────

var_hostname="guest-portal"
var_cpu=1
var_ram=512
var_disk=4
var_bridge="vmbr0"
var_net="dhcp"
var_os_template="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"
var_rootfs_storage="local-lvm"
var_repo="https://github.com/bon1wheel636/guest-portal.git"
var_repo_raw="https://raw.githubusercontent.com/bon1wheel636/guest-portal/main"
var_app_dir="/opt/guest-portal"
var_app_user="guestportal"
var_app_group="guestportal"
var_unprivileged=1

install_updateguest_command() {
  local target_ct="$1"
  pct exec "$target_ct" -- bash -c "
    if [ -f '${var_app_dir}/scripts/updateguest.sh' ]; then
      install -m 755 '${var_app_dir}/scripts/updateguest.sh' /usr/local/bin/updateguest
    fi
  " >/dev/null 2>&1
}

resolve_script_dir() {
  local source="${BASH_SOURCE[0]}"
  if [[ -n "$source" && -f "$source" ]]; then
    cd "$(dirname "$source")" && pwd
    return 0
  fi
  return 1
}

fetch_nginx_template() {
  local dest="$1"
  local script_dir=""
  if script_dir="$(resolve_script_dir)" && [[ -f "${script_dir}/nginx/guestportal.conf" ]]; then
    cp "${script_dir}/nginx/guestportal.conf" "$dest"
    return 0
  fi
  curl -fsSL "${var_repo_raw}/nginx/guestportal.conf" -o "$dest"
}

detect_os_template() {
  local template=""
  if command -v pveam >/dev/null 2>&1; then
    template=$(pveam list local 2>/dev/null | awk '/debian-12-standard/ {print $1; exit}')
  fi
  if [[ -n "$template" ]]; then
    var_os_template="$template"
    return 0
  fi

  msg_error "No Debian 12 LXC template found on this Proxmox node."
  echo "" >&2
  echo -e "${INFO}${YW}Download a template, then rerun the installer:${CL}" >&2
  echo -e "${TAB}  pveam update" >&2
  echo -e "${TAB}  pveam available | grep debian-12" >&2
  echo -e "${TAB}  pveam download local debian-12-standard" >&2
  echo -e "${TAB}  pveam list local" >&2
  exit 1
}

detect_rootfs_storage() {
  local candidate=""
  for candidate in local-lvm local-zfs; do
    if pvesm status 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$candidate"; then
      var_rootfs_storage="$candidate"
      return 0
    fi
  done

  msg_error "Could not find container rootfs storage (expected local-lvm or local-zfs)."
  echo "" >&2
  echo -e "${INFO}${YW}Check available storage:${CL}" >&2
  echo -e "${TAB}  pvesm status" >&2
  exit 1
}

validate_bridge() {
  local bridge="$1"
  if ip link show "$bridge" &>/dev/null; then
    return 0
  fi

  msg_error "Network bridge '${bridge}' was not found on this host."
  echo "" >&2
  echo -e "${INFO}${YW}Available bridges:${CL}" >&2
  ip -br link show type bridge 2>/dev/null | awk '{print "    " $1}' >&2 || true
  exit 1
}

ensure_ct_id_available() {
  local ct_id="$1"
  if pct status "$ct_id" &>/dev/null; then
    msg_error "Container ID ${ct_id} is already in use."
    echo -e "${TAB}  pct list" >&2
    exit 1
  fi
}

print_pct_create_help() {
  echo "" >&2
  echo -e "${INFO}${YW}Common fixes:${CL}" >&2
  echo -e "${TAB}  pveam update && pveam download local debian-12-standard" >&2
  echo -e "${TAB}  pveam list local" >&2
  echo -e "${TAB}  pvesm status" >&2
  echo -e "${TAB}  ip -br link show type bridge" >&2
  echo -e "${TAB}  pct list" >&2
}

run_pct_create() {
  local ct_id="$1"
  shift
  local output=""

  if output=$(pct create "$ct_id" "$@" 2>&1); then
    return 0
  fi

  msg_error "Failed to create LXC container ${ct_id}"
  echo "$output" >&2
  print_pct_create_help
  exit 1
}

run_pct_start() {
  local ct_id="$1"
  local output=""

  if output=$(pct start "$ct_id" 2>&1); then
    return 0
  fi

  msg_error "Failed to start LXC container ${ct_id}"
  echo "$output" >&2
  exit 1
}

# Auto-detect next available CT ID
NEXT_ID=$(pvesh get /cluster/nextid 2>/dev/null || echo "100")

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local answer
  read -p "${prompt} [y/n] (default: ${default}): " answer
  answer=${answer:-$default}
  [[ "${answer,,}" == "y" ]]
}

detect_existing_installs() {
  pct list 2>/dev/null | awk -v name="$var_hostname" 'NR > 1 && $4 == name { print $1 }'
}

select_existing_ct() {
  local existing_ids="$1"
  if [[ -n "$UPDATE_CT_ID" ]]; then
    echo "$UPDATE_CT_ID"
    return
  fi

  if [[ -n "$existing_ids" ]]; then
    echo "$existing_ids" | awk 'NR == 1 { print; exit }'
    return
  fi

  read -p "  Existing container ID to update: " UPDATE_CT_ID
  echo "$UPDATE_CT_ID"
}

update_existing_install() {
  local target_ct="$1"

  if ! pct status "$target_ct" >/dev/null 2>&1; then
    msg_error "Container ${target_ct} was not found."
    exit 1
  fi

  header_info
  echo -e "${TAB}${BOLD}Update Existing Guest Portal Install${CL}"
  echo ""
  echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}${target_ct}${CL}"
  echo -e "${INFO}${YW}The updater prompts before code, service, app state, NAS path, or restart changes.${CL}"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${TAB}${BOLD}Dry run only. Planned checks:${CL}"
    echo -e "${TAB}  - Detect app path (${var_app_dir} or legacy /root/guest-portal)"
    echo -e "${TAB}  - Update git checkout and npm dependencies if approved"
    echo -e "${TAB}  - Ensure ${var_app_user} service user and ownership if approved"
    echo -e "${TAB}  - Rewrite hardened systemd service if approved"
    echo -e "${TAB}  - Optionally validate and set a NAS upload path"
    echo -e "${TAB}  - Restart guest-portal only if approved"
    exit 0
  fi

  if prompt_yes_no "  Update application code and npm dependencies?" "y"; then
    msg_info "Updating application code"
    pct exec "$target_ct" -- bash -c "
      set -e
      groupadd --system '${var_app_group}' 2>/dev/null || true
      id -u '${var_app_user}' >/dev/null 2>&1 || useradd --system --gid '${var_app_group}' --home-dir '${var_app_dir}' --shell /usr/sbin/nologin '${var_app_user}'
      mkdir -p '${var_app_dir}' /etc/guest-portal
      if [ -d '${var_app_dir}/.git' ]; then
        true
      elif [ -d '/root/guest-portal/.git' ]; then
        cp -a /root/guest-portal/. '${var_app_dir}/'
      else
        git clone '${var_repo}' '${var_app_dir}'
      fi
      chown -R '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
      su -s /bin/bash -c \"cd '${var_app_dir}' && git pull --ff-only && npm install\" '${var_app_user}'
      mkdir -p '${var_app_dir}/uploads/backgrounds'
      chown -R '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
    " >/dev/null 2>&1
    install_updateguest_command "$target_ct"
    msg_ok "Application code updated"
  fi

  if prompt_yes_no "  Install or refresh the in-container updateguest command?" "y"; then
    msg_info "Installing updateguest command"
    install_updateguest_command "$target_ct"
    msg_ok "updateguest command installed"
  fi

  if prompt_yes_no "  Initialize missing state files and fix /etc/guest-portal ownership?" "y"; then
    msg_info "Updating app state ownership"
    pct exec "$target_ct" -- bash -c "
      mkdir -p /etc/guest-portal
      [ -f /etc/guest-portal/sessions.json ] || echo '{}' > /etc/guest-portal/sessions.json
      [ -f /etc/guest-portal/guest-tokens.json ] || echo '{}' > /etc/guest-portal/guest-tokens.json
      chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal
    " >/dev/null 2>&1
    msg_ok "App state ownership updated"
  fi

  if prompt_yes_no "  Rewrite hardened systemd service?" "y"; then
    msg_info "Writing systemd service"
    pct exec "$target_ct" -- bash -c "
cat > /etc/systemd/system/guest-portal.service << 'UNIT'
[Unit]
Description=Guest Portal Node.js Server
After=network.target

[Service]
Type=simple
User=${var_app_user}
Group=${var_app_group}
WorkingDirectory=${var_app_dir}
ExecStart=/usr/bin/env node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/etc/guest-portal ${var_app_dir}/uploads /mnt

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload >/dev/null 2>&1
systemctl enable guest-portal >/dev/null 2>&1
    " >/dev/null 2>&1
    msg_ok "Systemd service updated"
  fi

  if prompt_yes_no "  Change upload path to an existing mounted directory?" "n"; then
    read -p "  Existing mounted upload path (default: /mnt/nas/guest-photos): " update_mount
    update_mount=${update_mount:-/mnt/nas/guest-photos}

    if pct exec "$target_ct" -- bash -c "[ -d '${update_mount}' ] && su -s /bin/sh -c 'test -w \"${update_mount}\"' '${var_app_user}'" 2>/dev/null; then
      UPDATE_MOUNT_B64=$(printf '%s' "$update_mount" | base64 -w0)
      msg_info "Updating upload path"
      pct exec "$target_ct" -- bash -c "
        su -s /bin/sh -c 'mkdir -p \"${update_mount}/backgrounds\"' '${var_app_user}'
        export MOUNT_B64=$UPDATE_MOUNT_B64
        node -e 'var fs=require(\"fs\");var c=JSON.parse(fs.readFileSync(\"/etc/guest-portal/config.json\",\"utf8\"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,\"base64\").toString();fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
        chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal
      " >/dev/null 2>&1
      msg_ok "Upload path updated"
    else
      msg_error "Path does not exist or is not writable by ${var_app_user}. Upload path was not changed."
    fi
  fi

  if prompt_yes_no "  Restart guest-portal service now?" "y"; then
    msg_info "Restarting guest-portal"
    pct exec "$target_ct" -- systemctl restart guest-portal >/dev/null 2>&1
    msg_ok "guest-portal restarted"
  fi

  echo ""
  echo -e "${CM}${GN}Existing Guest Portal update complete.${CL}"
  exit 0
}

EXISTING_CT_IDS=$(detect_existing_installs)
if [[ "$UPDATE_MODE" == "true" || -n "$EXISTING_CT_IDS" ]]; then
  if [[ "$UPDATE_MODE" == "true" ]]; then
    UPDATE_TARGET_CT=$(select_existing_ct "$EXISTING_CT_IDS")
    update_existing_install "$UPDATE_TARGET_CT"
  elif prompt_yes_no "Existing ${var_hostname} container(s) found (${EXISTING_CT_IDS//$'\n'/, }). Update one instead of creating a new container?" "y"; then
    UPDATE_TARGET_CT=$(select_existing_ct "$EXISTING_CT_IDS")
    update_existing_install "$UPDATE_TARGET_CT"
  fi
fi

# ─── Settings Selection ────────────────────────────────────────────────────

echo -e "${TAB}${BOLD}How would you like to configure the container?${CL}"
echo ""
echo -e "${TAB}  1)  Use Default Settings"
echo -e "${TAB}  2)  Advanced Settings (customize everything)"
echo ""
read -p "  Select [1/2] (default: 1): " SETTINGS_CHOICE
SETTINGS_CHOICE=${SETTINGS_CHOICE:-1}

CT_ID="$NEXT_ID"
CT_HOSTNAME="$var_hostname"
CT_CPU="$var_cpu"
CT_RAM="$var_ram"
CT_DISK="$var_disk"
CT_BRIDGE="$var_bridge"
CT_NET_STRING=""
CT_IP_DISPLAY="DHCP"
CT_UNPRIVILEGED="$var_unprivileged"
CT_PRIVILEGE_DISPLAY="Unprivileged"

if [[ "$SETTINGS_CHOICE" == "2" ]]; then
  header_info
  echo -e "${TAB}${BOLD}Advanced Container Settings${CL}"
  echo ""

  # CT ID
  read -p "  Container ID (default: ${NEXT_ID}): " input
  CT_ID=${input:-$NEXT_ID}

  # Validate CT ID is not in use
  while pct status "$CT_ID" &>/dev/null; do
    echo -e "${TAB}${RD}CT ID ${CT_ID} is already in use.${CL}"
    read -p "  Container ID: " CT_ID
  done

  # Hostname
  read -p "  Hostname (default: ${var_hostname}): " input
  CT_HOSTNAME=${input:-$var_hostname}

  # Disk Size
  read -p "  Disk Size in GB (default: ${var_disk}): " input
  CT_DISK=${input:-$var_disk}

  # CPU Cores
  read -p "  CPU Cores (default: ${var_cpu}): " input
  CT_CPU=${input:-$var_cpu}

  # RAM
  read -p "  RAM in MiB (default: ${var_ram}): " input
  CT_RAM=${input:-$var_ram}

  # Network Bridge
  echo ""
  echo -e "${TAB}Available bridges:"
  brctl show 2>/dev/null | awk 'NR>1 && $1 != "" {print "    " $1}' || echo "    vmbr0"
  echo ""
  read -p "  Network Bridge (default: ${var_bridge}): " input
  CT_BRIDGE=${input:-$var_bridge}

  # Network: DHCP vs Static
  echo ""
  echo -e "${TAB}IPv4 Configuration:"
  echo -e "${TAB}  1)  DHCP"
  echo -e "${TAB}  2)  Static IP"
  echo ""
  read -p "  Select [1/2] (default: 1): " net_choice
  net_choice=${net_choice:-1}

  if [[ "$net_choice" == "2" ]]; then
    read -p "  Static IP (CIDR, e.g. 192.168.1.100/24): " CT_STATIC_IP
    read -p "  Gateway (e.g. 192.168.1.1): " CT_GATEWAY
    read -p "  DNS Server (default: 1.1.1.1): " CT_DNS
    CT_DNS=${CT_DNS:-"1.1.1.1"}
    CT_NET_STRING="name=eth0,bridge=${CT_BRIDGE},ip=${CT_STATIC_IP},gw=${CT_GATEWAY}"
    CT_IP_DISPLAY="${CT_STATIC_IP}"
  else
    CT_NET_STRING="name=eth0,bridge=${CT_BRIDGE},ip=dhcp"
    CT_IP_DISPLAY="DHCP"
  fi

  # Container privilege mode
  echo ""
  echo -e "${TAB}Container Isolation:"
  echo -e "${TAB}  1)  Unprivileged (recommended)"
  echo -e "${TAB}  2)  Privileged (only if container-managed NFS/SMB mounting requires it)"
  echo ""
  read -p "  Select [1/2] (default: 1): " privilege_choice
  privilege_choice=${privilege_choice:-1}
  if [[ "$privilege_choice" == "2" ]]; then
    CT_UNPRIVILEGED=0
    CT_PRIVILEGE_DISPLAY="Privileged"
  fi
else
  CT_NET_STRING="name=eth0,bridge=${CT_BRIDGE},ip=dhcp"
fi

# ─── Display Summary ───────────────────────────────────────────────────────

header_info
echo -e "${TAB}${BOLD}Container Configuration Summary${CL}"
echo ""
echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}${CT_ID}${CL}"
echo -e "${HOSTNAME_ICON}${BOLD}${DGN}Hostname: ${BGN}${CT_HOSTNAME}${CL}"
echo -e "${DISKSIZE}${BOLD}${DGN}Disk Size: ${BGN}${CT_DISK} GB${CL}"
echo -e "${CPUCORE}${BOLD}${DGN}CPU Cores: ${BGN}${CT_CPU}${CL}"
echo -e "${RAMSIZE}${BOLD}${DGN}RAM Size: ${BGN}${CT_RAM} MiB${CL}"
echo -e "${BRIDGE_ICON}${BOLD}${DGN}Bridge: ${BGN}${CT_BRIDGE}${CL}"
echo -e "${NETWORK}${BOLD}${DGN}IPv4: ${BGN}${CT_IP_DISPLAY}${CL}"
echo -e "${TAB}${BOLD}${DGN}Isolation: ${BGN}${CT_PRIVILEGE_DISPLAY}${CL}"
echo ""
read -p "  Continue with these settings? [y/n] (default: y): " confirm
confirm=${confirm:-y}
if [[ "${confirm,,}" != "y" ]]; then
  echo "Setup cancelled."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo -e "${TAB}${BOLD}Dry run complete. No containers, files, services, or mounts were changed.${CL}"
  echo -e "${TAB}  Planned app path: ${var_app_dir}"
  echo -e "${TAB}  Planned service user: ${var_app_user}"
  echo -e "${TAB}  Planned isolation: ${CT_PRIVILEGE_DISPLAY}"
  exit 0
fi

detect_os_template
detect_rootfs_storage
validate_bridge "$CT_BRIDGE"
ensure_ct_id_available "$CT_ID"

# ─── Create Container ──────────────────────────────────────────────────────

header_info
echo -e "${INFO}${YW}Using template: ${var_os_template}${CL}"
echo -e "${INFO}${YW}Using storage: ${var_rootfs_storage}:${CT_DISK}${CL}"
echo ""
msg_info "Creating LXC container ${CT_ID}"
run_pct_create "$CT_ID" "$var_os_template" \
  --hostname "$CT_HOSTNAME" \
  --cores "$CT_CPU" \
  --memory "$CT_RAM" \
  --net0 "$CT_NET_STRING" \
  --rootfs "${var_rootfs_storage}:${CT_DISK}" \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged "$CT_UNPRIVILEGED"
msg_ok "Created LXC container ${CT_ID}"

msg_info "Starting container"
run_pct_start "$CT_ID"
# Wait for container to be fully running
sleep 3
msg_ok "Started container"

# ─── Install Dependencies Inside Container ──────────────────────────────────

msg_info "Updating OS and installing dependencies"
pct exec "$CT_ID" -- bash -c "
  apt-get update >/dev/null 2>&1 &&
  apt-get install -y git curl nodejs npm >/dev/null 2>&1
" >/dev/null 2>&1
msg_ok "Installed OS dependencies"

# ─── Service User ───────────────────────────────────────────────────────────

msg_info "Creating application service user"
pct exec "$CT_ID" -- bash -c "
  groupadd --system '${var_app_group}' 2>/dev/null || true
  id -u '${var_app_user}' >/dev/null 2>&1 || useradd --system --gid '${var_app_group}' --home-dir '${var_app_dir}' --shell /usr/sbin/nologin '${var_app_user}'
  mkdir -p '${var_app_dir}' /etc/guest-portal
  chown '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
" >/dev/null 2>&1
msg_ok "Application service user ready"

# ─── Clone Repository Inside Container ──────────────────────────────────────

msg_info "Cloning Guest Portal repository"
pct exec "$CT_ID" -- bash -c "
  git clone ${var_repo} '${var_app_dir}' >/dev/null 2>&1
" >/dev/null 2>&1
msg_ok "Cloned repository into container"

msg_info "Installing Node.js dependencies"
pct exec "$CT_ID" -- bash -c "
  cd '${var_app_dir}' && npm install >/dev/null 2>&1
  mkdir -p '${var_app_dir}/uploads/backgrounds'
  chown -R '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
" >/dev/null 2>&1
install_updateguest_command "$CT_ID"
msg_ok "Installed Node.js dependencies"

# ─── Guest Room Configuration ───────────────────────────────────────────────

header_info
echo -e "${TAB}${BOLD}Guest Room Configuration${CL}"
echo ""
echo -e "${INFO}${YW}Configure rooms with Home Assistant dashboard URLs.${CL}"
echo -e "${TAB}  You can also add/remove rooms later from the Admin panel."
echo ""

read -p "  Number of guest rooms to configure now (default: 2): " ROOM_COUNT
ROOM_COUNT=${ROOM_COUNT:-2}

declare -a ROOMS
for (( i=1; i<=ROOM_COUNT; i++ )); do
  echo ""
  read -p "  Room ${i} name: " ROOM_NAME
  read -p "  Room ${i} dashboard URL: " ROOM_URL
  ROOM_JSON=$(ROOM_NAME="$ROOM_NAME" ROOM_URL="$ROOM_URL" node -e "console.log(JSON.stringify({name:process.env.ROOM_NAME,dashboardUrl:process.env.ROOM_URL}))")
  ROOMS+=("$ROOM_JSON")
done

# ─── Admin Credentials ──────────────────────────────────────────────────────

header_info
echo -e "${TAB}${BOLD}Admin Account Setup${CL}"
echo ""
echo -e "${INFO}${YW}Set the admin username and password for the admin panel.${CL}"
echo -e "${TAB}  You can also skip this and set up via the web UI on first visit."
echo ""
echo -e "${TAB}  1)  Set credentials now"
echo -e "${TAB}  2)  Skip — configure via web UI later"
echo ""
read -p "  Select [1/2] (default: 1): " admin_choice
admin_choice=${admin_choice:-1}

ADMIN_USER=""
ADMIN_HASH=""

if [[ "$admin_choice" == "1" ]]; then
  read -p "  Admin username (default: admin): " ADMIN_USER
  ADMIN_USER=${ADMIN_USER:-admin}

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

  msg_info "Hashing admin password"
  ADMIN_PASS_B64=$(printf '%s' "$ADMIN_PASS" | base64 -w0)
  ADMIN_HASH=$(pct exec "$CT_ID" -- bash -c "
    export PASS_B64=$ADMIN_PASS_B64
    node -e 'require(\"bcrypt\").hash(Buffer.from(process.env.PASS_B64,\"base64\").toString(),10).then(console.log)'
  ")
  msg_ok "Admin credentials configured"
fi

# ─── Write Config Files ────────────────────────────────────────────────────

msg_info "Writing configuration files"
pct exec "$CT_ID" -- bash -c "mkdir -p /etc/guest-portal"

# Build rooms JSON
ROOMS_JSON=$(ROOM_DATA="$(printf '%s\n' "${ROOMS[@]}")" node -e "
  var rooms = process.env.ROOM_DATA.trim().split('\n').filter(Boolean);
  console.log(JSON.stringify(rooms.map(function(r) { return JSON.parse(r); })));
")
ROOMS_JSON_B64=$(printf '%s' "$ROOMS_JSON" | base64 -w0)

if [[ -n "$ADMIN_HASH" ]]; then
  ADMIN_USER_B64=$(printf '%s' "$ADMIN_USER" | base64 -w0)
  ADMIN_HASH_B64=$(printf '%s' "$ADMIN_HASH" | base64 -w0)

  pct exec "$CT_ID" -- bash -c "
    if [ ! -f /etc/guest-portal/config.json ]; then
      export USER_B64=$ADMIN_USER_B64 HASH_B64=$ADMIN_HASH_B64
      node -e 'var fs=require(\"fs\");var c={adminUser:Buffer.from(process.env.USER_B64,\"base64\").toString(),adminHash:Buffer.from(process.env.HASH_B64,\"base64\").toString(),uploadDir:\"\",sessionExpirationMinutes:10,adminSessionTimeoutMinutes:15};fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
    else
      echo 'Existing config.json found — skipping overwrite'
    fi
  "
else
  pct exec "$CT_ID" -- bash -c "
    if [ ! -f /etc/guest-portal/config.json ]; then
      node -e 'var fs=require(\"fs\");var c={adminUser:\"admin\",adminHash:\"<bcrypt_hash_placeholder>\",uploadDir:\"\",sessionExpirationMinutes:10,adminSessionTimeoutMinutes:15};fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
    else
      echo 'Existing config.json found — skipping overwrite'
    fi
  "
fi

pct exec "$CT_ID" -- bash -c "
  if [ ! -f /etc/guest-portal/storage.json ]; then
    export ROOMS_B64=$ROOMS_JSON_B64
    node -e 'var fs=require(\"fs\");var s={rooms:JSON.parse(Buffer.from(process.env.ROOMS_B64,\"base64\").toString()),guests:[]};fs.writeFileSync(\"/etc/guest-portal/storage.json\",JSON.stringify(s,null,2))'
  else
    echo 'Existing storage.json found — skipping overwrite'
  fi
"
pct exec "$CT_ID" -- bash -c "
  [ -f /etc/guest-portal/sessions.json ] || echo '{}' > /etc/guest-portal/sessions.json
  [ -f /etc/guest-portal/guest-tokens.json ] || echo '{}' > /etc/guest-portal/guest-tokens.json
  chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal '${var_app_dir}/uploads'
"
msg_ok "Configuration files written"

APP_UID=$(pct exec "$CT_ID" -- id -u "${var_app_user}" | tr -d '[:space:]')
APP_GID=$(pct exec "$CT_ID" -- id -g "${var_app_user}" | tr -d '[:space:]')

# ─── Systemd Service ───────────────────────────────────────────────────────

msg_info "Setting up systemd service"
pct exec "$CT_ID" -- bash -c "
cat > /etc/systemd/system/guest-portal.service << 'UNIT'
[Unit]
Description=Guest Portal Node.js Server
After=network.target

[Service]
Type=simple
User=${var_app_user}
Group=${var_app_group}
WorkingDirectory=${var_app_dir}
ExecStart=/usr/bin/env node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadWritePaths=/etc/guest-portal ${var_app_dir}/uploads /mnt

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload >/dev/null 2>&1
systemctl enable guest-portal >/dev/null 2>&1
systemctl start guest-portal >/dev/null 2>&1
"
msg_ok "Systemd service enabled and started"

# ─── NAS Storage Setup ─────────────────────────────────────────────────────

header_info
echo -e "${TAB}${BOLD}Photo Upload Storage${CL}"
echo ""
echo -e "${INFO}${YW}By default, photos are stored locally at ${var_app_dir}/uploads/${CL}"
echo -e "${TAB}  For unprivileged LXCs, prefer mounting NAS storage on the Proxmox host"
echo -e "${TAB}  and bind-mounting it into the container, then choose option 3."
echo ""
echo -e "${TAB}  1)  Mount an NFS share"
echo -e "${TAB}  2)  Mount an SMB/CIFS share"
echo -e "${TAB}  3)  Use an existing mounted directory"
echo -e "${TAB}  4)  Skip — use local storage (configure later in Admin panel)"
echo ""
read -p "  Select [1/2/3/4] (default: 4): " storage_choice
storage_choice=${storage_choice:-4}

if [[ "$CT_UNPRIVILEGED" == "1" && ( "$storage_choice" == "1" || "$storage_choice" == "2" ) ]]; then
  echo ""
  echo -e "${INFO}${YW}Container-managed NFS/SMB mounts often require privileged containers or extra Proxmox features.${CL}"
  echo -e "${TAB}  Recommended: mount the NAS share on the Proxmox host, bind-mount it into this LXC,"
  echo -e "${TAB}  then rerun setup or configure option 3 with that in-container path."
  read -p "  Continue with container-managed mounting anyway? [y/n] (default: n): " mount_confirm
  mount_confirm=${mount_confirm:-n}
  if [[ "${mount_confirm,,}" != "y" ]]; then
    storage_choice=4
  fi
fi

case "$storage_choice" in
  1)
    echo ""
    read -p "  NFS server (e.g. 192.168.1.50): " nas_ip
    read -p "  NFS export path (e.g. /volume1/guest-photos): " nas_export
    read -p "  Mount point (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}

    msg_info "Installing NFS client and mounting share"
    pct exec "$CT_ID" -- bash -c "
      apt-get install -y nfs-common >/dev/null 2>&1 &&
      mkdir -p '${nas_mount}' &&
      mount -t nfs -o nosuid,nodev,noexec '${nas_ip}:${nas_export}' '${nas_mount}' &&
      mkdir -p '${nas_mount}/backgrounds' &&
      (chown -R '${var_app_user}:${var_app_group}' '${nas_mount}' 2>/dev/null || true) &&
      echo '${nas_ip}:${nas_export} ${nas_mount} nfs defaults,_netdev,nosuid,nodev,noexec 0 0' >> /etc/fstab
    "

    if pct exec "$CT_ID" -- bash -c "mountpoint -q '${nas_mount}' && su -s /bin/sh -c 'test -w \"${nas_mount}\"' '${var_app_user}'" 2>/dev/null; then
      msg_ok "NFS share mounted at ${nas_mount}"

      NAS_MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      pct exec "$CT_ID" -- bash -c "
        export MOUNT_B64=$NAS_MOUNT_B64
        node -e 'var fs=require(\"fs\");var c=JSON.parse(fs.readFileSync(\"/etc/guest-portal/config.json\",\"utf8\"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,\"base64\").toString();fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
        chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal
      "
      pct exec "$CT_ID" -- systemctl restart guest-portal
      msg_ok "Upload path set to ${nas_mount}"
    else
      msg_error "Mount failed or is not writable by ${var_app_user}. Check NAS export permissions."
      echo -e "${INFO}${YW}You can configure the upload path later in the Admin panel.${CL}"
    fi
    ;;
  2)
    echo ""
    read -p "  SMB server (e.g. 192.168.1.50): " nas_ip
    read -p "  SMB share name (e.g. guest-photos): " smb_share
    read -p "  SMB username: " smb_user
    read -sp "  SMB password: " smb_pass
    echo
    read -p "  Mount point (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}

    msg_info "Installing CIFS client and mounting share"
    SMB_USER_B64=$(printf '%s' "$smb_user" | base64 -w0)
    SMB_PASS_B64=$(printf '%s' "$smb_pass" | base64 -w0)

    pct exec "$CT_ID" -- bash -c "
      apt-get install -y cifs-utils >/dev/null 2>&1 &&
      mkdir -p '${nas_mount}' &&
      export SMB_U_B64=$SMB_USER_B64 SMB_P_B64=$SMB_PASS_B64
      node -e '
        var fs = require(\"fs\");
        var u = Buffer.from(process.env.SMB_U_B64, \"base64\").toString();
        var p = Buffer.from(process.env.SMB_P_B64, \"base64\").toString();
        fs.writeFileSync(\"/etc/guest-portal/.smbcredentials\", \"username=\" + u + \"\npassword=\" + p + \"\n\", { mode: 0o600 });
      ' &&
      mount -t cifs '//${nas_ip}/${smb_share}' '${nas_mount}' -o credentials=/etc/guest-portal/.smbcredentials,uid=${APP_UID},gid=${APP_GID},file_mode=0660,dir_mode=0770,nosuid,nodev,noexec &&
      mkdir -p '${nas_mount}/backgrounds' &&
      echo '//${nas_ip}/${smb_share} ${nas_mount} cifs credentials=/etc/guest-portal/.smbcredentials,uid=${APP_UID},gid=${APP_GID},file_mode=0660,dir_mode=0770,nosuid,nodev,noexec,_netdev 0 0' >> /etc/fstab
    "

    if pct exec "$CT_ID" -- bash -c "mountpoint -q '${nas_mount}' && su -s /bin/sh -c 'test -w \"${nas_mount}\"' '${var_app_user}'" 2>/dev/null; then
      msg_ok "SMB share mounted at ${nas_mount}"

      NAS_MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      pct exec "$CT_ID" -- bash -c "
        export MOUNT_B64=$NAS_MOUNT_B64
        node -e 'var fs=require(\"fs\");var c=JSON.parse(fs.readFileSync(\"/etc/guest-portal/config.json\",\"utf8\"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,\"base64\").toString();fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
        chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal
      "
      pct exec "$CT_ID" -- systemctl restart guest-portal
      msg_ok "Upload path set to ${nas_mount}"
    else
      msg_error "Mount failed or is not writable by ${var_app_user}. Check NAS/SMB permissions."
      echo -e "${INFO}${YW}You can configure the upload path later in the Admin panel.${CL}"
    fi
    ;;
  3)
    echo ""
    read -p "  Existing mounted upload path (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}

    if pct exec "$CT_ID" -- bash -c "[ -d '${nas_mount}' ] && su -s /bin/sh -c 'test -w \"${nas_mount}\"' '${var_app_user}'" 2>/dev/null; then
      NAS_MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      pct exec "$CT_ID" -- bash -c "
        su -s /bin/sh -c 'mkdir -p \"${nas_mount}/backgrounds\"' '${var_app_user}'
        export MOUNT_B64=$NAS_MOUNT_B64
        node -e 'var fs=require(\"fs\");var c=JSON.parse(fs.readFileSync(\"/etc/guest-portal/config.json\",\"utf8\"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,\"base64\").toString();fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
        chown -R '${var_app_user}:${var_app_group}' /etc/guest-portal
      "
      pct exec "$CT_ID" -- systemctl restart guest-portal
      msg_ok "Upload path set to existing mount ${nas_mount}"
    else
      msg_error "Path does not exist or is not writable by ${var_app_user}."
      echo -e "${INFO}${YW}Create or bind-mount the NAS path first, then configure it in the Admin panel.${CL}"
    fi
    ;;
  4)
    echo -e "${CM}${GN}Using default local storage${CL}"
    echo -e "${INFO}${YW}Configure NAS mount later from Admin panel > Upload Storage Path.${CL}"
    ;;
  *)
    echo -e "${CM}${GN}Using default local storage${CL}"
    ;;
esac

# ─── Reverse Proxy Setup ───────────────────────────────────────────────────

# Detect container IP
NODEJS_IP=$(pct exec "$CT_ID" -- hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$NODEJS_IP" ]]; then
  echo ""
  echo -e "${INFO}${YW}Could not auto-detect container IP.${CL}"
  read -p "  Enter the container IP address: " NODEJS_IP
fi

header_info
echo -e "${TAB}${BOLD}Reverse Proxy / HTTPS${CL}"
echo ""
echo -e "${GATEWAY}${DGN}Guest Portal backend: ${BGN}http://${NODEJS_IP}:3000${CL}"
echo ""
echo -e "${TAB}  1)  Nginx Proxy Manager (existing instance)"
echo -e "${TAB}      ${DGN}Prints step-by-step NPM dashboard config${CL}"
echo ""
echo -e "${TAB}  2)  New NGINX container"
echo -e "${TAB}      ${DGN}Creates a dedicated LXC with auto-configured reverse proxy${CL}"
echo ""
echo -e "${TAB}  3)  Skip / Manual"
echo -e "${TAB}      ${DGN}Configure your own reverse proxy later${CL}"
echo ""
read -p "  Select [1/2/3] (default: 1): " proxy_choice
proxy_choice=${proxy_choice:-1}

case "$proxy_choice" in
  1)
    header_info
    echo -e "${TAB}${BOLD}Nginx Proxy Manager Configuration${CL}"
    echo ""
    echo -e "${TAB}  Add a new ${BOLD}Proxy Host${CL} in your NPM dashboard:"
    echo ""
    echo -e "${TAB}  ${BOLD}Details tab:${CL}"
    echo -e "${TAB}    Domain Names:       guestportal.yourdomain.com"
    echo -e "${TAB}    Scheme:             http"
    echo -e "${TAB}    Forward Hostname:   ${GN}${NODEJS_IP}${CL}"
    echo -e "${TAB}    Forward Port:       ${GN}3000${CL}"
    echo -e "${TAB}    [x] Block Common Exploits"
    echo -e "${TAB}    [x] Websockets Support"
    echo ""
    echo -e "${TAB}  ${BOLD}SSL tab:${CL}"
    echo -e "${TAB}    [x] Request a new SSL Certificate"
    echo -e "${TAB}    [x] Use DNS Challenge for internal-only hostnames"
    echo -e "${TAB}    [x] Force SSL"
    echo -e "${TAB}    [x] HTTP/2 Support"
    echo -e "${TAB}    [x] HSTS Enabled"
    echo -e "${TAB}    Store DNS provider API tokens in NPM only, never in this repo."
    echo ""
    echo -e "${TAB}  ${BOLD}Advanced tab (optional security headers):${CL}"
    echo -e "${TAB}    add_header X-Content-Type-Options nosniff always;"
    echo -e "${TAB}    add_header X-Frame-Options DENY always;"
    echo -e "${TAB}    add_header Referrer-Policy strict-origin-when-cross-origin always;"
    echo -e "${TAB}    add_header Permissions-Policy \"camera=(), microphone=(), geolocation=()\" always;"
    echo -e "${TAB}    client_max_body_size 50M;"
    echo ""
    echo -e "${TAB}  See PROXY.md for split DNS, Cloudflare DNS challenge, and hardening notes."
    echo ""
    ;;
  2)
    echo ""
    echo -e "${TAB}${BOLD}NGINX Container Settings${CL}"
    echo ""
    read -p "  NGINX hostname (default: guest-portal-nginx): " nginx_hostname
    nginx_hostname=${nginx_hostname:-"guest-portal-nginx"}

    NEXT_NGINX_ID=$((CT_ID + 1))
    read -p "  NGINX container ID (default: ${NEXT_NGINX_ID}): " nginx_id
    nginx_id=${nginx_id:-$NEXT_NGINX_ID}

    read -p "  Network bridge (default: ${CT_BRIDGE}): " nginx_bridge
    nginx_bridge=${nginx_bridge:-$CT_BRIDGE}

    echo ""
    echo -e "${TAB}  NGINX IPv4 Configuration:"
    echo -e "${TAB}    1)  DHCP"
    echo -e "${TAB}    2)  Static IP"
    echo ""
    read -p "  Select [1/2] (default: 2): " nginx_net_choice
    nginx_net_choice=${nginx_net_choice:-2}

    if [[ "$nginx_net_choice" == "2" ]]; then
      read -p "  Static IP (CIDR, e.g. 192.168.1.101/24): " nginx_ip
      read -p "  Gateway (e.g. 192.168.1.1): " nginx_gw
      read -p "  DNS Server (default: 1.1.1.1): " nginx_dns
      nginx_dns=${nginx_dns:-"1.1.1.1"}
      nginx_net="name=eth0,bridge=${nginx_bridge},ip=${nginx_ip},gw=${nginx_gw}"
    else
      nginx_net="name=eth0,bridge=${nginx_bridge},ip=dhcp"
    fi

    msg_info "Creating NGINX container"
    run_pct_create "$nginx_id" "$var_os_template" \
      --hostname "$nginx_hostname" \
      --cores 1 --memory 256 \
      --net0 "$nginx_net" \
      --rootfs "${var_rootfs_storage}:2" \
      --onboot 1 \
      --unprivileged 1
    msg_ok "Created NGINX container ${nginx_id}"

    msg_info "Starting NGINX container and installing nginx"
    run_pct_start "$nginx_id"
    sleep 3
    pct exec "$nginx_id" -- bash -c "apt-get update >/dev/null 2>&1 && apt-get install -y nginx >/dev/null 2>&1"
    msg_ok "NGINX installed"

    # Check if nginx config template exists locally or on GitHub
    NGINX_CONF_TMP=$(mktemp)
    if fetch_nginx_template "$NGINX_CONF_TMP"; then
      sed "s/NODEJS_CONTAINER_IP/${NODEJS_IP}/g" "$NGINX_CONF_TMP" > "${NGINX_CONF_TMP}.final"
      mv "${NGINX_CONF_TMP}.final" "$NGINX_CONF_TMP"
      msg_info "Deploying nginx config"
      pct push "$nginx_id" "$NGINX_CONF_TMP" /etc/nginx/conf.d/guestportal.conf
      rm -f "$NGINX_CONF_TMP"
      pct exec "$nginx_id" -- systemctl restart nginx
      msg_ok "NGINX configured and running"
    else
      msg_info "No nginx config template found — generating basic config"
      pct exec "$nginx_id" -- bash -c "
cat > /etc/nginx/conf.d/guestportal.conf << 'NGINX'
server {
    listen 80;
    server_name guestportal.yourdomain.com;
    client_max_body_size 50M;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;
    add_header Permissions-Policy \"camera=(), microphone=(), geolocation=()\" always;

    location / {
        proxy_pass http://${NODEJS_IP}:3000;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \\\$scheme;
    }
}
NGINX
systemctl restart nginx
"
      msg_ok "Basic NGINX config deployed"
    fi

    echo ""
    echo -e "${INFO}${YW}Install certbot for HTTPS:${CL}"
    echo -e "${TAB}  pct exec ${nginx_id} -- bash -c 'apt install -y certbot python3-certbot-nginx'"
    echo -e "${TAB}  pct exec ${nginx_id} -- certbot --nginx -d guestportal.yourdomain.com"
    echo ""
    ;;
  3)
    echo ""
    echo -e "${CM}${GN}Skipping reverse proxy setup${CL}"
    echo ""
    echo -e "${INFO}${YW}Point your reverse proxy to: ${GN}http://${NODEJS_IP}:3000${CL}"
    echo -e "${TAB}  See PROXY.md and the example nginx config in the repo at:"
    echo -e "${TAB}  ${var_app_dir}/nginx/guestportal.conf"
    echo ""
    ;;
  *)
    echo -e "${CM}${GN}Skipping reverse proxy setup${CL}"
    ;;
esac

# ─── Setup Complete ────────────────────────────────────────────────────────

header_info
echo -e "${CREATING}${GN}${BOLD}Guest Portal setup has been completed successfully!${CL}"
echo ""
echo -e "${CONTAINERID}${BOLD}${DGN}Container ID: ${BGN}${CT_ID}${CL}  (${CT_HOSTNAME})"
echo -e "${GATEWAY}${BOLD}${DGN}Backend: ${BGN}http://${NODEJS_IP}:3000${CL}"
echo -e "${PROXY}${BOLD}${DGN}Admin Panel: ${BGN}http://${NODEJS_IP}:3000/admin.html${CL}"
echo ""
echo -e "${TAB}${BOLD}Key Paths (inside container):${CL}"
echo -e "${TAB}  Application:   ${var_app_dir}/"
echo -e "${TAB}  Config:        /etc/guest-portal/config.json"
echo -e "${TAB}  Data:          /etc/guest-portal/storage.json"
echo -e "${TAB}  Service:       systemctl status guest-portal"
echo ""
echo -e "${TAB}${BOLD}Useful Commands:${CL}"
echo -e "${TAB}  ${DGN}pct enter ${CT_ID}${CL}                    Enter the container"
echo -e "${TAB}  ${DGN}pct exec ${CT_ID} -- systemctl status guest-portal${CL}"
echo -e "${TAB}  ${DGN}pct exec ${CT_ID} -- journalctl -u guest-portal -f${CL}"
echo -e "${TAB}  ${DGN}bash -c \"\$(curl -fsSL .../install.sh)\"${CL}  Install/update without git on host"
echo -e "${TAB}  ${DGN}pct exec ${CT_ID} -- updateguest${CL}         Update app from inside container"
echo -e "${TAB}  ${DGN}pct exec ${CT_ID} -- updateguest --dry-run${CL} Preview update steps"
echo ""
if [[ -z "$ADMIN_HASH" || "$ADMIN_HASH" == *"placeholder"* ]]; then
  echo -e "${INFO}${YW}Visit /admin.html to create your admin account on first login.${CL}"
else
  echo -e "${CM}${GN}Admin credentials are configured. Log in at /admin.html${CL}"
fi
echo ""
