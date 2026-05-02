#!/usr/bin/env bash
# parity-check.sh — Compare dev and prod SportsCal API responses.
#
# Usage:
#   SPORTSCAL_API_KEY=... ./deploy/parity-check.sh            # uses defaults
#   DEV_BASE=http://100.68.255.93:8080 PROD_BASE=https://api.sportscal.app \
#     SPORTSCAL_API_KEY=... ./deploy/parity-check.sh
#
# Exits 0 when every endpoint matches after noise-stripping, 1 otherwise.
# Relies on jq and curl being in PATH.

set -u

DEV_BASE="${DEV_BASE:-http://100.68.255.93:8080}"
PROD_BASE="${PROD_BASE:-https://api.sportscal.app}"
API_KEY="${SPORTSCAL_API_KEY:-}"

if [[ -z "${API_KEY}" ]]; then
    echo "ERROR: SPORTSCAL_API_KEY must be set." >&2
    exit 2
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }

# Endpoints to compare. Add freely; keep responses small (< a few MB after
# stripping) — the diff is the useful signal, not the raw payload size.
ENDPOINTS=(
    "/v2025/schedules"
    "/v2025/live"
    "/v2025/teams"
    "/v2025/sport/basketball"
    "/v2025/sport/soccer"
    "/v2025/sport/racing"
    "/v2025/standings/4387"      # NBA
    "/v2025/standings/4391"      # NFL
    "/v2025/widget/schedule?sports=basketball,soccer,mlb&limit=6"
    "/v2025/teams-by-league"
    "/v2025/all-live-games"
)

# Fields that change every request and would drown out real diffs.
# `walk` is a jq helper that descends into every object; we delete the noisy
# keys at any depth.
NOISE_FILTER='def strip: walk(
    if type == "object" then
        del(.strTimestamp, .updated, .isoDate, .fetchedAt, .timestamp, .lastPlayId)
    else .
    end
); strip'

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

mismatches=0
errors=0
checked=0

for endpoint in "${ENDPOINTS[@]}"; do
    checked=$((checked + 1))
    dev_out="${WORKDIR}/dev.json"
    prod_out="${WORKDIR}/prod.json"
    dev_raw="${WORKDIR}/dev.raw"
    prod_raw="${WORKDIR}/prod.raw"

    dev_status=$(curl -sS -o "${dev_raw}" -w "%{http_code}" -H "X-API-Key: ${API_KEY}" "${DEV_BASE}${endpoint}" 2>"${WORKDIR}/dev.err" || echo "curl_failed")
    prod_status=$(curl -sS -o "${prod_raw}" -w "%{http_code}" -H "X-API-Key: ${API_KEY}" "${PROD_BASE}${endpoint}" 2>"${WORKDIR}/prod.err" || echo "curl_failed")

    if [[ "${dev_status}" != "200" || "${prod_status}" != "200" ]]; then
        echo "✗ ${endpoint}"
        echo "  dev=${dev_status}  prod=${prod_status}"
        if [[ -s "${WORKDIR}/dev.err" ]]; then
            echo "  dev err: $(head -c 200 "${WORKDIR}/dev.err")"
        fi
        if [[ -s "${WORKDIR}/prod.err" ]]; then
            echo "  prod err: $(head -c 200 "${WORKDIR}/prod.err")"
        fi
        errors=$((errors + 1))
        continue
    fi

    if ! jq -S "${NOISE_FILTER}" < "${dev_raw}" > "${dev_out}" 2>/dev/null; then
        echo "✗ ${endpoint} (dev returned non-JSON)"
        errors=$((errors + 1))
        continue
    fi
    if ! jq -S "${NOISE_FILTER}" < "${prod_raw}" > "${prod_out}" 2>/dev/null; then
        echo "✗ ${endpoint} (prod returned non-JSON)"
        errors=$((errors + 1))
        continue
    fi

    if diff -q "${dev_out}" "${prod_out}" >/dev/null; then
        echo "✓ ${endpoint}"
    else
        mismatches=$((mismatches + 1))
        echo "✗ ${endpoint} (diff)"
        # Show first 40 lines of the diff so big payloads don't drown the terminal.
        diff -u "${dev_out}" "${prod_out}" | head -n 40 | sed 's/^/    /'
        echo ""
    fi
done

echo ""
echo "── summary ──"
echo "endpoints checked: ${checked}"
echo "matches:           $((checked - mismatches - errors))"
echo "mismatches:        ${mismatches}"
echo "errors:            ${errors}"
echo "dev:  ${DEV_BASE}"
echo "prod: ${PROD_BASE}"

if (( mismatches > 0 || errors > 0 )); then
    exit 1
fi
