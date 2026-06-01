#!/usr/bin/env bash
#
# apns-load-test.sh — seed N synthetic APNS-* registration keys into Redis and
# compare the cost of the old `KEYS` scan vs the new `SCAN` cursor (B5).
#
# Usage:   ./apns-load-test.sh [N] [extra redis-cli args...]
# Example: ./apns-load-test.sh 10000
#          ./apns-load-test.sh 10000 -h 127.0.0.1 -p 6379
#
# Keys are prefixed `APNS-loadtest-` so cleanup never touches real registrations.
# End-to-end job runtime (scan -> process) is observable separately at
#   GET /admin/push-metrics  ->  lastRunSeconds
# once the server is running with live-score data; target < 40s to keep the
# JobLock 10s safety margin under the 60s tick.

set -euo pipefail

N="${1:-5000}"
shift || true
RCLI=(redis-cli "$@")
PREFIX="APNS-loadtest-"

echo "Seeding ${N} ${PREFIX}* keys into Redis..."
seq 1 "${N}" | sed "s/^/SET ${PREFIX}token/; s/\$/ 1/" | "${RCLI[@]}" --pipe >/dev/null
total="$("${RCLI[@]}" --scan --pattern "${PREFIX}*" | wc -l | tr -d ' ')"
echo "Seeded. ${PREFIX}* count = ${total}"
echo

echo "== KEYS (old path — O(N), blocks the ENTIRE Redis server) =="
time "${RCLI[@]}" KEYS "${PREFIX}*" >/dev/null
echo
echo "== SCAN cursor (new path — incremental, non-blocking) =="
time "${RCLI[@]}" --scan --pattern "${PREFIX}*" >/dev/null
echo

cat <<'NOTE'
Interpretation:
  KEYS holds Redis exclusively for its whole duration — every other client
  (including the API serving real users) stalls behind it. SCAN yields between
  batches. At device scale the delta is the difference between "fine" and
  "the whole server hitches every minute on the APNS tick".
NOTE
echo

read -r -p "Delete the ${total} seeded keys now? [y/N] " ans
if [[ "${ans:-N}" =~ ^[Yy]$ ]]; then
    "${RCLI[@]}" --scan --pattern "${PREFIX}*" | xargs -r "${RCLI[@]}" DEL >/dev/null
    echo "Cleaned up."
else
    echo "Left seeded. Clean later with:"
    echo "  redis-cli --scan --pattern '${PREFIX}*' | xargs redis-cli DEL"
fi
