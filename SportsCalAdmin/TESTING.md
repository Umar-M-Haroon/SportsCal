# SportsCal Admin Dashboard - Testing Guide

## Quick Start

### 1. Start the Backend

```bash
cd /Users/umar/Developer/SportsCalMonoRepo/SportsCalAPI/SportsCalServer
swift run
```

The server will start on `http://localhost:8080`

### 2. Access the Dashboard

Open your browser and navigate to:
```
http://localhost:8080/admin/
```

## Testing Checklist

### Backend Endpoints

Test the admin endpoints using curl:

```bash
# Health check
curl http://localhost:8080/admin/health | jq

# Redis keys
curl http://localhost:8080/admin/redis/keys | jq

# Data gaps analysis
curl http://localhost:8080/admin/data-gaps | jq

# Get schedules (regular API)
curl http://localhost:8080/v2025/schedules | jq

# Get teams
curl http://localhost:8080/v2025/teams | jq
```

Write operations:
```bash
# Refresh schedules
curl -X POST http://localhost:8080/admin/redis/refresh | jq

# View specific Redis key (URL encode the key name)
curl "http://localhost:8080/admin/redis/key/Latest%20Schedule" | jq

# Invalidate a key (be careful!)
curl -X POST http://localhost:8080/admin/redis/invalidate/test-key | jq
```

### Frontend Testing

#### 1. Health Monitor
- [ ] Displays Redis connection status (green/red indicator)
- [ ] Shows Redis key count and memory usage
- [ ] Lists all background jobs with schedules
- [ ] "Refresh Schedules" button works
- [ ] "Clear All Cache" button shows confirmation

#### 2. Live Games
- [ ] WebSocket connects (check connection indicator in header)
- [ ] Live games appear grouped by sport
- [ ] Scores update in real-time (if games are live)
- [ ] Team badges display correctly
- [ ] Game status badges show correct colors

#### 3. League Explorer
- [ ] League dropdown shows all 24 leagues
- [ ] Selecting a league loads statistics
- [ ] Game table displays with team names and badges
- [ ] Status badges show correct game states
- [ ] Time/progress displays correctly

#### 4. Data Gaps
- [ ] Overall completeness percentage displays
- [ ] League table shows all leagues
- [ ] Missing data counts are accurate
- [ ] Completeness badges use correct colors
- [ ] Recommendations section shows leagues with issues

#### 5. Redis Viewer
- [ ] All Redis keys display in table
- [ ] Search filter works
- [ ] "View" button shows key contents
- [ ] JSON is properly formatted
- [ ] TTL displays correctly
- [ ] "Delete" button shows confirmation
- [ ] Deleting a key removes it from the list

#### 6. Teams Explorer
- [ ] All teams display in grid
- [ ] Team badges/logos show correctly
- [ ] Missing badge indicator shows for teams without logos
- [ ] Search filter works
- [ ] Badge shows count of teams with missing badges

### Performance Testing

#### WebSocket Connection
- Open browser developer tools > Network tab
- Check for WebSocket connection to `/ws`
- Verify messages are being received every 5 seconds
- Connection should auto-reconnect if dropped

#### API Response Times
All admin endpoints should respond in:
- `/admin/health` - < 100ms
- `/admin/redis/keys` - < 500ms (depends on key count)
- `/admin/data-gaps` - < 1s
- `/admin/leagues/:id/stats` - < 200ms

### Browser Compatibility

Test in:
- [ ] Chrome/Edge (Chromium)
- [ ] Firefox
- [ ] Safari

### Mobile Responsive

Test on mobile viewport:
- [ ] Navigation is usable
- [ ] Tables are scrollable
- [ ] Cards stack properly
- [ ] Buttons are tappable

## Common Issues

### WebSocket Won't Connect

**Symptom**: Connection indicator stays red, no live updates

**Solutions**:
1. Check Vapor server is running: `curl http://localhost:8080/ws`
2. Check browser console for WebSocket errors
3. Try refreshing the page
4. Verify Redis is running and accessible

### API Endpoints Return 404

**Symptom**: Dashboard shows "Failed to fetch" errors

**Solutions**:
1. Verify admin routes are registered in `routes.swift`
2. Check Vapor server logs for errors
3. Rebuild and restart server: `swift build && swift run`
4. Test endpoint directly: `curl http://localhost:8080/admin/health`

### Empty or Missing Data

**Symptom**: Dashboard shows no games, teams, or data

**Solutions**:
1. Check if Redis has data: `redis-cli KEYS "*"`
2. Trigger a manual refresh: `curl -X POST http://localhost:8080/admin/redis/refresh`
3. Wait for background jobs to run (check schedule in Health Monitor)
4. Check Vapor logs for job execution errors

### Build Failures

**Backend**:
```bash
cd SportsCalAPI/SportsCalServer
swift build
# Fix any compilation errors
```

**Frontend**:
```bash
cd SportsCalAdmin
rm -rf node_modules
npm install
npm run build
```

## Development Workflow

### Making Changes

1. **Backend Changes** (AdminController.swift):
   ```bash
   cd SportsCalAPI/SportsCalServer
   swift build
   swift run
   ```

2. **Frontend Changes**:
   ```bash
   cd SportsCalAdmin
   npm run dev  # Development server with hot reload
   # or
   npm run build  # Production build
   ```

### Debugging

**Backend Logs**:
- Vapor prints logs to stdout
- Look for "running ScheduleJobs/..." messages
- Check for Redis connection errors

**Frontend Debugging**:
- Open browser DevTools (F12)
- Check Console tab for errors
- Check Network tab for failed requests
- Check Application tab > Local Storage for cached data

## Production Deployment

### Pre-deployment Checklist

- [ ] Backend compiles without errors
- [ ] All tests pass
- [ ] Frontend builds successfully
- [ ] WebSocket connects properly
- [ ] All admin endpoints respond correctly
- [ ] No console errors in browser
- [ ] Mobile responsive design works
- [ ] Performance is acceptable

### Deployment Steps

1. Build frontend:
   ```bash
   cd SportsCalAdmin
   npm run build
   ```

2. Build backend:
   ```bash
   cd ../SportsCalAPI/SportsCalServer
   swift build -c release
   ```

3. Deploy to production server
4. Verify at: `https://your-domain.com/admin/`

## Monitoring

### What to Watch

- Redis memory usage (shown in Health Monitor)
- Number of Redis keys (should be relatively stable)
- Background job execution (should run on schedule)
- WebSocket connection stability
- API response times

### Alerts to Set Up

- Redis connection failures
- Redis memory usage > 80%
- Background job failures
- API response time > 2s
- WebSocket disconnections

## Support

For issues or questions:
1. Check Vapor logs
2. Check browser console
3. Review this testing guide
4. Check README.md for configuration details
