#!/bin/bash
# Clears all SportsCal caches from Redis, forcing a full refetch of everything.
echo "Clearing all SportsCal caches..."
redis-cli keys "debug-*" | xargs -r redis-cli del
echo "Done. Full data refresh will take ~3-4 minutes."
