import type { LiveScore, Game } from '../api/types'
import { showToast } from '../utils/formatting'

/**
 * Live Sources view: which live-score source reports changes first and how far the
 * others lag (from LiveSourceStats on the server), plus per-game source pins for when a
 * feed is wrong. Backed by /api/admin/live-sources.
 */

interface SourceSummary {
  name: string
  wins: number
  follows: number
  averageLagSeconds: number
  maxLagSeconds: number
  behind: number
}

interface Race {
  eventID: string
  score: string
  first: string
  at: string
  followers: Record<string, number>
}

interface LiveSourcesResponse {
  since: string | null
  tickIntervalSeconds: number
  sources: SourceSummary[]
  recent: Race[]
  forced: Record<string, string>
  configured: Record<string, string[]>
}

const SOURCES = ['espn', 'fifa', 'mlb-statsapi', 'nhl-apiweb', 'nba-cdn']

export class LiveSources {
  private container: HTMLElement | null = null
  private refreshInterval: ReturnType<typeof setInterval> | null = null
  private liveGames: Game[] = []

  render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Live Sources</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-secondary" id="ls-reset" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Reset Stats</button>
            <button class="btn btn-primary" id="ls-refresh" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Every source configured for a league is polled each tick; the copy furthest along in game time wins.
          A <em>win</em> is a score change a source reported before any other; <em>lag</em> is how long a source took to catch up
          to one it didn't report first (resolution is the tick interval).
        </p>
        <div id="ls-content"><div class="loading">Loading...</div></div>
      </div>
    `
    this.container.querySelector('#ls-refresh')?.addEventListener('click', () => this.load())
    this.container.querySelector('#ls-reset')?.addEventListener('click', () => this.resetStats())
    this.load()
    this.refreshInterval = setInterval(() => this.load(), 10000)
  }

  stop() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
      this.refreshInterval = null
    }
  }

  private async load() {
    try {
      const [overview, live] = await Promise.all([
        this.request<LiveSourcesResponse>('/api/admin/live-sources'),
        this.request<LiveScore>('/api/admin/live-espn')
      ])
      this.liveGames = Object.values(live)
        .flatMap((bucket) => (bucket as { events?: Game[] } | undefined)?.events ?? [])
        .filter((game) => game.strStatus === 'in' && !!game.idEvent)
      this.renderContent(overview)
    } catch (error) {
      const content = this.container?.querySelector('#ls-content')
      if (content) {
        content.innerHTML = `<div class="badge error">${this.escapeHtml(error instanceof Error ? error.message : 'Failed to load')}</div>`
      }
    }
  }

  private renderContent(data: LiveSourcesResponse) {
    const content = this.container?.querySelector('#ls-content')
    if (!content) return

    const gameName = (id: string) => {
      const game = this.liveGames.find((g) => g.idEvent === id)
      return game ? `${game.strAwayTeam} @ ${game.strHomeTeam}` : id
    }
    const seconds = (value: number) => `${value.toFixed(1)}s`

    const sourceRows = data.sources.length
      ? data.sources.map((s) => `
          <tr>
            <td style="font-family: monospace;">${this.escapeHtml(s.name)}</td>
            <td>${s.wins}</td>
            <td>${s.follows}</td>
            <td>${seconds(s.averageLagSeconds)}</td>
            <td>${seconds(s.maxLagSeconds)}</td>
            <td>${s.behind}</td>
          </tr>`).join('')
      : `<tr><td colspan="6" style="color: var(--text-secondary);">No contested score changes yet.</td></tr>`

    const configured = Object.entries(data.configured)
    const configuredText = configured.length
      ? configured.map(([league, names]) => `${this.escapeHtml(league)}: ${names.map((n) => this.escapeHtml(n)).join(' + ')}`).join(' · ')
      : 'ESPN only (no LIVE_SOURCE_* overrides set)'

    const forcedRows = Object.entries(data.forced).map(([id, source]) => `
        <tr>
          <td>${this.escapeHtml(gameName(id))} <span style="color: var(--text-secondary); font-family: monospace;">${this.escapeHtml(id)}</span></td>
          <td style="font-family: monospace;">${this.escapeHtml(source)}</td>
          <td><button class="btn btn-secondary ls-unpin" data-event="${this.escapeHtml(id)}" style="padding: 0.25rem 0.75rem; font-size: 0.8rem;">Unpin</button></td>
        </tr>`).join('')

    const gameOptions = this.liveGames
      .map((g) => `<option value="${this.escapeHtml(g.idEvent ?? '')}">${this.escapeHtml(`${g.strAwayTeam} @ ${g.strHomeTeam}`)}</option>`)
      .join('')
    const sourceOptions = SOURCES.map((s) => `<option value="${s}">${s}</option>`).join('')

    const recentRows = data.recent.length
      ? data.recent.map((r) => `
          <tr>
            <td>${this.escapeHtml(gameName(r.eventID))}</td>
            <td>${this.escapeHtml(r.score)}</td>
            <td style="font-family: monospace;">${this.escapeHtml(r.first)}</td>
            <td>${Object.entries(r.followers).map(([n, lag]) => `${this.escapeHtml(n)} +${seconds(lag)}`).join(', ')}</td>
            <td>${this.escapeHtml(new Date(r.at).toLocaleTimeString())}</td>
          </tr>`).join('')
      : `<tr><td colspan="5" style="color: var(--text-secondary);">None yet — needs two sources covering the same live game.</td></tr>`

    content.innerHTML = `
      <p style="margin-bottom: 1rem;">
        Tick: <strong>${data.tickIntervalSeconds}s</strong>
        · Since: <strong>${data.since ? this.escapeHtml(new Date(data.since).toLocaleString()) : '—'}</strong>
        · Sources: ${configuredText}
      </p>
      <h3 style="margin: 1rem 0 0.5rem;">Sources</h3>
      <table>
        <thead><tr><th>Source</th><th>Wins</th><th>Follows</th><th>Avg lag</th><th>Max lag</th><th>Behind (dropped)</th></tr></thead>
        <tbody>${sourceRows}</tbody>
      </table>

      <h3 style="margin: 1.5rem 0 0.5rem;">Pinned games</h3>
      <div style="display: flex; gap: 0.5rem; align-items: center; margin-bottom: 0.75rem;">
        <select id="ls-game" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
          ${gameOptions || '<option value="">No live games</option>'}
        </select>
        <select id="ls-source" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
          ${sourceOptions}
        </select>
        <button class="btn btn-primary" id="ls-pin" style="padding: 0.5rem 1rem; font-size: 0.875rem;" ${gameOptions ? '' : 'disabled'}>Pin</button>
      </div>
      ${forcedRows
        ? `<table><thead><tr><th>Game</th><th>Source</th><th></th></tr></thead><tbody>${forcedRows}</tbody></table>`
        : '<p style="color: var(--text-secondary);">No pins. A pinned game takes only that source, ahead or behind.</p>'}

      <h3 style="margin: 1.5rem 0 0.5rem;">Recent contested changes</h3>
      <table>
        <thead><tr><th>Game</th><th>Score</th><th>First</th><th>Followers</th><th>At</th></tr></thead>
        <tbody>${recentRows}</tbody>
      </table>
    `

    content.querySelector('#ls-pin')?.addEventListener('click', () => this.pin())
    content.querySelectorAll('.ls-unpin').forEach((button) => {
      button.addEventListener('click', () => {
        const id = (button as HTMLElement).dataset.event
        if (id) this.unpin(id)
      })
    })
  }

  private async pin() {
    const eventID = (this.container?.querySelector('#ls-game') as HTMLSelectElement | null)?.value
    const source = (this.container?.querySelector('#ls-source') as HTMLSelectElement | null)?.value
    if (!eventID || !source) return
    try {
      await this.request('/api/admin/live-sources/forced', { method: 'PUT', body: JSON.stringify({ eventID, source }) })
      showToast(`Pinned to ${source}`, 'success')
      this.load()
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Pin failed', 'error')
    }
  }

  private async unpin(eventID: string) {
    try {
      await this.request(`/api/admin/live-sources/forced/${encodeURIComponent(eventID)}`, { method: 'DELETE' })
      showToast('Unpinned', 'success')
      this.load()
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Unpin failed', 'error')
    }
  }

  private async resetStats() {
    try {
      await this.request('/api/admin/live-sources/stats', { method: 'DELETE' }, false)
      showToast('Stats reset', 'success')
      this.load()
    } catch (error) {
      showToast(error instanceof Error ? error.message : 'Reset failed', 'error')
    }
  }

  private async request<T>(path: string, options?: RequestInit, json = true): Promise<T> {
    const response = await fetch(path, {
      ...options,
      headers: { 'Content-Type': 'application/json', ...options?.headers }
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    return (json ? response.json() : undefined) as Promise<T>
  }

  private escapeHtml(text: string): string {
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
  }
}
