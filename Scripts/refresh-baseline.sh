#!/usr/bin/env bash
# Captures /schedules + /teams from the configured SportsCal server, trims the
# schedule to a today±N-day window, and writes the result to
# SportsCal/Shared/Resources/Baseline/. Read at first-launch by
# GameViewModel.loadBundledBaselineSnapshot when no on-disk cache exists.
#
# Usage:
#   ./Scripts/refresh-baseline.sh
#
# Reads SPORTSCAL_API_BASE and SPORTSCAL_API_KEY from .env at the repo root.
# `.env` is gitignored — copy `.env.example` and fill in.
#
# Environment overrides (optional):
#   BASELINE_DAYS_BACK    days of history to keep (default: 2)
#   BASELINE_DAYS_FORWARD days of upcoming schedule to keep (default: 14)
#
# Notes:
# - The bundled JSON files must also be added to the SportsCal app target's
#   "Copy Bundle Resources" build phase (one-time Xcode UI step).
# - Files are checked in so cold launches on first install work offline.
# - Requires `jq`. Pre-installed on macOS 13+; otherwise `brew install jq`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

API_BASE="${SPORTSCAL_API_BASE:?Set SPORTSCAL_API_BASE in $ENV_FILE (no trailing slash). Copy from .env.example.}"
API_KEY="${SPORTSCAL_API_KEY:?Set SPORTSCAL_API_KEY in $ENV_FILE. Copy from .env.example.}"
DAYS_BACK="${BASELINE_DAYS_BACK:-2}"
DAYS_FORWARD="${BASELINE_DAYS_FORWARD:-14}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)" >&2; exit 1; }

OUT_DIR="$REPO_ROOT/SportsCal/Shared/Resources/Baseline"
mkdir -p "$OUT_DIR"

CUTOFF_FROM=$(date -u -v-"${DAYS_BACK}"d +"%Y-%m-%dT%H:%M")
CUTOFF_TO=$(date -u -v+"${DAYS_FORWARD}"d +"%Y-%m-%dT%H:%M")
TMP_RAW="$(mktemp -t baseline-schedule-raw)"
trap 'rm -f "$TMP_RAW"' EXIT

echo "→ Fetching $API_BASE/v2025/schedules"
curl -fsS -H "X-API-Key: $API_KEY" "$API_BASE/v2025/schedules" -o "$TMP_RAW"
RAW_SIZE=$(wc -c < "$TMP_RAW" | tr -d ' ')
echo "  raw payload: $RAW_SIZE bytes"

echo "→ Trimming events to ${CUTOFF_FROM} … ${CUTOFF_TO}"
# ISO 8601 timestamps sort lexicographically the same as chronologically, so a
# string compare on the first 16 chars (YYYY-MM-DDTHH:MM) is correct here.
jq --arg from "$CUTOFF_FROM" --arg to "$CUTOFF_TO" '
    def keepEvent: (.strTimestamp // "") | .[0:16] >= $from and .[0:16] <= $to;
    def trim:
        if . == null then null
        elif (.events // null) == null then .
        else .events |= map(select(keepEvent))
        end;
    {
        nba:    (.nba    | trim),
        mlb:    (.mlb    | trim),
        soccer: (.soccer | trim),
        nfl:    (.nfl    | trim),
        nhl:    (.nhl    | trim),
        golf:   (.golf   | trim),
        tennis: (.tennis | trim),
        racing: (.racing | trim),
        f1Standings: .f1Standings
    }
' "$TMP_RAW" > "$OUT_DIR/baseline-schedule.json"

echo "→ Fetching $API_BASE/v2025/teams"
curl -fsS -H "X-API-Key: $API_KEY" "$API_BASE/v2025/teams" -o "$OUT_DIR/baseline-teams.json"

SIZE_SCHEDULE=$(wc -c < "$OUT_DIR/baseline-schedule.json" | tr -d ' ')
SIZE_TEAMS=$(wc -c < "$OUT_DIR/baseline-teams.json" | tr -d ' ')

echo
PCT=$(awk -v a="$SIZE_SCHEDULE" -v b="$RAW_SIZE" 'BEGIN { if (b > 0) printf "%.1f", a * 100 / b; else printf "0" }')
echo "✓ baseline-schedule.json: $SIZE_SCHEDULE bytes (${PCT}% of raw)"
echo "✓ baseline-teams.json:    $SIZE_TEAMS bytes"
echo
echo "Per-sport event counts after trimming:"
for sport in nba mlb nfl nhl soccer golf tennis racing; do
    count=$(jq ".${sport}.events | length" "$OUT_DIR/baseline-schedule.json")
    printf "  %-8s %s\n" "$sport" "$count"
done
echo
echo "Next: in Xcode, add both files to the SportsCal target's"
echo "      'Copy Bundle Resources' build phase if not already there."
