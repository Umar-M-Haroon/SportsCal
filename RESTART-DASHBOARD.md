# How to Restart the Dashboard

## Quick Restart

**Kill the old server (if running on port 8080):**
```bash
lsof -ti:8080 | xargs kill -9
```

**Start the server:**
```bash
cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift run
```

**Open the dashboard:**
```
http://localhost:8080/admin/
```

## New Features Added

### 1. Connection Logger
- Click the **📋 Log** button in the top-right corner
- See all API requests, responses, and timing
- Debug connection issues easily
- Clear or close the log as needed

### 2. Refresh Buttons
Every view now has a refresh button:
- **Health Monitor**: 🔄 Refresh button top-right
- **League Explorer**: 🔄 Refresh button to reload all leagues
- **Redis Viewer**: 🔄 Refresh button to reload keys

### 3. Better Error Handling
- All components show proper error messages
- Retry buttons appear when requests fail
- Loading states don't block the UI
- Timeouts prevent infinite waiting

### 4. Pretty JSON Viewer (Redis)
- Syntax highlighted JSON
- Dark theme editor
- Copy button to copy JSON to clipboard
- Shows file size and TTL
- Scrollable for large JSON

### 5. Connection Status
Each component logs:
- When it starts
- When requests are made
- How long requests take
- Success/failure status
- Error details

## Testing the Dashboard

After starting the server, test each feature:

### Health Monitor
1. Should load within 1-2 seconds
2. Shows Redis status, memory, key count
3. Lists all background jobs
4. Refresh button reloads data
5. Actions: Refresh Schedules, Clear Cache

### Live Games
1. Shows UI immediately
2. WebSocket connects in background
3. Badge shows connection status
4. Updates every 5 seconds if games are live

### League Explorer
1. All 24 leagues load progressively
2. Click any league to see games
3. Games grouped by: Live, Upcoming, Completed
4. Refresh button reloads all data
5. Back button returns to league grid

### Redis Viewer
1. Lists all Redis keys with metadata
2. Search/filter keys
3. Click "View" to see pretty JSON
4. Syntax highlighting (blue/orange/green)
5. Copy button to clipboard
6. Delete button with confirmation

### Connection Log
1. Click **📋 Log** button in header
2. See all API activity
3. Green = success, Red = error
4. Shows timing for each request
5. Clear button to reset log

## Troubleshooting

### Dashboard shows "Not Found"
- The server is running old code
- Kill the server and restart: `lsof -ti:8080 | xargs kill -9`
- Then: `swift run`

### Health Monitor gets stuck
- Open the Connection Log (📋 Log button)
- Check for red error messages
- Look for timeout errors
- Verify server is on port 8080: `curl http://localhost:8080/api/admin/health`

### "Every endpoint fails"
- Check if server is actually running: `ps aux | grep swift`
- Check if port 8080 is in use: `lsof -ti:8080`
- Test API directly: `curl http://localhost:8080/api/admin/health`
- Check the Connection Log for details

### League Explorer shows "No games"
- Wait 10-15 seconds for data to load
- Check Connection Log for errors
- Click 🔄 Refresh button
- Verify schedules endpoint works: `curl http://localhost:8080/v2025/schedules`

## API Endpoints Reference

All admin endpoints (check these with curl):

```bash
# Health check
curl http://localhost:8080/api/admin/health | jq

# Redis keys
curl http://localhost:8080/api/admin/redis/keys | jq

# Data gaps
curl http://localhost:8080/api/admin/data-gaps | jq

# League stats (example: NBA = 4387)
curl http://localhost:8080/api/admin/leagues/4387/stats | jq

# Regular API endpoints
curl http://localhost:8080/v2025/schedules | jq
curl http://localhost:8080/v2025/teams | jq
```

## Expected Behavior

### Load Times
- Health Monitor: < 2 seconds
- League Explorer: 10-15 seconds (loads progressively)
- Redis Viewer: < 1 second
- Data Gaps: < 2 seconds

### Connection Log Messages
You should see messages like:
```
[timestamp] Health Monitor initialized
[timestamp] Fetching health status from /api/admin/health...
[timestamp] Health status received in 145ms
[timestamp] League Explorer initialized
[timestamp] Fetching schedules from /v2025/schedules...
[timestamp] Schedules loaded in 892ms
[timestamp] Loaded 13 Redis keys in 234ms
```

### Error Messages
If something fails, you'll see:
```
[timestamp] Health fetch failed after 5003ms: Request timeout after 5s
[timestamp] Failed to fetch schedules: Error: ...
```

## Development Mode

To run with Vite hot reload:

```bash
# Terminal 1: Backend
cd SportsCalAPI/SportsCalServer
swift run

# Terminal 2: Frontend dev server
cd SportsCalAdmin
npm run dev

# Open: http://localhost:3000
```

## Production Build

To rebuild the dashboard:

```bash
cd SportsCalAdmin
npm run build

# Files are automatically copied to:
# SportsCalAPI/SportsCalServer/Public/admin/
```

Then restart the Vapor server to serve the new files.
