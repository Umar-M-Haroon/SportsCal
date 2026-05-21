#!/bin/bash

echo "🔄 Force Restarting SportsCal Server..."
echo ""

# Kill any process on port 8080
echo "1. Stopping old server on port 8080..."
PID=$(lsof -ti:8080)
if [ ! -z "$PID" ]; then
    kill -9 $PID
    echo "   Killed process $PID"
    sleep 1
else
    echo "   No process found on port 8080"
fi

# Also kill any swift run processes
pkill -9 -f "swift run" 2>/dev/null && echo "   Killed swift run processes"
pkill -9 -f "Run" 2>/dev/null && echo "   Killed Run processes"

echo ""

# Make sure Redis is up — the server and cache flush both depend on it.
echo "2. Checking Redis..."
if ! command -v redis-cli >/dev/null 2>&1; then
    echo "   ⚠️  redis-cli not found — install Redis (e.g. 'brew install redis') and re-run."
    exit 1
fi

if redis-cli ping >/dev/null 2>&1; then
    echo "   Redis already running"
else
    echo "   Redis not running — attempting to start..."
    if command -v brew >/dev/null 2>&1; then
        brew services start redis >/dev/null 2>&1
        # Wait briefly for it to accept connections.
        for i in 1 2 3 4 5; do
            if redis-cli ping >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
    fi

    if redis-cli ping >/dev/null 2>&1; then
        echo "   Redis started"
    else
        echo "   ❌ Could not start Redis. Start it manually:"
        echo "        brew services start redis"
        echo "      or:"
        echo "        redis-server"
        exit 1
    fi
fi

echo ""

# Flush dynamic caches so the next fetch cycle repopulates from ESPN / TheSportsDB.
# Keeps: static team lookups, ESPN↔TSDB ID map, F1 circuit/image data, and all
# push-notification state (PushToStart-*, SentPushToStart-*, EventState-*).
# Wipes: every cached live/schedule/enrichment payload, both prod and debug keys.
echo "3. Clearing dynamic Redis caches (keeping teams, ID map, F1 circuits, push state)..."
if command -v redis-cli >/dev/null 2>&1; then
    DYNAMIC_KEYS=(
      "Latest Full Live Info"
      "Latest Detailed Full Live Info"
      "All Soccer Scoreboards"
      "Latest Soccer Scoreboards"
      "All Tennis Scoreboards"
      "Latest Tennis Scoreboards"
      "Latest Schedule"
      "Schedule Last Update"
      "Latest Live Info (TSDB)"
      "Latest Full Live Info (TSDB)"
      "F1 Standings"
      "F1 Enrichment Last Update"
      "Golf Enrichment"
      "Golf Enrichment Last Update"
      "Injuries"
      "Injuries Last Update"
      "Postseason Window"
      "Postseason Window Last Update"
    )
    # Build a single DEL call with prod + debug variants of each key.
    DEL_ARGS=()
    for key in "${DYNAMIC_KEYS[@]}"; do
        DEL_ARGS+=("$key" "debug-$key")
    done
    DELETED=$(redis-cli del "${DEL_ARGS[@]}")
    echo "   Cleared $DELETED dynamic key(s)"
else
    echo "   ⚠️  redis-cli not found — skipping cache flush"
fi

echo ""
export SportsDB_API_KEY="929289"

echo "4. Building server..."
cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "5. Starting server..."
    echo "   Server will run on http://localhost:8080"
    echo "   Admin dashboard: http://localhost:8080/admin/"
    echo ""
    echo "   Press Ctrl+C to stop"
    echo ""
    swift run
else
    echo ""
    echo "❌ Build failed. Please check errors above."
    exit 1
fi
