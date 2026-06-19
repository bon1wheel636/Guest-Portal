#!/usr/bin/env bash
# Guest Portal Proxmox installer bootstrap
# No git required on the Proxmox host.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/bon1wheel636/guest-portal/main/install.sh)"
#
# Pin a branch or fork:
#   GUEST_PORTAL_BRANCH=main bash -c "$(curl -fsSL .../install.sh)"

set -euo pipefail

REPO="${GUEST_PORTAL_REPO:-bon1wheel636/guest-portal}"
BRANCH="${GUEST_PORTAL_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"

if [[ "${1:-}" == "--branch" && -n "${2:-}" ]]; then
  BRANCH="$2"
  RAW_BASE="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
  shift 2
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required on the Proxmox host." >&2
  exit 1
fi

exec bash <(curl -fsSL "${RAW_BASE}/setup.sh") "$@"
