import type {
  HealthResponse,
  MetricsResponse,
  RedisKeysResponse,
  RedisKeyContentResponse,
  DataGapsResponse,
  LeagueStatsResponse,
  InvalidateResponse,
  RefreshResponse,
  ForceRefreshResponse,
  TriggerJobResponse,
  LiveScore,
  Team
} from './types'

class ApiClient {
  private baseUrl: string

  constructor(baseUrl = '') {
    this.baseUrl = baseUrl
  }

  private async fetch<T>(path: string, options?: RequestInit): Promise<T> {
    const response = await fetch(`${this.baseUrl}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        ...options?.headers
      }
    })

    if (!response.ok) {
      throw new Error(`API error: ${response.statusText}`)
    }

    return response.json()
  }

  // Read endpoints
  async getHealth(): Promise<HealthResponse> {
    return this.fetch<HealthResponse>('/api/admin/health')
  }

  async getMetrics(): Promise<MetricsResponse> {
    return this.fetch<MetricsResponse>('/api/admin/metrics')
  }

  // Per-day telemetry counters: { event -> { epochDay -> count } }.
  // Includes the client.* monetization funnel events.
  async getTelemetry(): Promise<{ counters: Record<string, Record<string, number>> }> {
    return this.fetch('/api/admin/telemetry')
  }

  async getRedisKeys(): Promise<RedisKeysResponse> {
    return this.fetch<RedisKeysResponse>('/api/admin/redis/keys')
  }

  async getRedisKey(key: string): Promise<RedisKeyContentResponse> {
    return this.fetch<RedisKeyContentResponse>(`/api/admin/redis/key/${encodeURIComponent(key)}`)
  }

  async getDataGaps(): Promise<DataGapsResponse> {
    return this.fetch<DataGapsResponse>('/api/admin/data-gaps')
  }

  async getLeagueStats(leagueId: number): Promise<LeagueStatsResponse> {
    return this.fetch<LeagueStatsResponse>(`/api/admin/leagues/${leagueId}/stats`)
  }

  async getSchedules(): Promise<LiveScore> {
    return this.fetch<LiveScore>('/v2025/schedules')
  }

  async getTeams(): Promise<Team[]> {
    return this.fetch<Team[]>('/v2025/teams')
  }

  async getLiveGames(): Promise<LiveScore> {
    return this.fetch<LiveScore>('/v2025/all-live-games')
  }

  // Write endpoints
  async invalidateKey(key: string): Promise<InvalidateResponse> {
    return this.fetch<InvalidateResponse>(`/api/admin/redis/invalidate/${encodeURIComponent(key)}`, {
      method: 'POST'
    })
  }

  async refreshSchedules(): Promise<RefreshResponse> {
    return this.fetch<RefreshResponse>('/api/admin/redis/refresh', {
      method: 'POST'
    })
  }

  async forceRefresh(): Promise<ForceRefreshResponse> {
    return this.fetch<ForceRefreshResponse>('/api/admin/force-refresh', {
      method: 'POST'
    })
  }

  async triggerJob(jobName: string): Promise<TriggerJobResponse> {
    return this.fetch<TriggerJobResponse>(`/api/admin/jobs/trigger/${jobName}`, {
      method: 'POST'
    })
  }

  async clearAllCache(): Promise<InvalidateResponse> {
    return this.fetch<InvalidateResponse>('/api/admin/cache/all', {
      method: 'DELETE'
    })
  }

  async getPushToStartRegistrations(): Promise<{ registrations: Array<{ tokenPrefix: string; favorites: string[]; eventIDs: string[] }>; totalTokens: number }> {
    return this.fetch('/api/admin/push-to-start/registrations')
  }

  async getPushToStartDiagnostics(): Promise<{
    system: Array<{ name: string; ok: boolean; detail: string }>;
    tokens: Array<{
      tokenPrefix: string;
      steps: Array<{ name: string; status: string; detail: string }>;
    }>;
  }> {
    return this.fetch('/api/admin/push-to-start/diagnostics')
  }

  async triggerDebugPushToStart(eventID: string, homeTeam: string, awayTeam: string): Promise<{ notified: number; tokens: string[]; trace?: string; reason?: string; errors?: string[] }> {
    return this.fetch('/v2025/debug/trigger-push-to-start', {
      method: 'POST',
      body: JSON.stringify({ eventID, homeTeam, awayTeam })
    })
  }
}

export const apiClient = new ApiClient()

// WebSocket manager for live updates
export class WebSocketManager {
  private ws: WebSocket | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private reconnectDelay = 5000
  private url: string
  private onMessageCallback: ((data: LiveScore) => void) | null = null
  private onStatusChange: ((connected: boolean) => void) | null = null

  constructor(url = 'ws://localhost:8080/ws') {
    this.url = url
  }

  connect(onMessage: (data: LiveScore) => void, onStatusChange?: (connected: boolean) => void) {
    this.onMessageCallback = onMessage
    this.onStatusChange = onStatusChange || null

    try {
      // Use ws:// for local development, wss:// for production
      const wsUrl = window.location.protocol === 'https:'
        ? this.url.replace('ws://', 'wss://')
        : this.url

      this.ws = new WebSocket(wsUrl)

      this.ws.onopen = () => {
        console.log('WebSocket connected')
        this.onStatusChange?.(true)
        if (this.reconnectTimer) {
          clearTimeout(this.reconnectTimer)
          this.reconnectTimer = null
        }
      }

      this.ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          this.onMessageCallback?.(data)
        } catch (error) {
          console.error('Failed to parse WebSocket message:', error)
        }
      }

      this.ws.onerror = (error) => {
        console.error('WebSocket error:', error)
        this.onStatusChange?.(false)
      }

      this.ws.onclose = () => {
        console.log('WebSocket disconnected')
        this.onStatusChange?.(false)
        this.scheduleReconnect()
      }
    } catch (error) {
      console.error('Failed to connect WebSocket:', error)
      this.onStatusChange?.(false)
      this.scheduleReconnect()
    }
  }

  private scheduleReconnect() {
    if (this.reconnectTimer) return

    this.reconnectTimer = setTimeout(() => {
      console.log('Attempting to reconnect WebSocket...')
      if (this.onMessageCallback) {
        this.connect(this.onMessageCallback, this.onStatusChange || undefined)
      }
    }, this.reconnectDelay)
  }

  disconnect() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }

    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
  }

  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN
  }
}
