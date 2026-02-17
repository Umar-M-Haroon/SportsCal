# SportsCal Admin Dashboard

A web-based admin dashboard for monitoring and managing the SportsCal API.

## Features

- **Health Monitor**: Real-time system health, Redis status, and background job monitoring
- **Live Games**: WebSocket-powered live game updates across all sports
- **League Explorer**: Browse and analyze games by league
- **Data Gaps**: Identify missing data (badges, scores, timestamps) across leagues
- **Redis Viewer**: Browse, view, and manage Redis cache keys
- **Teams Explorer**: View all teams with badges and metadata

## Technology Stack

- **Frontend**: TypeScript + Vite
- **Backend**: Vapor (Swift) API
- **Real-time**: WebSocket for live updates
- **Styling**: Vanilla CSS with CSS variables

## Development Setup

### Prerequisites

- Node.js 18+
- Vapor backend running on `localhost:8080`

### Installation

```bash
cd SportsCalAdmin
npm install
```

### Development Mode

Run the Vite dev server with API proxy:

```bash
npm run dev
```

This will:
- Start dev server on `http://localhost:3000`
- Proxy API requests to `http://localhost:8080`
- Enable hot module replacement

### Building for Production

Build the dashboard to be served by Vapor:

```bash
npm run build
```

This will:
- Compile TypeScript
- Bundle assets
- Output to `../SportsCalAPI/SportsCalServer/Public/admin`

After building, restart the Vapor server and access the dashboard at:
```
http://localhost:8080/admin/
```

## API Endpoints

### Read Endpoints

- `GET /admin/health` - System health and job status
- `GET /admin/metrics` - API performance metrics
- `GET /admin/redis/keys` - List all Redis keys
- `GET /admin/redis/key/:key` - Get specific key content
- `GET /admin/data-gaps` - Data completeness analysis
- `GET /admin/leagues/:league/stats` - League statistics

### Write Endpoints

- `POST /admin/redis/invalidate/:key` - Delete specific cache key
- `POST /admin/redis/refresh` - Force refresh all schedules
- `POST /admin/jobs/trigger/:jobName` - Trigger background job
- `DELETE /admin/cache/all` - Clear all cache (use with caution)

## Project Structure

```
SportsCalAdmin/
├── src/
│   ├── api/
│   │   ├── client.ts       # API client and WebSocket manager
│   │   └── types.ts        # TypeScript type definitions
│   ├── components/
│   │   ├── Dashboard.ts    # Main container
│   │   ├── HealthMonitor.ts
│   │   ├── LiveGames.ts
│   │   ├── LeagueExplorer.ts
│   │   ├── DataGaps.ts
│   │   ├── RedisViewer.ts
│   │   └── TeamsExplorer.ts
│   ├── utils/
│   │   └── formatting.ts   # Utility functions
│   ├── styles/
│   │   └── main.css        # Global styles
│   └── main.ts             # Entry point
├── index.html
├── package.json
├── tsconfig.json
└── vite.config.ts
```

## Features Detail

### Health Monitor

- Redis connection status and memory usage
- Background job schedules and last run times
- Quick actions: Refresh schedules, Clear cache

### Live Games

- Real-time score updates via WebSocket
- Grouped by sport (NBA, NFL, NHL, MLB, Soccer)
- Shows game status, scores, and last play

### League Explorer

- Select from 24 supported leagues
- View all games with live status
- Statistics: total, live, and upcoming games

### Data Gaps

- Completeness analysis for each league
- Identifies missing badges, scores, and timestamps
- Recommendations for data improvements

### Redis Viewer

- Browse all Redis keys with metadata
- View key contents (formatted JSON)
- Search and filter keys
- Delete individual keys

### Teams Explorer

- Grid view of all teams with logos
- Search by team name
- Identifies teams with missing badges

## Development Tips

### Adding New Components

1. Create component file in `src/components/`
2. Implement `render(container)` and `stop()` methods
3. Register in `Dashboard.ts`
4. Add navigation button in `index.html`

### API Integration

Use the `apiClient` from `src/api/client.ts`:

```typescript
import { apiClient } from '../api/client'

const health = await apiClient.getHealth()
```

### WebSocket Usage

```typescript
import { WebSocketManager } from '../api/client'

const ws = new WebSocketManager()
ws.connect(
  (data) => console.log('Live data:', data),
  (connected) => console.log('Connected:', connected)
)
```

## Testing

### Backend Testing

Test admin endpoints with curl:

```bash
# Health check
curl http://localhost:8080/admin/health

# Redis keys
curl http://localhost:8080/admin/redis/keys

# Data gaps
curl http://localhost:8080/admin/data-gaps

# Invalidate key
curl -X POST http://localhost:8080/admin/redis/invalidate/test-key
```

### Frontend Testing

1. Start Vapor backend: `swift run`
2. Start dev server: `npm run dev`
3. Open `http://localhost:3000`
4. Test all views and features

## Deployment

### Production Build

```bash
npm run build
cd ../SportsCalAPI/SportsCalServer
swift run
```

Access at: `http://localhost:8080/admin/`

### Verifying Deployment

- [ ] All components load without errors
- [ ] WebSocket connects successfully
- [ ] All API endpoints respond correctly
- [ ] No console errors
- [ ] Responsive design works on mobile

## Troubleshooting

### WebSocket Connection Issues

If WebSocket fails to connect:
- Check that Vapor server is running
- Verify WebSocket endpoint is accessible at `/ws`
- Check browser console for errors

### API Errors

If API requests fail:
- Verify Vapor server is running on port 8080
- Check that admin routes are registered
- Look for CORS issues in browser console

### Build Issues

If build fails:
- Clear node_modules: `rm -rf node_modules && npm install`
- Clear Vite cache: `rm -rf node_modules/.vite`
- Check TypeScript errors: `npx tsc --noEmit`

## Future Enhancements

- [ ] Authentication with API keys
- [ ] Historical metrics and charts (Chart.js)
- [ ] Data export (CSV/JSON)
- [ ] Job execution history
- [ ] Real-time alerts
- [ ] Team badge upload
- [ ] Bulk operations
- [ ] API testing tool

## License

Internal use only
