import { WebSocketManager } from '../api/client'
import type { LiveScore, Game } from '../api/types'
import { getStatusBadge, showToast } from '../utils/formatting'
import { logger } from '../utils/logger'

export class LiveGames {
  private container: HTMLElement | null = null
  private wsManager: WebSocketManager
  private connectionStatus: HTMLElement | null = null
  private useWebSocket: boolean = true
  private refreshInterval: ReturnType<typeof setInterval> | null = null

  constructor() {
    this.wsManager = new WebSocketManager()
    this.connectionStatus = document.getElementById('connection-status')
  }

  render(container: HTMLElement) {
    this.container = container
    logger.log('Live Games initialized', 'info')

    // Show initial UI immediately
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Live Games</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-primary" id="refresh-live" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
            <button class="btn btn-secondary" id="toggle-mode" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Mode</button>
            <span class="badge info" id="ws-status">Loading...</span>
          </div>
        </div>
        <div id="live-games-content" style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div class="loading">Loading live games...</div>
        </div>
      </div>
    `

    // Add button listeners
    this.container.querySelector('#refresh-live')?.addEventListener('click', () => this.manualRefresh())
    this.container.querySelector('#toggle-mode')?.addEventListener('click', () => this.toggleMode())

    // Start with API polling (more reliable)
    this.fetchLiveGames()
    this.refreshInterval = setInterval(() => this.fetchLiveGames(), 10000)
  }

  private toggleMode() {
    this.useWebSocket = !this.useWebSocket

    if (this.useWebSocket) {
      logger.log('Switching to WebSocket mode', 'info')
      showToast('Using WebSocket for live updates', 'success')
      if (this.refreshInterval) {
        clearInterval(this.refreshInterval)
        this.refreshInterval = null
      }
      this.wsManager.connect(
        (data) => this.handleLiveData(data),
        (connected) => this.updateConnectionStatus(connected)
      )
    } else {
      logger.log('Switching to polling mode', 'info')
      showToast('Using API polling (10s refresh)', 'success')
      this.wsManager.disconnect()
      if (!this.refreshInterval) {
        this.refreshInterval = setInterval(() => this.fetchLiveGames(), 10000)
      }
      this.fetchLiveGames()
    }
  }

  private async manualRefresh() {
    logger.log('Manual refresh triggered', 'info')
    showToast('Refreshing live games...', 'success')
    await this.fetchLiveGames()
  }

  private async fetchLiveGames() {
    logger.log('Fetching live games...', 'info')
    const startTime = Date.now()

    try {
      const timeoutPromise = new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('Request timed out after 10s')), 10000)
      )
      const fetchPromise = fetch('/api/admin/live-espn').then(async (response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        return response.json() as Promise<LiveScore>
      })

      const allGames = await Promise.race([fetchPromise, timeoutPromise])
      const elapsed = Date.now() - startTime
      logger.log(`All games fetched in ${elapsed}ms`, 'success')

      // Filter for only live games
      const filterLive = (events: Game[] = []) => {
        return events.filter(game => {
          const status = game.strStatus || ''
          return status === 'in' || /^(Q[1-4]|OT|Half|P[1-3])/.test(status)
        })
      }

      const liveData: LiveScore = {
        nba: allGames.nba ? { events: filterLive(allGames.nba.events) } : undefined,
        nfl: allGames.nfl ? { events: filterLive(allGames.nfl.events) } : undefined,
        nhl: allGames.nhl ? { events: filterLive(allGames.nhl.events) } : undefined,
        mlb: allGames.mlb ? { events: filterLive(allGames.mlb.events) } : undefined,
        soccer: allGames.soccer ? { events: filterLive(allGames.soccer.events) } : undefined,
        golf: allGames.golf ? { events: filterLive(allGames.golf.events) } : undefined,
        tennis: allGames.tennis ? { events: filterLive(allGames.tennis.events) } : undefined,
        racing: allGames.racing ? { events: filterLive(allGames.racing.events) } : undefined
      }

      this.handleLiveData(liveData, allGames)
    } catch (error) {
      const elapsed = Date.now() - startTime
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      logger.log(`Failed to fetch live games after ${elapsed}ms: ${errorMsg}`, 'error')

      const content = this.container?.querySelector('#live-games-content')
      if (content) {
        content.innerHTML = `
          <div style="text-align: center; padding: 3rem;">
            <div style="font-size: 2rem; margin-bottom: 1rem; color: var(--danger-color);">Failed to load</div>
            <div style="color: var(--text-secondary); margin-bottom: 1rem;">${errorMsg}</div>
            <button class="btn btn-primary" id="retry-live">Retry</button>
          </div>
        `
        content.querySelector('#retry-live')?.addEventListener('click', () => this.manualRefresh())
      }
    }
  }

  stop() {
    this.wsManager.disconnect()
    this.updateConnectionStatus(false)
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
      this.refreshInterval = null
    }
  }

  private updateConnectionStatus(connected: boolean) {
    if (this.connectionStatus) {
      this.connectionStatus.className = `status-indicator ${connected ? 'connected' : 'disconnected'}`
    }
    const statusBadge = this.container?.querySelector('#ws-status')
    if (statusBadge) {
      statusBadge.className = connected ? 'badge success' : 'badge warning'
      statusBadge.textContent = connected ? 'Connected' : 'Disconnected'
    }
  }

  private handleLiveData(liveData: LiveScore, allData?: LiveScore) {
    if (!this.container) return

    const sports = [
      { name: 'NBA', data: liveData.nba, allData: allData?.nba, color: '#1d428a' },
      { name: 'NFL', data: liveData.nfl, allData: allData?.nfl, color: '#013369' },
      { name: 'NHL', data: liveData.nhl, allData: allData?.nhl, color: '#000000' },
      { name: 'MLB', data: liveData.mlb, allData: allData?.mlb, color: '#002d72' },
      { name: 'Soccer', data: liveData.soccer, allData: allData?.soccer, color: '#00a650' },
      { name: 'Golf', data: liveData.golf, allData: allData?.golf, color: '#2ca58d' },
      { name: 'Tennis', data: liveData.tennis, allData: allData?.tennis, color: '#c8b900' },
      { name: 'Formula 1', data: liveData.racing, allData: allData?.racing, color: '#e10600' }
    ]

    const liveGamesCount = sports.reduce((sum, sport) =>
      sum + (sport.data?.events?.length || 0), 0
    )
    const totalGamesCount = sports.reduce((sum, sport) =>
      sum + (sport.allData?.events?.length || 0), 0
    )

    logger.log(`Displaying ${liveGamesCount} live games (${totalGamesCount} total)`, liveGamesCount > 0 ? 'success' : 'info')

    const content = this.container?.querySelector('#live-games-content')
    const statusBadge = this.container?.querySelector('#ws-status')

    if (statusBadge) {
      statusBadge.className = `badge ${liveGamesCount > 0 ? 'success' : 'info'}`
      statusBadge.textContent = `${liveGamesCount} Live${totalGamesCount > 0 ? ` / ${totalGamesCount} Total` : ''}`
    }

    if (content) {
      // Show sport summary cards even when no live games
      const sportSummaries = sports
        .filter(s => (s.allData?.events?.length || 0) > 0 || (s.data?.events?.length || 0) > 0)
        .map(s => {
          const liveCount = s.data?.events?.length || 0
          const totalCount = s.allData?.events?.length || 0
          return `<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.5rem 0; border-bottom: 1px solid var(--border-color);">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 4px; height: 24px; background: ${s.color}; border-radius: 2px;"></span>
              <span style="font-weight: 500;">${s.name}</span>
            </div>
            <div style="display: flex; gap: 0.5rem;">
              ${liveCount > 0 ? `<span class="badge success">${liveCount} Live</span>` : ''}
              <span class="badge info">${totalCount} Games</span>
            </div>
          </div>`
        }).join('')

      const liveContent = liveGamesCount > 0
        ? sports.map(sport => this.renderSportSection(sport.name, sport.data, sport.color)).join('')
        : ''

      content.innerHTML = `
        ${sportSummaries ? `
          <div style="margin-bottom: 1.5rem;">
            <h3 style="font-size: 1rem; font-weight: 600; margin-bottom: 0.75rem; color: var(--text-secondary);">Live Scoreboard Summary</h3>
            ${sportSummaries}
          </div>
        ` : ''}

        ${liveContent || `
          <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
            <div style="font-weight: 600; margin-bottom: 0.5rem;">No live games at the moment</div>
            <div style="font-size: 0.875rem;">Auto-refreshing every 10 seconds</div>
          </div>
        `}
      `

      // Add click delegation for expandable tournament cards
      content.querySelectorAll('[data-tournament-id]').forEach(card => {
        card.addEventListener('click', (e) => {
          // Don't toggle if clicking a button or link inside the card
          if ((e.target as HTMLElement).closest('button, a')) return
          const collapsed = card.querySelector('.tournament-collapsed')
          const expanded = card.querySelector('.tournament-expanded')
          if (collapsed && expanded) {
            collapsed.classList.toggle('hidden')
            expanded.classList.toggle('hidden')
          }
        })
      })
    }
  }

  private renderSportSection(sportName: string, data: any, color: string): string {
    if (!data || !data.events || data.events.length === 0) {
      return ''
    }

    return `
      <div class="card">
        <div class="card-header" style="border-left: 4px solid ${color};">
          <h3 class="card-title">${sportName}</h3>
          <span class="badge info">${data.events.length} Games</span>
        </div>
        <div style="display: grid; gap: 1rem;">
          ${data.events.map((game: Game) => this.renderGame(game, sportName)).join('')}
        </div>
      </div>
    `
  }

  private renderGame(game: Game, sportName: string): string {
    if (sportName === 'Golf' || sportName === 'Tennis' || sportName === 'Formula 1') {
      return this.renderTournamentGame(game)
    }
    return this.renderTeamGame(game)
  }

  private renderTeamGame(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)
    const homeScore = game.intHomeScore || '0'
    const awayScore = game.intAwayScore || '0'

    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span class="${statusBadge.class}">${statusBadge.text}</span>
          <span style="font-size: 0.875rem; color: var(--text-secondary);">${game.strProgress || ''}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${game.strHomeTeamBadge ? `<img src="${game.strHomeTeamBadge}" alt="${game.strHomeTeam}" style="width: 24px; height: 24px;">` : ''}
            <span style="font-weight: 500;">${game.strHomeTeam}</span>
          </div>
          <span style="font-size: 1.25rem; font-weight: 700;">${homeScore}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${game.strAwayTeamBadge ? `<img src="${game.strAwayTeamBadge}" alt="${game.strAwayTeam}" style="width: 24px; height: 24px;">` : ''}
            <span style="font-weight: 500;">${game.strAwayTeam}</span>
          </div>
          <span style="font-size: 1.25rem; font-weight: 700;">${awayScore}</span>
        </div>
        ${(game.aggregateScore || game.legDisplay) ? `
        <div style="margin-top: 0.5rem; font-size: 0.75rem; color: var(--text-secondary);">
          ${[game.legDisplay, game.aggregateScore].filter(Boolean).join(' · ')}
        </div>` : ''}
      </div>
    `
  }

  private renderTournamentGame(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)
    const gameId = game.idEvent || Math.random().toString(36).slice(2)

    // Parse leaderboard from lastPlay (format: "Name|Score|R1,R2,R3\n...")
    const leaderboard = (game.lastPlay || '').split('\n')
      .filter(line => line.includes('|'))
      .map((line, index) => {
        const parts = line.split('|')
        const name = parts[0] || 'TBD'
        const score = parts[1] || '--'
        const rounds = parts[2] ? parts[2].split(',') : []
        return { position: index + 1, name, score, rounds }
      })

    const hasRounds = leaderboard.some(e => e.rounds.length > 0)
    const maxRounds = Math.max(0, ...leaderboard.map(e => e.rounds.length))

    // Collapsed view: top 5
    const collapsedRows = leaderboard.length > 0
      ? leaderboard.slice(0, 5).map(entry => `
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0; ${entry.position === 1 ? 'font-weight: 600;' : 'color: var(--text-secondary);'}">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${entry.position}</span>
              <span>${entry.name}</span>
            </div>
            <span style="font-weight: 500;">${entry.score}</span>
          </div>
        `).join('')
      : `<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0;">
            <span>${game.strAwayTeam}</span>
            <span style="font-weight: 600;">${game.intAwayScore || '--'}</span>
         </div>`

    // Expanded view: full leaderboard with round columns
    const roundHeaders = hasRounds
      ? Array.from({ length: maxRounds }, (_, i) => `<span style="width: 2.5rem; text-align: right; font-size: 0.75rem;">R${i + 1}</span>`).join('')
      : ''

    const expandedRows = leaderboard.map(entry => {
      const roundCells = hasRounds
        ? Array.from({ length: maxRounds }, (_, i) =>
            `<span style="width: 2.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${entry.rounds[i] || '-'}</span>`
          ).join('')
        : ''
      return `
        <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; ${entry.position === 1 ? 'font-weight: 600;' : 'color: var(--text-secondary);'}">
          <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${entry.position}</span>
          <span style="flex: 1;">${entry.name}</span>
          <span style="width: 3rem; text-align: right; font-weight: 500;">${entry.score}</span>
          ${roundCells}
        </div>
      `
    }).join('')

    const showExpand = leaderboard.length > 5

    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; cursor: ${showExpand ? 'pointer' : 'default'};" data-tournament-id="${gameId}">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span style="font-weight: 600; font-size: 1rem;">${game.strHomeTeam}</span>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${showExpand ? '<span style="font-size: 0.75rem; color: var(--text-secondary);">Click to expand</span>' : ''}
            <span class="${statusBadge.class}">${statusBadge.text}</span>
          </div>
        </div>
        ${game.strProgress ? `<div style="font-size: 0.8rem; color: var(--text-secondary); margin-bottom: 0.5rem;">${game.strProgress}</div>` : ''}
        <div class="tournament-collapsed" style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">
          ${collapsedRows}
        </div>
        <div class="tournament-expanded hidden" style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">
          ${hasRounds ? `
            <div style="display: flex; align-items: center; gap: 0.5rem; padding: 0.25rem 0; font-size: 0.75rem; color: var(--text-secondary); border-bottom: 1px solid var(--border-color); margin-bottom: 0.25rem;">
              <span style="width: 1.5rem; text-align: right;">Pos</span>
              <span style="flex: 1;">Player</span>
              <span style="width: 3rem; text-align: right;">Score</span>
              ${roundHeaders}
            </div>
          ` : ''}
          ${expandedRows}
        </div>
      </div>
    `
  }
}
