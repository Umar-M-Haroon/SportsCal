#!/usr/bin/env bash
# setup-vps.sh — Run this on a fresh Ubuntu 22.04+ VPS (Hetzner CX22 or similar)
# Usage: scp setup-vps.sh root@YOUR_VPS_IP: && ssh root@YOUR_VPS_IP ./setup-vps.sh
set -euo pipefail

APP_DIR="/opt/sportscal"

echo "=== SportsCal VPS Setup ==="
echo ""

# 1. System updates
echo "[1/4] Updating system packages..."
apt-get update -qq && apt-get upgrade -y -qq

# 2. Install Docker
if command -v docker &>/dev/null; then
    echo "[2/4] Docker already installed: $(docker --version)"
else
    echo "[2/4] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Ensure Docker Compose plugin is available
if docker compose version &>/dev/null; then
    echo "       Docker Compose plugin: $(docker compose version)"
else
    echo "       Installing Docker Compose plugin..."
    apt-get install -y -qq docker-compose-plugin
fi

# 3. Create app directory
echo "[3/4] Setting up app directory at ${APP_DIR}..."
mkdir -p "${APP_DIR}"

# 4. Firewall (allow HTTP, HTTPS, SSH only)
echo "[4/4] Configuring firewall..."
if command -v ufw &>/dev/null; then
    ufw allow OpenSSH
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    echo "       UFW enabled: SSH, HTTP, HTTPS allowed"
else
    echo "       UFW not found, skipping firewall setup"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "  1. Point sportscal.com DNS A record to this server's IP"
echo ""
echo "  2. From your local machine, deploy with:"
echo "     ./deploy/deploy.sh YOUR_VPS_IP"
echo ""
echo "  3. On this server, create your env file:"
echo "     cp ${APP_DIR}/.env.production.example ${APP_DIR}/.env.production"
echo "     nano ${APP_DIR}/.env.production"
echo ""
echo "  4. Copy your APNS key file:"
echo "     scp AuthKey_XXXXX.p8 root@THIS_IP:${APP_DIR}/AuthKey.p8"
echo ""
echo "  5. Start everything:"
echo "     cd ${APP_DIR} && docker compose up -d"
echo ""
