import { apiClient } from '../api/client'
import { Leagues, LeagueNames, type LiveScore, type Game } from '../api/types'
import { formatDateTime, getStatusBadge, showToast } from '../utils/formatting'
import { logger } from '../utils/logger'

interface ComputedLeagueStats {
  league: string
  leagueId: number
  sport: string
  totalGames: number
  liveGames: number
  completedGames: number
  upcomingGames: number
  teams: string[]
}

export class LeagueExplorer {
  private container: HTMLElement | null = null
  private leagueStats: Map<number, ComputedLeagueStats> = new Map()
  private scheduleData: LiveScore | null = null
  private currentFilter: string = 'all'
  private selectedLeague: number | null = null
  private isLoading: boolean = false
  private selectedSeason: string = 'all'
  private selectedTeam: string = 'all'
  private expandedRaceSessions: Set<string> = new Set()

  async render(container: HTMLElement) {
    this.container = container
    logger.log('League Explorer initialized', 'info')

    this.showLoadingState()
    await this.loadData()
  }

  private showLoadingState() {
    if (!this.container) return
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
        </div>
        <div style="text-align: center; padding: 3rem; color: var(--text-secondary);">
          <div style="font-size: 2rem; margin-bottom: 1rem; animation: pulse 1.5s infinite;">Loading schedules...</div>
          <div style="font-size: 0.875rem;">Fetching data from server</div>
        </div>
      </div>
    `
  }

  private async loadData() {
    if (this.isLoading) return
    this.isLoading = true


    logger.log('Fetching schedules from /v2025/schedules...', 'info')

    try {
      const startTime = Date.now()
      const timeoutPromise = new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error('Request timed out after 15s')), 15000)
      )
      this.scheduleData = await Promise.race([apiClient.getSchedules(), timeoutPromise])
      const elapsed = Date.now() - startTime
      logger.log(`Schedules loaded in ${elapsed}ms`, 'success')

      this.computeAllStats()
      this.displayAllLeagues()
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      logger.log(`Failed to fetch schedules: ${errorMsg}`, 'error')

      this.showErrorState(errorMsg)
    } finally {
      this.isLoading = false
    }
  }

  private showErrorState(errorMsg: string) {
    if (!this.container) return
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
        </div>
        <div style="text-align: center; padding: 3rem;">
          <div style="font-size: 2rem; margin-bottom: 1rem; color: var(--danger-color);">Failed to load</div>
          <div style="color: var(--text-secondary); margin-bottom: 1.5rem;">${errorMsg}</div>
          <button class="btn btn-primary" id="retry-btn">Retry</button>
        </div>
      </div>
    `
    this.container.querySelector('#retry-btn')?.addEventListener('click', () => {
      this.showLoadingState()
      this.loadData()
    })
  }

  stop() {}

  /** Compute stats for all leagues client-side from schedule data */
  private computeAllStats() {
    this.leagueStats.clear()
    if (!this.scheduleData) return

    const computeForEvents = (events: Game[], league: Leagues) => {
      const teamSet = new Set<string>()
      const individual = this.isIndividualSport(league)
      let live = 0, completed = 0, upcoming = 0

      for (const game of events) {
        if (individual) {
          // For golf/tennis, strHomeTeam is the tournament/event name
          // For racing, extract GP name from session name
          if (game.strHomeTeam && game.strHomeTeam !== 'TBD') {
            const name = league === Leagues.Formula1 ? this.extractGPName(game.strHomeTeam) : game.strHomeTeam
            teamSet.add(name)
          }
        } else {
          if (game.strHomeTeam) teamSet.add(game.strHomeTeam)
          if (game.strAwayTeam) teamSet.add(game.strAwayTeam)
        }

        const status = (game.strStatus || '').toLowerCase()
        if (['ft', 'aot', 'final', 'final/ot', 'post', 'completed', 'finished', 'match finished', 'ap'].includes(status)) {
          completed++
        } else if (['ns', 'pre', '', 'scheduled', 'not started'].includes(status)) {
          upcoming++
        } else {
          live++
        }
      }

      this.leagueStats.set(league, {
        league: LeagueNames[league] || 'Unknown',
        leagueId: league,
        sport: this.getSportForLeague(league),
        totalGames: events.length,
        liveGames: live,
        completedGames: completed,
        upcomingGames: upcoming,
        teams: Array.from(teamSet).sort()
      })
    }

    // Single-league sports
    if (this.scheduleData.nba) computeForEvents(this.scheduleData.nba.events, Leagues.NBA)
    if (this.scheduleData.nfl) computeForEvents(this.scheduleData.nfl.events, Leagues.NFL)
    if (this.scheduleData.nhl) computeForEvents(this.scheduleData.nhl.events, Leagues.NHL)
    if (this.scheduleData.mlb) computeForEvents(this.scheduleData.mlb.events, Leagues.MLB)
    if (this.scheduleData.golf) computeForEvents(this.scheduleData.golf.events, Leagues.PGA)
    if (this.scheduleData.racing) computeForEvents(this.scheduleData.racing.events, Leagues.Formula1)

    // Multi-league sports: soccer & tennis — group by idLeague
    const groupByLeague = (events: Game[]) => {
      const groups = new Map<number, Game[]>()
      for (const game of events) {
        const leagueId = parseInt(game.idLeague || '0')
        if (!leagueId) continue
        const arr = groups.get(leagueId) || []
        arr.push(game)
        groups.set(leagueId, arr)
      }
      return groups
    }

    if (this.scheduleData.soccer) {
      const groups = groupByLeague(this.scheduleData.soccer.events)
      for (const [leagueId, games] of groups) {
        const league = leagueId as Leagues
        if (LeagueNames[league]) {
          computeForEvents(games, league)
        }
      }
    }

    if (this.scheduleData.tennis) {
      const groups = groupByLeague(this.scheduleData.tennis.events)
      for (const [leagueId, games] of groups) {
        const league = leagueId as Leagues
        if (LeagueNames[league]) {
          computeForEvents(games, league)
        }
      }
    }

    logger.log(`Computed stats for ${this.leagueStats.size} leagues`, 'success')
  }

  private displayAllLeagues() {
    if (!this.container) return

    const loadedCount = this.leagueStats.size
    const totalGames = Array.from(this.leagueStats.values()).reduce((s, l) => s + l.totalGames, 0)

    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Explorer</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            ${this.selectedLeague ? `<button class="btn btn-secondary" id="back-to-leagues" style="padding: 0.5rem 1rem; font-size: 0.875rem;">← Back</button>` : ''}
            <button class="btn btn-primary" id="refresh-leagues" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
            <span class="badge info">${loadedCount} Leagues</span>
            <span class="badge success">${totalGames.toLocaleString()} Games</span>
          </div>
        </div>

        <div id="main-content">
          ${this.selectedLeague ? this.renderLeagueDetail(this.selectedLeague) : this.renderLeagueGrid()}
        </div>
      </div>
    `

    this.container.querySelector('#refresh-leagues')?.addEventListener('click', () => {
      showToast('Refreshing leagues...', 'success')
      this.leagueStats.clear()
      this.showLoadingState()
      this.loadData()
    })

    if (this.selectedLeague) {
      this.container.querySelector('#back-to-leagues')?.addEventListener('click', () => {
        this.selectedLeague = null
        this.selectedSeason = 'all'
        this.selectedTeam = 'all'
        this.expandedRaceSessions.clear()
        this.displayAllLeagues()
      })

      this.container.querySelectorAll('[data-season]').forEach(btn => {
        btn.addEventListener('click', (e) => {
          this.selectedSeason = (e.target as HTMLElement).dataset.season || 'all'
          this.displayAllLeagues()
        })
      })

      this.container.querySelectorAll('[data-team]').forEach(btn => {
        btn.addEventListener('click', (e) => {
          this.selectedTeam = (e.target as HTMLElement).dataset.team || 'all'
          this.displayAllLeagues()
        })
      })

      this.container.querySelector('#clear-filters')?.addEventListener('click', () => {
        this.selectedSeason = 'all'
        this.selectedTeam = 'all'
        this.displayAllLeagues()
      })

      // Racing session expand/collapse
      this.container.querySelectorAll('[data-racing-session-id]').forEach(row => {
        row.addEventListener('click', () => {
          const sessionId = (row as HTMLElement).dataset.racingSessionId
          if (sessionId) {
            if (this.expandedRaceSessions.has(sessionId)) {
              this.expandedRaceSessions.delete(sessionId)
            } else {
              this.expandedRaceSessions.add(sessionId)
            }
            this.displayAllLeagues()
          }
        })
      })
    } else {
      this.container.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          const sport = (e.target as HTMLElement).dataset.sport
          if (sport) {
            this.currentFilter = sport
            this.displayAllLeagues()
          }
        })
      })

      this.container.querySelectorAll('[data-league-id]').forEach(card => {
        card.addEventListener('click', () => {
          const leagueId = (card as HTMLElement).dataset.leagueId
          if (leagueId) {
            this.selectedLeague = parseInt(leagueId)
            this.selectedSeason = 'all'
            this.selectedTeam = 'all'
            this.expandedRaceSessions.clear()
            this.displayAllLeagues()
          }
        })
      })
    }
  }

  private renderLeagueGrid(): string {
    return `
      <div style="display: flex; gap: 0.5rem; margin-bottom: 1.5rem; overflow-x: auto; padding: 0.25rem;">
        <button class="filter-btn ${this.currentFilter === 'all' ? 'active' : ''}" data-sport="all">All Sports</button>
        <button class="filter-btn ${this.currentFilter === 'basketball' ? 'active' : ''}" data-sport="basketball">Basketball</button>
        <button class="filter-btn ${this.currentFilter === 'football' ? 'active' : ''}" data-sport="football">Football</button>
        <button class="filter-btn ${this.currentFilter === 'hockey' ? 'active' : ''}" data-sport="hockey">Hockey</button>
        <button class="filter-btn ${this.currentFilter === 'baseball' ? 'active' : ''}" data-sport="baseball">Baseball</button>
        <button class="filter-btn ${this.currentFilter === 'soccer' ? 'active' : ''}" data-sport="soccer">Soccer</button>
        <button class="filter-btn ${this.currentFilter === 'golf' ? 'active' : ''}" data-sport="golf">Golf</button>
        <button class="filter-btn ${this.currentFilter === 'tennis' ? 'active' : ''}" data-sport="tennis">Tennis</button>
        <button class="filter-btn ${this.currentFilter === 'racing' ? 'active' : ''}" data-sport="racing">Racing</button>
      </div>

      <div id="leagues-container" class="grid grid-2">
        ${this.renderLeagueCards()}
      </div>
    `
  }

  private renderLeagueCards(): string {
    // Sort leagues: those with data first, then alphabetically
    const entries = Array.from(this.leagueStats.entries())
      .filter(([_, stats]) => {
        if (this.currentFilter === 'all') return true
        return stats.sport === this.currentFilter
      })
      .sort((a, b) => {
        // Live games first, then by total games desc, then by name
        if (a[1].liveGames !== b[1].liveGames) return b[1].liveGames - a[1].liveGames
        if (a[1].totalGames !== b[1].totalGames) return b[1].totalGames - a[1].totalGames
        return a[1].league.localeCompare(b[1].league)
      })

    if (entries.length === 0) {
      return `<div style="grid-column: 1 / -1; text-align: center; padding: 3rem; color: var(--text-secondary);">
        ${this.currentFilter === 'all' ? 'No schedule data loaded yet' : `No ${this.currentFilter} leagues found`}
      </div>`
    }

    return entries.map(([leagueId, stats]) => {
      const sportColor = this.getSportColor(stats.sport)
      return `
        <div class="card league-card" data-league-id="${leagueId}" style="border-left: 4px solid ${sportColor}; cursor: pointer; transition: transform 0.2s, box-shadow 0.2s;">
          <div style="display: flex; justify-content: space-between; align-items: start; margin-bottom: 1rem;">
            <div>
              <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 0.25rem;">${stats.league}</h3>
              <div style="font-size: 0.875rem; color: var(--text-secondary);">${this.capitalizeFirst(stats.sport)}</div>
            </div>
            <div style="display: flex; gap: 0.375rem;">
              ${stats.liveGames > 0 ? `<span class="badge success">${stats.liveGames} Live</span>` : ''}
              ${stats.totalGames === 0 ? `<span class="badge warning">No data</span>` : ''}
            </div>
          </div>

          <div class="grid grid-3" style="gap: 1rem;">
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--primary-color);">${stats.totalGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Total</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--success-color);">${stats.liveGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Live</div>
            </div>
            <div style="text-align: center;">
              <div style="font-size: 1.5rem; font-weight: 700; color: var(--warning-color);">${stats.upcomingGames}</div>
              <div style="font-size: 0.75rem; color: var(--text-secondary);">Upcoming</div>
            </div>
          </div>

          <div style="margin-top: 1rem; text-align: center; font-size: 0.875rem; color: var(--primary-color); font-weight: 500;">
            Click to view games →
          </div>
        </div>
      `
    }).join('')
  }

  private getSportForLeague(league: Leagues): string {
    switch (league) {
      case Leagues.NBA: return 'basketball'
      case Leagues.NFL: return 'football'
      case Leagues.NHL: return 'hockey'
      case Leagues.MLB: return 'baseball'
      case Leagues.PGA: return 'golf'
      case Leagues.ATP: case Leagues.WTA: return 'tennis'
      case Leagues.Formula1: return 'racing'
      default: return 'soccer'
    }
  }

  private isIndividualSport(league: Leagues): boolean {
    return league === Leagues.PGA || league === Leagues.ATP || league === Leagues.WTA || league === Leagues.Formula1
  }

  private isIndividualSportGame(game: Game): boolean {
    const leagueId = parseInt(game.idLeague || '0')
    return leagueId === Leagues.PGA || leagueId === Leagues.ATP || leagueId === Leagues.WTA || leagueId === Leagues.Formula1
  }

  private isRacingLeague(leagueId: number): boolean {
    return leagueId === Leagues.Formula1
  }

  private extractGPName(sessionName: string): string {
    return sessionName
      .replace(/\s+(Sprint Shootout|Sprint|FP1|FP2|FP3|Qual|Race)$/i, '')
      .trim()
  }

  private getSessionOrder(sessionName: string): number {
    const name = sessionName.toLowerCase()
    if (name.endsWith(' fp1')) return 0
    if (name.endsWith(' fp2')) return 1
    if (name.endsWith(' fp3')) return 2
    if (name.endsWith(' sprint shootout')) return 3
    if (name.endsWith(' sprint')) return 4
    if (name.endsWith(' qual')) return 5
    if (name.endsWith(' race')) return 6
    return 7
  }

  private getSessionLabel(sessionName: string): string {
    const name = sessionName.toLowerCase()
    if (name.endsWith(' fp1')) return 'Free Practice 1'
    if (name.endsWith(' fp2')) return 'Free Practice 2'
    if (name.endsWith(' fp3')) return 'Free Practice 3'
    if (name.endsWith(' sprint shootout')) return 'Sprint Shootout'
    if (name.endsWith(' sprint')) return 'Sprint'
    if (name.endsWith(' qual')) return 'Qualifying'
    if (name.endsWith(' race')) return 'Race'
    return sessionName
  }

  private groupRacingGamesByGP(games: Game[]): Map<string, Game[]> {
    const gpMap = new Map<string, Game[]>()
    for (const game of games) {
      const gpName = this.extractGPName(game.strHomeTeam || '')
      if (!gpName) continue
      const arr = gpMap.get(gpName) || []
      arr.push(game)
      gpMap.set(gpName, arr)
    }
    // Sort sessions within each GP
    for (const [, sessions] of gpMap) {
      sessions.sort((a, b) => this.getSessionOrder(a.strHomeTeam || '') - this.getSessionOrder(b.strHomeTeam || ''))
    }
    return gpMap
  }

  private getSportColor(sport: string): string {
    switch (sport) {
      case 'basketball': return '#1d428a'
      case 'football': return '#013369'
      case 'hockey': return '#000000'
      case 'baseball': return '#002d72'
      case 'soccer': return '#00a650'
      case 'golf': return '#2ca58d'
      case 'tennis': return '#c8b900'
      case 'racing': return '#e10600'
      default: return 'var(--primary-color)'
    }
  }

  private capitalizeFirst(str: string): string {
    return str.charAt(0).toUpperCase() + str.slice(1)
  }

  private getGamesForLeague(leagueId: number): Game[] {
    if (!this.scheduleData) return []

    if (leagueId === Leagues.NBA && this.scheduleData.nba) return this.scheduleData.nba.events
    if (leagueId === Leagues.NFL && this.scheduleData.nfl) return this.scheduleData.nfl.events
    if (leagueId === Leagues.NHL && this.scheduleData.nhl) return this.scheduleData.nhl.events
    if (leagueId === Leagues.MLB && this.scheduleData.mlb) return this.scheduleData.mlb.events
    if (leagueId === Leagues.PGA && this.scheduleData.golf) return this.scheduleData.golf.events
    if (leagueId === Leagues.Formula1 && this.scheduleData.racing) return this.scheduleData.racing.events

    // Tennis — filter by league ID
    if ((leagueId === Leagues.ATP || leagueId === Leagues.WTA) && this.scheduleData.tennis) {
      return this.scheduleData.tennis.events.filter(g => g.idLeague === String(leagueId))
    }

    // Soccer — filter by league ID
    if (this.scheduleData.soccer) {
      return this.scheduleData.soccer.events.filter(g => g.idLeague === String(leagueId))
    }

    return []
  }

  private renderLeagueDetail(leagueId: number): string {
    const stats = this.leagueStats.get(leagueId)
    const leagueName = LeagueNames[leagueId as Leagues] || 'Unknown League'
    const league = leagueId as Leagues

    if (!stats || !this.scheduleData) {
      return '<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No data available for this league</div>'
    }

    const allGames = this.getGamesForLeague(leagueId)

    // Extract unique seasons and teams
    const seasons = this.extractSeasons(allGames)
    const teams = this.extractTeams(allGames)

    const individual = this.isIndividualSport(league)
    const isRacing = this.isRacingLeague(leagueId)

    // Apply filters
    let games = allGames

    if (this.selectedSeason !== 'all') {
      games = games.filter(g => this.getGameSeason(g) === this.selectedSeason)
    }

    if (this.selectedTeam !== 'all') {
      games = games.filter(g => {
        if (isRacing) return this.extractGPName(g.strHomeTeam || '') === this.selectedTeam
        return individual
          ? g.strHomeTeam === this.selectedTeam
          : g.strHomeTeam === this.selectedTeam || g.strAwayTeam === this.selectedTeam
      })
    }

    // Group games by status
    const completedStatuses = ['ft', 'aot', 'final', 'final/ot', 'post', 'ap', 'completed', 'finished', 'match finished']
    const upcomingStatuses = ['ns', 'pre', '', 'scheduled', 'not started']

    const liveGames = games.filter(g => {
      const status = (g.strStatus || '').toLowerCase()
      return !completedStatuses.includes(status) && !upcomingStatuses.includes(status)
    })

    const upcomingGames = games.filter(g => {
      const status = (g.strStatus || '').toLowerCase()
      return upcomingStatuses.includes(status)
    }).sort((a, b) => {
      const dateA = new Date(a.isoDate || a.strTimestamp || 0).getTime()
      const dateB = new Date(b.isoDate || b.strTimestamp || 0).getTime()
      return dateA - dateB
    })

    const completedGames = games.filter(g => {
      const status = (g.strStatus || '').toLowerCase()
      return completedStatuses.includes(status)
    }).sort((a, b) => {
      const dateA = new Date(a.isoDate || a.strTimestamp || 0).getTime()
      const dateB = new Date(b.isoDate || b.strTimestamp || 0).getTime()
      return dateB - dateA // most recent first
    })

    const sport = this.getSportForLeague(league)
    const sportColor = this.getSportColor(sport)
    const hasActiveFilters = this.selectedSeason !== 'all' || this.selectedTeam !== 'all'

    // Group racing sessions by GP
    const liveGPGroups = isRacing ? this.groupRacingGamesByGP(liveGames) : null
    const upcomingGPGroups = isRacing ? this.groupRacingGamesByGP(upcomingGames) : null
    const completedGPGroups = isRacing ? this.groupRacingGamesByGP(completedGames) : null

    // Racing-specific label helpers
    const filterLabel = isRacing ? 'Grand Prix' : (individual ? 'Tournament' : 'Team')
    const filterLabelPlural = isRacing ? 'Grand Prix' : (individual ? 'Tournaments' : 'Teams')
    const itemLabel = isRacing ? 'sessions' : (individual ? 'events' : 'games')

    return `
      <div style="border-left: 4px solid ${sportColor}; padding-left: 1rem; margin-bottom: 1.5rem;">
        <h2 style="font-size: 1.5rem; font-weight: 700; margin-bottom: 0.25rem;">${leagueName}</h2>
        <div style="color: var(--text-secondary); font-size: 0.875rem;">${this.capitalizeFirst(sport)} &middot; ${allGames.length} total ${itemLabel} &middot; ${stats.teams.length} ${filterLabelPlural}</div>
      </div>

      <!-- Filter Controls -->
      <div style="margin-bottom: 1.5rem;">
        ${seasons.length > 1 ? `
          <div style="margin-bottom: 1rem;">
            <label style="display: block; font-size: 0.875rem; font-weight: 600; margin-bottom: 0.5rem;">Season</label>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedSeason === 'all' ? 'active' : ''}" data-season="all">All Seasons</button>
              ${seasons.map(season => `
                <button class="filter-btn ${this.selectedSeason === season ? 'active' : ''}" data-season="${season}">${season}</button>
              `).join('')}
            </div>
          </div>
        ` : ''}

        ${teams.length > 1 && teams.length <= 40 ? `
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
              <label style="font-size: 0.875rem; font-weight: 600;">${filterLabel}</label>
              ${hasActiveFilters ? `<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>` : ''}
            </div>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <button class="filter-btn ${this.selectedTeam === 'all' ? 'active' : ''}" data-team="all">All ${filterLabelPlural}</button>
              ${teams.map(team => `
                <button class="filter-btn ${this.selectedTeam === team ? 'active' : ''}" data-team="${team}">${team}</button>
              `).join('')}
            </div>
          </div>
        ` : hasActiveFilters ? `<button class="btn btn-secondary" id="clear-filters" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear Filters</button>` : ''}
      </div>

      <div class="grid grid-3" style="margin-bottom: 1.5rem;">
        <div class="stat-card">
          <div class="stat-value">${games.length}</div>
          <div class="stat-label">Games${hasActiveFilters ? ' (Filtered)' : ''}</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--success-color);">${liveGames.length}</div>
          <div class="stat-label">Live</div>
        </div>
        <div class="stat-card">
          <div class="stat-value" style="color: var(--warning-color);">${upcomingGames.length}</div>
          <div class="stat-label">Upcoming</div>
        </div>
      </div>

      ${liveGames.length > 0 ? `
        <div class="card" style="margin-bottom: 1.5rem; border-left: 4px solid var(--success-color);">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem; display: flex; align-items: center; gap: 0.5rem;">
            <span class="badge success">Live</span>
            ${isRacing && liveGPGroups ? `${liveGPGroups.size} Grand Prix In Progress (${liveGames.length} sessions)` : `${liveGames.length} Games In Progress`}
          </h3>
          <div style="display: grid; gap: 1rem;">
            ${isRacing && liveGPGroups
              ? Array.from(liveGPGroups.entries()).map(([gpName, sessions]) => this.renderRacingGPGroup(gpName, sessions, 'live')).join('')
              : liveGames.map(game => individual ? this.renderTournamentCard(game) : this.renderGameCard(game)).join('')}
          </div>
        </div>
      ` : ''}

      ${upcomingGames.length > 0 ? `
        <div class="card" style="margin-bottom: 1.5rem;">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${isRacing && upcomingGPGroups ? `Upcoming Grand Prix (${upcomingGPGroups.size} GPs, ${upcomingGames.length} sessions)` : `Upcoming ${individual ? 'Events' : 'Games'} (${upcomingGames.length})`}
          </h3>
          ${isRacing && upcomingGPGroups ? `
            <div>
              ${Array.from(upcomingGPGroups.entries()).map(([gpName, sessions]) => this.renderRacingGPGroup(gpName, sessions, 'upcoming')).join('')}
            </div>
          ` : `
            <table>
              <thead>
                <tr>
                  ${individual ? `
                    <th>Tournament</th>
                    <th>Status</th>
                    <th>Time</th>
                  ` : `
                    <th>Home Team</th>
                    <th>Away Team</th>
                    <th>Status</th>
                    <th>Time</th>
                  `}
                </tr>
              </thead>
              <tbody>
                ${upcomingGames.slice(0, 25).map(game => individual ? this.renderTournamentRow(game) : this.renderGameRow(game)).join('')}
              </tbody>
            </table>
            ${upcomingGames.length > 25 ? `<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${upcomingGames.length} upcoming ${individual ? 'events' : 'games'}</div>` : ''}
          `}
        </div>
      ` : ''}

      ${completedGames.length > 0 ? `
        <div class="card">
          <h3 style="font-size: 1.125rem; font-weight: 600; margin-bottom: 1rem;">
            ${isRacing && completedGPGroups ? `Completed Grand Prix (${completedGPGroups.size} GPs, ${completedGames.length} sessions)` : `Completed ${individual ? 'Events' : 'Games'} (${completedGames.length})`}
          </h3>
          ${isRacing && completedGPGroups ? `
            <div>
              ${Array.from(completedGPGroups.entries()).map(([gpName, sessions]) => this.renderRacingGPGroup(gpName, sessions, 'completed')).join('')}
            </div>
          ` : `
            <table>
              <thead>
                <tr>
                  ${individual ? `
                    <th>Tournament</th>
                    <th>Leader</th>
                    <th>Score</th>
                    <th>Status</th>
                  ` : `
                    <th>Home Team</th>
                    <th>Away Team</th>
                    <th>Score</th>
                    <th>Status</th>
                  `}
                </tr>
              </thead>
              <tbody>
                ${completedGames.slice(0, 25).map(game => individual ? this.renderTournamentRow(game) : this.renderGameRow(game)).join('')}
              </tbody>
            </table>
            ${completedGames.length > 25 ? `<div style="text-align: center; margin-top: 1rem; color: var(--text-secondary); font-size: 0.875rem;">Showing 25 of ${completedGames.length} completed ${individual ? 'events' : 'games'}</div>` : ''}
          `}
        </div>
      ` : ''}

      ${games.length === 0 ? '<div style="text-align: center; padding: 3rem; color: var(--text-secondary);">No games found for this league</div>' : ''}
    `
  }

  private renderGameCard(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)
    const homeScore = game.intHomeScore || '0'
    const awayScore = game.intAwayScore || '0'

    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; background-color: var(--surface-color);">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem;">
          <span class="${statusBadge.class}">${statusBadge.text}</span>
          <span style="font-size: 0.875rem; color: var(--text-secondary);">${game.strProgress || ''}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${game.strHomeTeamBadge ? `<img src="${game.strHomeTeamBadge}" alt="${game.strHomeTeam}" style="width: 32px; height: 32px; object-fit: contain;">` : ''}
            <span style="font-weight: 600;">${game.strHomeTeam}</span>
          </div>
          <span style="font-size: 1.75rem; font-weight: 700; min-width: 60px; text-align: center;">${homeScore}</span>
        </div>

        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.5rem; flex: 1;">
            ${game.strAwayTeamBadge ? `<img src="${game.strAwayTeamBadge}" alt="${game.strAwayTeam}" style="width: 32px; height: 32px; object-fit: contain;">` : ''}
            <span style="font-weight: 600;">${game.strAwayTeam}</span>
          </div>
          <span style="font-size: 1.75rem; font-weight: 700; min-width: 60px; text-align: center;">${awayScore}</span>
        </div>
      </div>
    `
  }

  private renderTournamentCard(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)

    // Parse leaderboard from lastPlay (format: "Name|Score\nName|Score\n...")
    const leaderboard = (game.lastPlay || '').split('\n')
      .filter(line => line.includes('|'))
      .map((line, index) => {
        const [name, score] = line.split('|')
        return { position: index + 1, name: name || 'TBD', score: score || '--' }
      })

    const leaderboardRows = leaderboard.length > 0
      ? leaderboard.map(entry => `
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0; ${entry.position === 1 ? 'font-weight: 600;' : 'color: var(--text-secondary);'}">
            <div style="display: flex; align-items: center; gap: 0.5rem;">
              <span style="width: 1.5rem; text-align: right; font-size: 0.8rem; color: var(--text-secondary);">${entry.position}</span>
              <span>${entry.name}</span>
            </div>
            <span style="font-weight: 500;">${entry.score}</span>
          </div>
        `).join('')
      : game.strAwayTeam && game.strAwayTeam !== 'TBD'
        ? `<div style="display: flex; justify-content: space-between; align-items: center; padding: 0.25rem 0;">
              <span>${game.strAwayTeam}</span>
              <span style="font-weight: 600;">${game.intAwayScore || '--'}</span>
           </div>`
        : ''

    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.375rem; padding: 1rem; background-color: var(--surface-color);">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
          <span style="font-weight: 600; font-size: 1.1rem;">${game.strHomeTeam}</span>
          <span class="${statusBadge.class}">${statusBadge.text}</span>
        </div>
        ${game.strProgress ? `<div style="font-size: 0.8rem; color: var(--text-secondary); margin-bottom: 0.5rem;">${game.strProgress}</div>` : ''}
        ${leaderboardRows ? `<div style="border-top: 1px solid var(--border-color); padding-top: 0.5rem;">${leaderboardRows}</div>` : ''}
      </div>
    `
  }

  private renderGameRow(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)
    const homeScore = game.intHomeScore || '-'
    const awayScore = game.intAwayScore || '-'

    return `
      <tr>
        <td>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${game.strHomeTeamBadge ? `<img src="${game.strHomeTeamBadge}" alt="${game.strHomeTeam}" style="width: 20px; height: 20px; object-fit: contain;">` : ''}
            <span>${game.strHomeTeam}</span>
          </div>
        </td>
        <td>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            ${game.strAwayTeamBadge ? `<img src="${game.strAwayTeamBadge}" alt="${game.strAwayTeam}" style="width: 20px; height: 20px; object-fit: contain;">` : ''}
            <span>${game.strAwayTeam}</span>
          </div>
        </td>
        <td>${homeScore} - ${awayScore}</td>
        <td><span class="${statusBadge.class}">${statusBadge.text}</span></td>
        <td style="font-size: 0.875rem;">${game.strProgress || formatDateTime(game.strTimestamp)}</td>
      </tr>
    `
  }

  private renderTournamentRow(game: Game): string {
    const statusBadge = getStatusBadge(game.strStatus)
    const leader = game.strAwayTeam !== 'TBD' ? game.strAwayTeam : ''
    const score = game.intAwayScore || '-'

    return `
      <tr>
        <td>
          <span style="font-weight: 500;">${game.strHomeTeam}</span>
        </td>
        ${leader ? `<td>${leader}</td><td>${score}</td>` : `<td colspan="2" style="color: var(--text-secondary);">-</td>`}
        <td><span class="${statusBadge.class}">${statusBadge.text}</span></td>
        <td style="font-size: 0.875rem;">${game.strProgress || formatDateTime(game.strTimestamp)}</td>
      </tr>
    `
  }

  private renderRacingLeaderboard(game: Game): string {
    const lines = (game.lastPlay || '').split('\n').filter(line => line.includes('|'))
    if (lines.length === 0) return '<div style="padding: 0.5rem; color: var(--text-secondary); font-size: 0.8rem;">No leaderboard data</div>'

    // Format: DriverName|Score|Gap|ConstructorName
    const entries = lines.map((line, index) => {
      const parts = line.split('|')
      return {
        position: index + 1,
        name: parts[0] || '',
        score: parts[1] || '',
        gap: parts[2] || '',
        constructor: parts[3] || ''
      }
    })

    return `
      <table style="width: 100%; font-size: 0.8rem; margin-top: 0.5rem; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid var(--border-color);">
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600; width: 2rem;">Pos</th>
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600;">Driver</th>
            <th style="text-align: left; padding: 0.25rem 0.5rem; font-weight: 600;">Constructor</th>
            <th style="text-align: right; padding: 0.25rem 0.5rem; font-weight: 600;">Score</th>
            <th style="text-align: right; padding: 0.25rem 0.5rem; font-weight: 600;">Gap</th>
          </tr>
        </thead>
        <tbody>
          ${entries.map(entry => `
            <tr style="${entry.position === 1 ? 'font-weight: 600;' : 'color: var(--text-secondary);'} ${entry.position <= 3 ? 'background-color: rgba(225, 6, 0, 0.03);' : ''}">
              <td style="padding: 0.2rem 0.5rem;">${entry.position}</td>
              <td style="padding: 0.2rem 0.5rem;">${entry.name}</td>
              <td style="padding: 0.2rem 0.5rem; font-size: 0.75rem;">${entry.constructor || '-'}</td>
              <td style="text-align: right; padding: 0.2rem 0.5rem;">${entry.score || '-'}</td>
              <td style="text-align: right; padding: 0.2rem 0.5rem;">${entry.gap || '-'}</td>
            </tr>
          `).join('')}
        </tbody>
      </table>
    `
  }

  private renderRacingGPGroup(gpName: string, sessions: Game[], sectionType: 'live' | 'upcoming' | 'completed'): string {
    const raceSession = sessions.find(s => (s.strHomeTeam || '').toLowerCase().endsWith(' race'))
    const firstSession = sessions[0]
    const date = firstSession ? formatDateTime(firstSession.strTimestamp) : ''

    // Find winner for completed GPs
    let winner = ''
    let winnerConstructor = ''
    if (sectionType === 'completed' && raceSession) {
      const lines = (raceSession.lastPlay || '').split('\n').filter(l => l.includes('|'))
      if (lines.length > 0) {
        const parts = lines[0].split('|')
        winner = parts[0] || ''
        winnerConstructor = parts[3] || ''
      } else if (raceSession.strAwayTeam && raceSession.strAwayTeam !== 'TBD') {
        winner = raceSession.strAwayTeam
      }
    }

    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.5rem; margin-bottom: 0.75rem; overflow: hidden;">
        <div style="padding: 0.75rem 1rem; background: linear-gradient(135deg, rgba(225, 6, 0, 0.05), transparent); border-bottom: 1px solid var(--border-color);">
          <div style="display: flex; justify-content: space-between; align-items: center;">
            <div>
              <div style="font-weight: 700; font-size: 1rem;">${gpName}</div>
              ${winner ? `<div style="font-size: 0.8rem; color: var(--text-secondary); margin-top: 0.125rem;">Winner: <span style="font-weight: 600; color: var(--text-primary);">${winner}</span>${winnerConstructor ? ` <span style="font-size: 0.75rem; color: var(--text-secondary);">(${winnerConstructor})</span>` : ''}</div>` : ''}
            </div>
            <div style="display: flex; gap: 0.5rem; align-items: center;">
              <span style="font-size: 0.75rem; color: var(--text-secondary);">${date}</span>
              <span class="badge info" style="font-size: 0.7rem;">${sessions.length} sessions</span>
            </div>
          </div>
        </div>
        <div style="padding: 0;">
          ${sessions.map(game => this.renderRacingSessionRow(game, sectionType)).join('')}
        </div>
      </div>
    `
  }

  private renderRacingSessionRow(game: Game, sectionType: 'live' | 'upcoming' | 'completed'): string {
    const label = this.getSessionLabel(game.strHomeTeam || '')
    const statusBadge = getStatusBadge(game.strStatus)
    const isRace = (game.strHomeTeam || '').toLowerCase().endsWith(' race')
    const isExpanded = this.expandedRaceSessions.has(game.idEvent || '')
    const hasLeaderboard = sectionType === 'completed' && (game.lastPlay || '').includes('|')
    const isClickable = hasLeaderboard

    // Get leader for completed
    let leader = ''
    let leaderConstructor = ''
    let leaderScore = ''
    if (sectionType === 'completed') {
      const lines = (game.lastPlay || '').split('\n').filter(l => l.includes('|'))
      if (lines.length > 0) {
        const parts = lines[0].split('|')
        leader = parts[0] || ''
        leaderScore = parts[1] || ''
        leaderConstructor = parts[3] || ''
      } else if (game.strAwayTeam && game.strAwayTeam !== 'TBD') {
        leader = game.strAwayTeam
      }
    }

    const bgColor = isRace ? 'rgba(225, 6, 0, 0.04)' : 'transparent'

    return `
      <div ${isClickable ? `data-racing-session-id="${game.idEvent}"` : ''} style="padding: 0.5rem 1rem; border-bottom: 1px solid var(--border-color); background-color: ${bgColor}; ${isClickable ? 'cursor: pointer;' : ''} display: flex; flex-direction: column; transition: background-color 0.15s;">
        <div style="display: flex; justify-content: space-between; align-items: center;">
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            ${isClickable ? `<span style="font-size: 0.7rem; color: var(--text-secondary); transition: transform 0.2s; transform: rotate(${isExpanded ? '90' : '0'}deg); display: inline-block;">&#9654;</span>` : '<span style="width: 0.7rem; display: inline-block;"></span>'}
            <span style="font-weight: ${isRace ? '600' : '500'}; font-size: 0.875rem;">${label}</span>
            ${leader && !isExpanded ? `<span style="font-size: 0.8rem; color: var(--text-secondary);">${leader}${leaderConstructor ? ` <span style="font-size: 0.75rem;">(${leaderConstructor})</span>` : ''}${leaderScore ? ` <span style="font-size: 0.75rem; color: var(--text-secondary);">P${leaderScore}</span>` : ''}</span>` : ''}
          </div>
          <div style="display: flex; align-items: center; gap: 0.5rem;">
            <span style="font-size: 0.8rem; color: var(--text-secondary);">${game.strProgress || formatDateTime(game.strTimestamp)}</span>
            <span class="${statusBadge.class}" style="font-size: 0.7rem;">${statusBadge.text}</span>
          </div>
        </div>
        ${isExpanded ? `<div style="padding: 0.5rem 0 0.25rem 2rem;">${this.renderRacingLeaderboard(game)}</div>` : ''}
      </div>
    `
  }

  private extractSeasons(games: Game[]): string[] {
    const seasons = new Set<string>()
    for (const game of games) {
      const season = this.getGameSeason(game)
      if (season) seasons.add(season)
    }
    return Array.from(seasons).sort().reverse()
  }

  private extractTeams(games: Game[]): string[] {
    const teams = new Set<string>()
    const leagueId = parseInt(games[0]?.idLeague || '0')
    const racing = this.isRacingLeague(leagueId)
    for (const game of games) {
      if (racing) {
        // For F1, use GP names instead of raw session names
        const gpName = this.extractGPName(game.strHomeTeam || '')
        if (gpName) teams.add(gpName)
      } else if (this.isIndividualSportGame(game)) {
        // For golf/tennis, only use tournament names (strHomeTeam), not player names
        if (game.strHomeTeam && game.strHomeTeam !== 'TBD') teams.add(game.strHomeTeam)
      } else {
        if (game.strHomeTeam) teams.add(game.strHomeTeam)
        if (game.strAwayTeam) teams.add(game.strAwayTeam)
      }
    }
    return Array.from(teams).sort()
  }

  private getGameSeason(game: Game): string | null {
    const timestamp = game.strTimestamp || game.isoDate
    if (!timestamp) return null
    try {
      const date = new Date(timestamp)
      const year = date.getFullYear()
      const month = date.getMonth() + 1
      if (month >= 8) return `${year}-${year + 1}`
      return `${year - 1}-${year}`
    } catch {
      return null
    }
  }
}
