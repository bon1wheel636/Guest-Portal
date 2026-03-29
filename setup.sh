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

# H6: Exclude node_modules, .git, and sensitive files from project copy
echo "Copying project files (excluding node_modules, .git, uploads)..."
tar cf - --exclude='node_modules' --exclude='.git' --exclude='uploads' --exclude='*.env' --exclude='config.json' --exclude='storage.json' --exclude='sessions.json' -C "$(pwd)" . | pct exec "$nodejs_id" -- bash -c "mkdir -p /root/guest-portal && tar xf - -C /root/guest-portal"

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

echo "Installing dependencies and configuring systemd service..."
pct exec "$nodejs_id" -- bash -c "cd /root/guest-portal && npm install"
pct push "$nodejs_id" "$(pwd)/guest-portal.service" /etc/systemd/system/guest-portal.service
pct exec "$nodejs_id" -- bash -c "systemctl daemon-reload && systemctl enable guest-portal && systemctl start guest-portal"
echo "Guest Portal service started and enabled on boot."

############################
# Reverse Proxy Setup      #
############################

# Get the Node.js container’s IP for proxy configuration
NODEJS_IP=$(pct exec "$nodejs_id" -- hostname -I 2>/dev/null | awk ‘{print $1}’)
if [[ -z "$NODEJS_IP" ]]; then
  echo ""
  echo "⚠  Could not auto-detect Node.js container IP."
  read -p "Enter the Node.js container IP address: " NODEJS_IP
fi

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Reverse Proxy Configuration"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Guest Portal is running at: http://${NODEJS_IP}:3000"
echo ""
echo "  How would you like to handle reverse proxy / HTTPS?"
echo ""
echo "  1) Nginx Proxy Manager (NPM)"
echo "     Use an existing NPM instance to manage SSL and routing."
echo ""
echo "  2) New NGINX container"
echo "     Create a dedicated NGINX LXC with the included config."
echo ""
echo "  3) Skip / Manual"
echo "     I’ll configure my own reverse proxy later."
echo ""
read -p "Select an option [1/2/3] (default: 1): " proxy_choice
proxy_choice=${proxy_choice:-1}

case "$proxy_choice" in
  1)
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "  Nginx Proxy Manager Setup"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "  Add a new Proxy Host in your NPM dashboard:"
    echo ""
    echo "  Details tab:"
    echo "    Domain Names:       guestportal.yourdomain.com"
    echo "    Scheme:             http"
    echo "    Forward Hostname:   ${NODEJS_IP}"
    echo "    Forward Port:       3000"
    echo "    ☑ Block Common Exploits"
    echo "    ☑ Websockets Support"
    echo ""
    echo "  SSL tab:"
    echo "    ☑ Request a new SSL Certificate"
    echo "    ☑ Force SSL"
    echo "    ☑ HTTP/2 Support"
    echo "    ☑ HSTS Enabled"
    echo ""
    echo "  Custom locations (optional):"
    echo "    /admin-api/*  →  Access control or IP whitelist"
    echo ""
    echo "  Advanced tab (optional — paste this for security headers):"
    echo "    add_header X-Content-Type-Options nosniff always;"
    echo "    add_header X-Frame-Options DENY always;"
    echo "    add_header Referrer-Policy strict-origin-when-cross-origin always;"
    echo "    client_max_body_size 50M;"
    echo ""
    ;;
  2)
    read -p "Enter container name for NGINX (default: guest-portal-nginx): " nginx_container
    nginx_container=${nginx_container:-"guest-portal-nginx"}

    next_nginx_id=$((nodejs_id + 1))
    read -p "Enter container ID for NGINX (default: $next_nginx_id): " nginx_id
    nginx_id=${nginx_id:-$next_nginx_id}

    read -p "Enter network bridge for NGINX (default: vmbr0): " nginx_bridge
    nginx_bridge=${nginx_bridge:-"vmbr0"}

    read -p "Use static IP for NGINX? (y/n, default: y): " nginx_static
    nginx_static=${nginx_static:-y}

    if [[ "$nginx_static" == "y" ]]; then
      read -p "Enter static IP (CIDR, e.g. 192.168.1.101/24): " nginx_ip
      read -p "Enter gateway (e.g. 192.168.1.1): " nginx_gw
      read -p "Enter DNS (e.g. 8.8.8.8): " nginx_dns
      nginx_net="name=eth0,bridge=${nginx_bridge},ip=${nginx_ip},gw=${nginx_gw},nameserver=${nginx_dns}"
    else
      nginx_net="name=eth0,bridge=${nginx_bridge},ip=dhcp"
    fi

    echo ""
    echo "Creating NGINX container..."
    pct create "$nginx_id" local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst \
      --hostname "$nginx_container" --cores 1 --memory 256 --net0 "$nginx_net" \
      --rootfs local-lvm:2 --onboot 1

    pct start "$nginx_id"
    pct exec "$nginx_id" -- bash -c "apt update && apt install -y nginx"

    # Generate nginx config with the actual backend IP
    NGINX_CONF_TMP=$(mktemp)
    sed "s/NODEJS_CONTAINER_IP/${NODEJS_IP}/g" "$(pwd)/nginx/guestportal.conf" > "$NGINX_CONF_TMP"
    pct push "$nginx_id" "$NGINX_CONF_TMP" /etc/nginx/conf.d/guestportal.conf
    rm -f "$NGINX_CONF_TMP"

    pct exec "$nginx_id" -- systemctl restart nginx
    echo "NGINX container created and configured."
    echo ""
    echo "  Note: The included config expects SSL certificates at:"
    echo "    /etc/letsencrypt/live/guestportal.example.com/"
    echo ""
    echo "  Install certbot and request a certificate:"
    echo "    pct exec $nginx_id -- bash -c ‘apt install -y certbot python3-certbot-nginx’"
    echo "    pct exec $nginx_id -- certbot --nginx -d guestportal.yourdomain.com"
    ;;
  3)
    echo ""
    echo "  Skipping reverse proxy setup."
    echo ""
    echo "  To configure manually, point your reverse proxy to:"
    echo "    http://${NODEJS_IP}:3000"
    echo ""
    echo "  An example nginx config is included at:"
    echo "    nginx/guestportal.conf"
    echo ""
    echo "  Replace NODEJS_CONTAINER_IP with: ${NODEJS_IP}"
    ;;
  *)
    echo "Invalid option. Skipping proxy setup."
    ;;
esac

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Guest Portal Setup Complete!"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Backend:  http://${NODEJS_IP}:3000"
echo "  Admin:    http://${NODEJS_IP}:3000/admin.html"
echo ""
echo "  Container ID: ${nodejs_id} (${nodejs_container})"
echo "  Config:       /etc/guest-portal/config.json"
echo "  Data:         /etc/guest-portal/storage.json"
echo "  Service:      systemctl status guest-portal"
echo ""
echo "  First-time setup: visit /admin.html to create your"
echo "  admin account (or credentials from this script are"
echo "  already configured)."
echo ""