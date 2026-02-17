#!/bin/bash

echo "🚀 Starting SportsCal Server on port 8081..."
echo ""

export SportsDB_API_KEY="929289"

cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer

echo "Building server..."
swift build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build successful!"
    echo ""
    echo "Starting server on port 8081..."
    echo "   Admin dashboard: http://localhost:8081/admin/"
    echo "   API endpoints: http://localhost:8081/api/admin/health"
    echo ""
    echo "   Press Ctrl+C to stop"
    echo ""

    # Set the port via environment variable
    PORT=8081 swift run serve --hostname 0.0.0.0 --port 8081
else
    echo ""
    echo "❌ Build failed. Please check errors above."
    exit 1
fi
