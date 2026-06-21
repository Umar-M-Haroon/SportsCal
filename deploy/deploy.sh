#!/usr/bin/env bash
# deploy.sh — Deploy or update SportsCal server
# Usage: ./deploy/deploy.sh
set -euo pipefail

HOST="hetzner"
REMOTE_DIR="/opt/sportscal"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying SportsCal ==="

# Sync source code (excludes iOS app, admin source, secrets, build artifacts)
echo "[1/3] Syncing source..."
rsync -avz --delete \
    --exclude '.build' \
    --exclude '.swiftpm' \
    --exclude 'node_modules' \
    --exclude '.git' \
    --exclude 'SportsCal/' \
    --exclude 'SportsCalAdmin/' \
    --exclude '*.p8' \
    --exclude '.env.production' \
    --exclude 'pbp_archive.sqlite*' \
    "${REPO_ROOT}/" \
    "${HOST}:${REMOTE_DIR}/repo/"

# Sync deploy configs
echo "[2/3] Syncing deploy configs..."
rsync -avz \
    "${SCRIPT_DIR}/docker-compose.yml" \
    "${SCRIPT_DIR}/Caddyfile" \
    "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}/.env.production.example" \
    "${HOST}:${REMOTE_DIR}/"

# Build and restart
echo "[3/3] Building and restarting..."
ssh "${HOST}" "cd ${REMOTE_DIR} && docker compose up --build -d && docker compose logs --tail=20 app"

echo ""
echo "=== Deploy complete ==="
echo "Check: curl -H 'X-API-Key: YOUR_KEY' https://api.sportscal.app/v2025/schedules"
