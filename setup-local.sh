#!/bin/bash
# Guest Portal Local Development Setup Script
# This script sets up the configuration for running locally without Proxmox

set -e

echo "Guest Portal - Local Development Setup"
echo "======================================="
echo ""

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    exit 1
fi

# Check for npm
if ! command -v npm &> /dev/null; then
    echo "Error: npm is required but not installed."
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

# Set admin username
read -p "Enter admin username (default: admin): " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

# Set admin password
while true; do
    read -sp "Enter admin password: " ADMIN_PASS
    echo
    if [ -z "$ADMIN_PASS" ]; then
        echo "Password cannot be empty. Try again."
        continue
    fi
    read -sp "Confirm password: " ADMIN_PASS_CONFIRM
    echo
    if [ "$ADMIN_PASS" == "$ADMIN_PASS_CONFIRM" ]; then
        break
    else
        echo "Passwords do not match. Try again."
    fi
done

# Hash the password using bcrypt (pass via env var to prevent shell injection)
echo "Hashing password..."
ADMIN_HASH=$(ADMIN_PASS="$ADMIN_PASS" node -e "require('bcrypt').hash(process.env.ADMIN_PASS, 10).then(h => console.log(h))")

# Create config directory
CONFIG_DIR="/etc/guest-portal"
if [ -w "/etc" ]; then
    mkdir -p "$CONFIG_DIR"
else
    echo ""
    echo "Note: Cannot write to /etc. Using sudo..."
    sudo mkdir -p "$CONFIG_DIR"
    sudo chown $(whoami) "$CONFIG_DIR"
fi

# Create config.json (use node to safely serialize values into JSON)
echo "Creating configuration files..."
ADMIN_USER="$ADMIN_USER" ADMIN_HASH="$ADMIN_HASH" node -e "
  var fs = require('fs');
  var config = {
    adminUser: process.env.ADMIN_USER,
    adminHash: process.env.ADMIN_HASH,
    uploadDir: './uploads',
    sessionExpirationMinutes: 10,
    adminSessionTimeoutMinutes: 15
  };
  fs.writeFileSync('$CONFIG_DIR/config.json', JSON.stringify(config, null, 2));
"

# Create storage.json if it doesn't exist
if [ ! -f "$CONFIG_DIR/storage.json" ]; then
    cat > "$CONFIG_DIR/storage.json" << EOF
{
  "rooms": [],
  "guests": []
}
EOF
fi

# Create sessions.json if it doesn't exist
if [ ! -f "$CONFIG_DIR/sessions.json" ]; then
    echo "{}" > "$CONFIG_DIR/sessions.json"
fi

# Create uploads directory
mkdir -p uploads

echo ""
echo "Setup complete!"
echo ""
echo "Admin credentials:"
echo "  Username: $ADMIN_USER"
echo "  Password: (as entered)"
echo ""
echo "To start the server, run:"
echo "  npm start"
echo ""
echo "Access the portal at: http://localhost:3000"
echo "Admin panel at: http://localhost:3000/admin.html"
