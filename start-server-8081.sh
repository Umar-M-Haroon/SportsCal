#!/bin/bash

echo "🚀 Starting SportsCal Server on port 8081..."
echo ""
echo "Admin dashboard will be at: http://localhost:8081/admin/"
echo ""

export SportsDB_API_KEY="929289"

cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift run
