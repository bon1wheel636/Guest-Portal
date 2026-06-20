#!/usr/bin/env bash
# Guest Portal in-container setup
# Run inside the Guest Portal LXC as root.
#
# Remote one-liner:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/scripts/setup-container.sh)"
#
# Local copy from a git checkout:
#   bash /opt/guest-portal/scripts/setup-container.sh

set -euo pipefail

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
GATEWAY="${TAB}🌐${TAB}"
CREATING="${TAB}🚀${TAB}"

msg_info() { echo -ne "${TAB}⏳${TAB}${YW}${1}...${CL}"; }
msg_ok() { echo -e "\r${CM}${GN}${1}${CL}"; }
msg_error() { echo -e "\r${CROSS}${RD}${1}${CL}" >&2; }

DRY_RUN=false
UPDATE_MODE=false
var_repo="https://github.com/bon1wheel636/guest-portal.git"
var_repo_raw="https://raw.githubusercontent.com/bon1wheel636/guest-portal/main"
var_app_dir="/opt/guest-portal"
var_app_user="guestportal"
var_app_group="guestportal"
CT_UNPRIVILEGED=1

usage() {
  cat <<'EOF'
Usage: setup-container.sh [--dry-run] [--update] [--help]

Install or update Guest Portal inside the current LXC/container.

Options:
  --dry-run   Show the planned steps without making changes
  --update    Refresh code, dependencies, systemd unit, and updateguest
  --help      Show this help
EOF
}

header_info() {
  clear
  echo -e "${BL}"
  echo '   ____                 _     ____            _        _ '
  echo '  / ___|_   _  ___  ___| |_  |  _ \ ___  _ __| |_ __ _| |'
  echo ' | |  _| | | |/ _ \/ __| __| | |_) / _ \|  __| __/ _` | |'
  echo ' | |_| | |_| |  __/\__ \ |_  |  __/ (_) | |  | || (_| | |'
  echo '  \____|\__,_|\___||___/\__| |_|   \___/|_|   \__\__,_|_|'
  echo -e "${CL}"
  echo -e "${TAB}${DGN}Guest Portal Container Setup${CL}"
  echo ""
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-n}"
  local answer
  read -p "${prompt} [y/n] (default: ${default}): " answer
  answer=${answer:-$default}
  [[ "${answer,,}" == "y" ]]
}

install_updateguest_command() {
  if [[ -f "${var_app_dir}/scripts/updateguest.sh" ]]; then
    install -m 755 "${var_app_dir}/scripts/updateguest.sh" /usr/local/bin/updateguest
  fi
}

load_setup_prompts() {
  local prompts_file="${var_app_dir}/scripts/setup-prompts.sh"
  if [[ ! -f "$prompts_file" ]]; then
    msg_error "Missing setup prompts helper: ${prompts_file}"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$prompts_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --update) UPDATE_MODE=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *)
      msg_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

header_info

if [[ "$(id -u)" -ne 0 ]]; then
  msg_error "Run this script as root inside the Guest Portal container."
  exit 1
fi

if [[ "$UPDATE_MODE" == "true" ]]; then
  echo -e "${TAB}${BOLD}Update Guest Portal (container)${CL}"
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${TAB}  - git pull --ff-only in ${var_app_dir}"
    echo -e "${TAB}  - npm install"
    echo -e "${TAB}  - refresh updateguest and systemd unit"
    echo -e "${TAB}  - restart guest-portal"
    exit 0
  fi

  if command -v updateguest >/dev/null 2>&1; then
    updateguest -y
  else
    msg_info "Updating application code"
    bash -c "
      set -e
      chown -R '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
      su -s /bin/bash -c \"cd '${var_app_dir}' && git pull --ff-only && npm install\" '${var_app_user}'
      mkdir -p '${var_app_dir}/uploads/backgrounds'
      chown -R '${var_app_user}:${var_app_group}' '${var_app_dir}' /etc/guest-portal
    "
    install_updateguest_command
    msg_ok "Application code updated"
    systemctl restart guest-portal
  fi

  echo ""
  echo -e "${CM}${GN}Guest Portal container update complete.${CL}"
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo -e "${TAB}${BOLD}Dry run only. Planned container setup:${CL}"
  echo -e "${TAB}  - Install git, curl, nodejs, npm"
  echo -e "${TAB}  - Clone ${var_repo} into ${var_app_dir}"
  echo -e "${TAB}  - Configure rooms, admin account, and systemd service"
  echo -e "${TAB}  - Optional NAS upload path"
  exit 0
fi

msg_info "Updating OS and installing dependencies"
apt-get update >/dev/null 2>&1
apt-get install -y git curl nodejs npm >/dev/null 2>&1
msg_ok "Installed OS dependencies"

msg_info "Creating application service user"
groupadd --system "${var_app_group}" 2>/dev/null || true
id -u "${var_app_user}" >/dev/null 2>&1 || useradd --system --gid "${var_app_group}" --home-dir "${var_app_dir}" --shell /usr/sbin/nologin "${var_app_user}"
mkdir -p "${var_app_dir}" /etc/guest-portal
chown "${var_app_user}:${var_app_group}" "${var_app_dir}" /etc/guest-portal
msg_ok "Application service user ready"

if [[ -d "${var_app_dir}/.git" ]]; then
  msg_info "Using existing repository checkout"
  git -C "${var_app_dir}" pull --ff-only >/dev/null 2>&1 || true
  msg_ok "Repository already present"
else
  msg_info "Cloning Guest Portal repository"
  git clone "${var_repo}" "${var_app_dir}" >/dev/null 2>&1
  msg_ok "Cloned repository into container"
fi

msg_info "Installing Node.js dependencies"
cd "${var_app_dir}"
npm install >/dev/null 2>&1
mkdir -p "${var_app_dir}/uploads/backgrounds"
chown -R "${var_app_user}:${var_app_group}" "${var_app_dir}" /etc/guest-portal
install_updateguest_command
msg_ok "Installed Node.js dependencies"

load_setup_prompts
gp_prompt_room_configuration || exit 1
gp_prompt_admin_configuration || exit 1

msg_info "Writing configuration files"
gp_write_setup_config_files "${var_app_user}" "${var_app_group}" "${var_app_dir}/uploads"
msg_ok "Configuration files written"

msg_info "Setting up systemd service"
cat > /etc/systemd/system/guest-portal.service << UNIT
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
systemctl restart guest-portal >/dev/null 2>&1
msg_ok "Systemd service enabled and started"

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
  read -p "  Continue with container-managed mounting anyway? [y/n] (default: n): " mount_confirm
  mount_confirm=${mount_confirm:-n}
  if [[ "${mount_confirm,,}" != "y" ]]; then
    storage_choice=4
  fi
fi

case "$storage_choice" in
  1)
    read -p "  NFS server (e.g. 192.168.1.50): " nas_ip
    read -p "  NFS export path (e.g. /volume1/guest-photos): " nas_export
    read -p "  Mount point (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}

    msg_info "Installing NFS client and mounting share"
    apt-get install -y nfs-common >/dev/null 2>&1
    mkdir -p "${nas_mount}"
    mount -t nfs -o nosuid,nodev,noexec "${nas_ip}:${nas_export}" "${nas_mount}"
    mkdir -p "${nas_mount}/backgrounds"
    chown -R "${var_app_user}:${var_app_group}" "${nas_mount}" 2>/dev/null || true
    echo "${nas_ip}:${nas_export} ${nas_mount} nfs defaults,_netdev,nosuid,nodev,noexec 0 0" >> /etc/fstab

    if mountpoint -q "${nas_mount}" && su -s /bin/sh -c "test -w \"${nas_mount}\"" "${var_app_user}"; then
      MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      export MOUNT_B64
      node -e 'var fs=require("fs");var c=JSON.parse(fs.readFileSync("/etc/guest-portal/config.json","utf8"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,"base64").toString();fs.writeFileSync("/etc/guest-portal/config.json",JSON.stringify(c,null,2))'
      chown -R "${var_app_user}:${var_app_group}" /etc/guest-portal
      systemctl restart guest-portal
      msg_ok "NFS mount configured at ${nas_mount}"
    else
      msg_error "NFS mount failed or is not writable by ${var_app_user}."
    fi
    ;;
  2)
    read -p "  SMB server (e.g. 192.168.1.50): " nas_ip
    read -p "  SMB share name (e.g. guest-photos): " nas_share
    read -p "  SMB username: " nas_user
    read -sp "  SMB password: " nas_pass
    echo
    read -p "  Mount point (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}

    msg_info "Installing SMB client and mounting share"
    apt-get install -y cifs-utils >/dev/null 2>&1
    mkdir -p /etc/guest-portal
    printf '%s\n' "username=${nas_user}" "password=${nas_pass}" > /etc/guest-portal/.smbcredentials
    chmod 600 /etc/guest-portal/.smbcredentials
    mkdir -p "${nas_mount}"
    mount -t cifs "//${nas_ip}/${nas_share}" "${nas_mount}" -o credentials=/etc/guest-portal/.smbcredentials,uid="$(id -u ${var_app_user})",gid="$(id -g ${var_app_user})",file_mode=0660,dir_mode=0770,nosuid,nodev,noexec
    mkdir -p "${nas_mount}/backgrounds"
    echo "//${nas_ip}/${nas_share} ${nas_mount} cifs credentials=/etc/guest-portal/.smbcredentials,uid=$(id -u ${var_app_user}),gid=$(id -g ${var_app_user}),file_mode=0660,dir_mode=0770,_netdev,nosuid,nodev,noexec 0 0" >> /etc/fstab

    if mountpoint -q "${nas_mount}" && su -s /bin/sh -c "test -w \"${nas_mount}\"" "${var_app_user}"; then
      MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      export MOUNT_B64
      node -e 'var fs=require("fs");var c=JSON.parse(fs.readFileSync("/etc/guest-portal/config.json","utf8"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,"base64").toString();fs.writeFileSync("/etc/guest-portal/config.json",JSON.stringify(c,null,2))'
      chown -R "${var_app_user}:${var_app_group}" /etc/guest-portal
      systemctl restart guest-portal
      msg_ok "SMB mount configured at ${nas_mount}"
    else
      msg_error "SMB mount failed or is not writable by ${var_app_user}."
    fi
    ;;
  3)
    read -p "  Existing mounted upload path (default: /mnt/nas/guest-photos): " nas_mount
    nas_mount=${nas_mount:-/mnt/nas/guest-photos}
    if [[ -d "${nas_mount}" ]] && su -s /bin/sh -c "test -w \"${nas_mount}\"" "${var_app_user}"; then
      su -s /bin/sh -c "mkdir -p \"${nas_mount}/backgrounds\"" "${var_app_user}"
      MOUNT_B64=$(printf '%s' "$nas_mount" | base64 -w0)
      export MOUNT_B64
      node -e 'var fs=require("fs");var c=JSON.parse(fs.readFileSync("/etc/guest-portal/config.json","utf8"));c.uploadDir=Buffer.from(process.env.MOUNT_B64,"base64").toString();fs.writeFileSync("/etc/guest-portal/config.json",JSON.stringify(c,null,2))'
      chown -R "${var_app_user}:${var_app_group}" /etc/guest-portal
      systemctl restart guest-portal
      msg_ok "Upload path set to existing mount ${nas_mount}"
    else
      msg_error "Path does not exist or is not writable by ${var_app_user}."
    fi
    ;;
  *)
    echo -e "${CM}${GN}Using default local storage${CL}"
    ;;
esac

NODEJS_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [[ -z "$NODEJS_IP" ]]; then
  read -p "  Enter this container IP address: " NODEJS_IP
fi

header_info
echo -e "${CREATING}${GN}${BOLD}Guest Portal container setup complete.${CL}"
echo ""
echo -e "${GATEWAY}${BOLD}${DGN}Backend: ${BGN}http://${NODEJS_IP}:3000${CL}"
echo -e "${GATEWAY}${BOLD}${DGN}Admin Panel: ${BGN}http://${NODEJS_IP}:3000/admin.html${CL}"
gp_admin_login_message
echo ""
echo -e "${TAB}${BOLD}Next steps:${CL}"
echo -e "${TAB}  - Point Nginx Proxy Manager or another reverse proxy to http://${NODEJS_IP}:3000"
echo -e "${TAB}  - See PROXY.md in ${var_app_dir} for HTTPS guidance"
echo -e "${TAB}  - Run ${DGN}updateguest${CL} later for routine code updates"
echo ""
