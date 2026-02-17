#!/bin/bash

echo "🔄 Restarting SportsCal Server..."
echo ""

# Kill any existing swift run processes
echo "1. Stopping old server..."
pkill -f "swift run" || echo "   No server was running"

echo ""
export SportsDB_API_KEY="929289"

echo "2. Building server..."
cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    LOCAL_IP=$(ipconfig getifaddr en0)
    echo "3. Starting server on 0.0.0.0:8080..."
    echo "   Local:   http://localhost:8080"
    echo "   Network: http://${LOCAL_IP}:8080"
    echo "   Press Ctrl+C to stop"
    echo ""
    swift run Run serve --hostname 0.0.0.0 --port 8080
else
    echo ""
    echo "❌ Build failed. Please check errors above."
    exit 1
fi
