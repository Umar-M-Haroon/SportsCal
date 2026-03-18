#!/bin/bash
# Clears cached soccer scoreboards and live data, forcing a full refetch on next job cycle.
echo "Clearing soccer caches..."
redis-cli del "debug-All Soccer Scoreboards" "debug-Latest Soccer Scoreboards" "debug-Latest Full Live Info" "debug-Latest Detailed Full Live Info"
echo "Done. Soccer data will refresh within ~2 minutes."
