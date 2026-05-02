#!/usr/bin/env bash
# setup-vps.sh — Set up a fresh VPS and deploy SportsCal
# Usage: ./deploy/setup-vps.sh
# Requires: "hetzner" SSH config entry, .env.production in deploy/, APNS .p8 key in SportsCalAPI/SportsCalServer/
set -euo pipefail

HOST="hetzner"
APP_DIR="/opt/sportscal"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
APNS_KEY=$(ls "${REPO_ROOT}/SportsCalAPI/SportsCalServer"/AuthKey_*.p8 2>/dev/null | head -1)

echo "=== SportsCal VPS Setup ==="

# 1. Install Docker & configure firewall
echo "[1/4] Installing Docker and configuring firewall..."
ssh "${HOST}" bash -s <<'REMOTE'
set -euo pipefail
apt-get update -qq && apt-get upgrade -y -qq

if ! command -v docker &>/dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

docker compose version &>/dev/null || apt-get install -y -qq docker-compose-plugin

mkdir -p /opt/sportscal

if command -v ufw &>/dev/null; then
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
fi
REMOTE

# 2. Copy .env.production
echo "[2/4] Copying .env.production..."
if [ -f "${SCRIPT_DIR}/.env.production" ]; then
    scp "${SCRIPT_DIR}/.env.production" "${HOST}:${APP_DIR}/.env.production"
else
    echo "  WARNING: deploy/.env.production not found!"
    echo "  Copy the example and fill in your values:"
    echo "    cp deploy/.env.production.example deploy/.env.production"
    echo "  Then re-run this script."
    exit 1
fi

# 3. Copy APNS key
echo "[3/4] Copying APNS key..."
if [ -n "${APNS_KEY}" ]; then
    scp "${APNS_KEY}" "${HOST}:${APP_DIR}/AuthKey.p8"
else
    echo "  WARNING: No AuthKey_*.p8 found in SportsCalAPI/SportsCalServer/"
    echo "  You'll need to manually copy it:"
    echo "    scp /path/to/AuthKey.p8 hetzner:${APP_DIR}/AuthKey.p8"
fi

# 4. Deploy
echo "[4/4] Running deploy..."
"${SCRIPT_DIR}/deploy.sh"

echo ""
echo "=== Setup Complete ==="
echo "Make sure sportscal.app and api.sportscal.app DNS A records point to your VPS IP."
echo "Check: curl -H 'X-API-Key: YOUR_KEY' https://api.sportscal.app/v2025/schedules"
