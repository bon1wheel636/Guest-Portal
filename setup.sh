#!/bin/bash
# Guest Portal LXC Setup Script — Secure & Sequenced

echo "Guest Portal LXC Setup Script"
echo "This script will set up LXC containers for the Guest Portal project."
echo ""

#############################
# Backend Container Options #
#############################

read -p "Enter container name for nodejs (default: guest-portal-nodejs): " nodejs_container
nodejs_container=${nodejs_container:-"guest-portal-nodejs"}

# Recommend next available container ID
next_id=$(pct list | awk 'NR>1 {print $1}' | sort -n | tail -n1)
next_id=$((next_id+1))
echo "Suggested next available container ID: $next_id"
read -p "Enter container ID for nodejs (default: $next_id): " nodejs_id
nodejs_id=${nodejs_id:-$next_id}
nodejs_id=${nodejs_id:-101}

read -p "Enter number of cores for nodejs container (default: 1): " nodejs_cores
nodejs_cores=${nodejs_cores:-1}

read -p "Enter memory for nodejs container in MB (default: 512): " nodejs_memory
nodejs_memory=${nodejs_memory:-512}

echo ""
echo "Configure network for the nodejs container:"
read -p "Enter network bridge for nodejs (default: vmbr0): " nodejs_bridge
nodejs_bridge=${nodejs_bridge:-"vmbr0"}

read -p "Enter network configuration type for nodejs (DHCP or static, default: DHCP): " nodejs_net_type
nodejs_net_type=${nodejs_net_type:-"DHCP"}

if [[ "${nodejs_net_type^^}" == "STATIC" ]]; then
    read -p "Enter static IP address with CIDR (e.g., 192.168.1.100/24): " nodejs_ip
    read -p "Enter gateway (e.g., 192.168.1.1): " nodejs_gw
    read -p "Enter DNS server (e.g., 8.8.8.8): " nodejs_dns
    nodejs_net="name=eth0,bridge=${nodejs_bridge},ip=${nodejs_ip},gw=${nodejs_gw},nameserver=${nodejs_dns}"
else
    nodejs_net="name=eth0,bridge=${nodejs_bridge},ip=dhcp"
fi

read -p "Enter number of guest rooms (1–10): " ROOM_COUNT
ROOM_COUNT=${ROOM_COUNT:-2}

declare -a ROOMS
for (( i=1; i<=ROOM_COUNT; i++ )); do
  read -p "Enter name for Guest Room $i: " ROOM_NAME
  read -p "Enter Home Assistant dashboard URL for $ROOM_NAME: " ROOM_URL
  # Use node to safely serialize room data as JSON
  ROOM_JSON=$(ROOM_NAME="$ROOM_NAME" ROOM_URL="$ROOM_URL" node -e "console.log(JSON.stringify({name:process.env.ROOM_NAME,dashboardUrl:process.env.ROOM_URL}))")
  ROOMS+=("$ROOM_JSON")
done

read -p "Set admin username (default: admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

while true; do
  read -sp "Set admin password for /admin/uploads: " ADMIN_PASS
  echo
  read -sp "Confirm password: " ADMIN_PASS_CONFIRM
  echo
  [[ "$ADMIN_PASS" == "$ADMIN_PASS_CONFIRM" ]] && break || echo "❌ Passwords do not match. Try again."
done

echo ""
echo "Creating nodejs container..."
pct create "$nodejs_id" local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
  --hostname "$nodejs_container" --cores "$nodejs_cores" --memory "$nodejs_memory" --net0 "$nodejs_net" \
  --rootfs local-lvm:4 --onboot 1

echo "Starting nodejs container..."
pct start "$nodejs_id"

echo "Installing Node.js and bcrypt..."
pct exec "$nodejs_id" -- bash -c "apt update && apt install -y nodejs npm && npm install bcrypt"

echo "Checking if bcrypt is installed in the container..."
pct exec "$nodejs_id" -- bash -c "npm list bcrypt || npm install bcrypt"
# Hash admin password (base64-encode to avoid shell injection)
echo "Hashing admin password..."
ADMIN_PASS_B64=$(printf '%s' "$ADMIN_PASS" | base64 -w0)
ADMIN_HASH=$(pct exec "$nodejs_id" -- bash -c "export PASS_B64=$ADMIN_PASS_B64 && node -e 'require(\"bcrypt\").hash(Buffer.from(process.env.PASS_B64,\"base64\").toString(),10).then(console.log)'")

echo "Copying project files..."
pct push "$nodejs_id" "$(pwd)" /root/guest-portal -r

# Write config to container (use base64 + node for safe JSON serialization)
echo "Writing config to nodejs container..."
pct exec "$nodejs_id" -- bash -c "mkdir -p /etc/guest-portal"

ADMIN_USER_B64=$(printf '%s' "$ADMIN_USER" | base64 -w0)
ADMIN_HASH_B64=$(printf '%s' "$ADMIN_HASH" | base64 -w0)

# Build rooms JSON array safely using node
ROOMS_JSON=$(ROOM_DATA="$(printf '%s\n' "${ROOMS[@]}")" node -e "
  var rooms = process.env.ROOM_DATA.trim().split('\n').filter(Boolean);
  console.log(JSON.stringify(rooms.map(function(r) { return JSON.parse(r); })));
")
ROOMS_JSON_B64=$(printf '%s' "$ROOMS_JSON" | base64 -w0)

pct exec "$nodejs_id" -- bash -c "
  if [ ! -f /etc/guest-portal/config.json ]; then
    export USER_B64=$ADMIN_USER_B64 HASH_B64=$ADMIN_HASH_B64
    node -e 'var fs=require(\"fs\");var c={adminUser:Buffer.from(process.env.USER_B64,\"base64\").toString(),adminHash:Buffer.from(process.env.HASH_B64,\"base64\").toString()};fs.writeFileSync(\"/etc/guest-portal/config.json\",JSON.stringify(c,null,2))'
  else
    echo '✔ Existing config.json found — skipping overwrite'
  fi
  if [ ! -f /etc/guest-portal/storage.json ]; then
    export ROOMS_B64=$ROOMS_JSON_B64
    node -e 'var fs=require(\"fs\");var s={rooms:JSON.parse(Buffer.from(process.env.ROOMS_B64,\"base64\").toString()),guests:[]};fs.writeFileSync(\"/etc/guest-portal/storage.json\",JSON.stringify(s,null,2))'
  else
    echo '✔ Existing storage.json found — skipping overwrite'
  fi
"

echo "Launching nodejs server..."
pct exec "$nodejs_id" -- bash -c "cd /root/guest-portal && npm install && nohup node server.js > server.log 2>&1 &"

echo ""
read -p "Do you want to set up a new NGINX container? (y/n, default: n): " setup_nginx
setup_nginx=${setup_nginx:-n}

if [[ "$setup_nginx" == "y" ]]; then
  read -p "Enter container name for NGINX (default: guest-portal-nginx): " nginx_container
  nginx_container=${nginx_container:-"guest-portal-nginx"}

  read -p "Enter container ID for NGINX (default: 102): " nginx_id
  nginx_id=${nginx_id:-102}

  read -p "Enter network bridge for NGINX (default: vmbr0): " nginx_bridge
  nginx_bridge=${nginx_bridge:-"vmbr0"}

  read -p "Use static IP for NGINX? (y/n, default: y): " nginx_static
  nginx_static=${nginx_static:-y}

  if [[ "$nginx_static" == "y" ]]; then
    read -p "Enter static IP (CIDR): " nginx_ip
    read -p "Enter gateway: " nginx_gw
    read -p "Enter DNS: " nginx_dns
    nginx_net="name=eth0,bridge=${nginx_bridge},ip=${nginx_ip},gw=${nginx_gw},nameserver=${nginx_dns}"
  else
    nginx_net="name=eth0,bridge=${nginx_bridge},ip=dhcp"
  fi

  pct create "$nginx_id" local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname "$nginx_container" --cores 1 --memory 512 --net0 "$nginx_net" \
    --rootfs local-lvm:2 --onboot 1

  pct start "$nginx_id"
  pct exec "$nginx_id" -- bash -c "apt update && apt install -y nginx"
  pct push "$nginx_id" "$(pwd)/nginx/guestportal.conf" /etc/nginx/conf.d/guestportal.conf
  pct exec "$nginx_id" -- systemctl restart nginx
else
  echo ""
  echo "Manual NGINX setup selected. Choose one of the following methods:"
  echo "1. Web UI:"
  echo "   - Log into the NGINX container’s web interface."
  echo "   - Add a new server block for guestportal.<your-domain>."
  echo "   - Reverse proxy to http://<nodejs-container-ip>:3000"
  echo ""
  echo "2. CLI:"
  echo "   - Copy 'nginx/guestportal.conf' to /etc/nginx/conf.d/guestportal.conf"
  echo "   - Restart nginx with: systemctl restart nginx"
fi

echo ""
echo "✅ Guest Portal setup complete!"