#!/usr/bin/env bash
# deploy.sh — Deploy or update SportsCal server on your VPS
# Usage: ./deploy/deploy.sh YOUR_VPS_IP [SSH_USER]
set -euo pipefail

VPS_IP="${1:?Usage: ./deploy/deploy.sh VPS_IP [SSH_USER]}"
SSH_USER="${2:-root}"
REMOTE_DIR="/opt/sportscal"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying SportsCal to ${SSH_USER}@${VPS_IP} ==="
echo ""

# Sync deployment files
echo "[1/3] Syncing files to ${VPS_IP}:${REMOTE_DIR}..."
rsync -avz --delete \
    --exclude '.build' \
    --exclude '.swiftpm' \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude 'SportsCal/' \
    --exclude 'SportsCalAdmin/' \
    --exclude '*.p8' \
    --exclude '.env.production' \
    "${REPO_ROOT}/" \
    "${SSH_USER}@${VPS_IP}:${REMOTE_DIR}/repo/"

# Sync deploy configs (Caddyfile, docker-compose, .env example)
echo "[2/3] Syncing deploy configs..."
rsync -avz \
    "${SCRIPT_DIR}/docker-compose.yml" \
    "${SCRIPT_DIR}/Caddyfile" \
    "${SCRIPT_DIR}/.env.production.example" \
    "${SCRIPT_DIR}/Dockerfile" \
    "${SSH_USER}@${VPS_IP}:${REMOTE_DIR}/"

# Build and restart on VPS
echo "[3/3] Building and restarting on VPS..."
ssh "${SSH_USER}@${VPS_IP}" "cd ${REMOTE_DIR} && docker compose up --build -d && docker compose logs --tail=20 app"

echo ""
echo "=== Deploy complete ==="
echo "Check: curl -H 'X-API-Key: YOUR_KEY' https://sportscal.com/schedules"
