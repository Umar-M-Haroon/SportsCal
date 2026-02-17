#!/bin/bash

echo "Testing SportsCal Admin Dashboard..."
echo ""

echo "1. Testing static file serving:"
curl -s -o /dev/null -w "  /admin/ - Status: %{http_code}\n" http://localhost:8080/admin/
curl -s -o /dev/null -w "  /admin/index.html - Status: %{http_code}\n" http://localhost:8080/admin/index.html

echo ""
echo "2. Testing API endpoints:"
curl -s -o /dev/null -w "  /api/admin/health - Status: %{http_code}\n" http://localhost:8080/api/admin/health
curl -s -o /dev/null -w "  /api/admin/redis/keys - Status: %{http_code}\n" http://localhost:8080/api/admin/redis/keys
curl -s -o /dev/null -w "  /api/admin/data-gaps - Status: %{http_code}\n" http://localhost:8080/api/admin/data-gaps

echo ""
echo "3. Testing regular API endpoints:"
curl -s -o /dev/null -w "  /v2025/schedules - Status: %{http_code}\n" http://localhost:8080/v2025/schedules
curl -s -o /dev/null -w "  /v2025/teams - Status: %{http_code}\n" http://localhost:8080/v2025/teams

echo ""
echo "If you see 200 for all endpoints, everything is working!"
echo "Open http://localhost:8080/admin/ in your browser"
