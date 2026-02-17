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
export SportsDB_API_KEY="929289"

echo "2. Building server..."
cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "3. Starting server..."
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
