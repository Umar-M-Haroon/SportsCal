/**
 * World Cup Status view: a fast health check that the World Cup enrichment pipeline
 * is flowing. Hits the public endpoints (group standings, bracket, scorers) and shows
 * group count (expect 12 at the 2026 tournament), bracket round/match counts, and the
 * Golden Boot list size. Use this to confirm data before opening the app.
 */

interface BracketMatch {
  homeTeamName?: string | null
  awayTeamName?: string | null
}
interface BracketRound {
  roundName: string
  matches: BracketMatch[]
}
interface Bracket {
  rounds: BracketRound[]
  thirdPlacePlayoff?: BracketMatch | null
}
interface Scorer {
  rank: number
  playerName: string
  teamName: string
  goals: number
}
interface StandingChild {
  name?: string
  standings?: { entries?: unknown[] }
}
interface Standing {
  standings?: { children?: StandingChild[] }
}

export class WorldCupStatus {
  private container: HTMLElement | null = null

  render(container: HTMLElement) {
    this.container = container
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">World Cup 2026 Status</h2>
          <button class="btn btn-primary" id="wc-refresh" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Refresh</button>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Verifies the World Cup enrichment pipeline (group standings, knockout bracket, Golden Boot).
          Group count should be 12 once the 2026 group draw is published.
        </p>
        <div id="wc-content">Loading…</div>
      </div>
    `
    container.querySelector('#wc-refresh')?.addEventListener('click', () => this.load())
    this.load()
  }

  stop() {}

  private async load() {
    const content = this.container?.querySelector('#wc-content')
    if (!content) return
    content.innerHTML = 'Loading…'

    const [standing, bracket, scorers] = await Promise.all([
      this.fetchJSON<Standing>('/v2025/standings/4429'),
      this.fetchJSON<Bracket>('/v2025/worldcup/bracket'),
      this.fetchJSON<Scorer[]>('/v2025/worldcup/scorers')
    ])

    const groups = standing?.standings?.children?.filter(c => (c.standings?.entries?.length ?? 0) > 0) ?? []
    const rounds = bracket?.rounds ?? []
    const matchCount = rounds.reduce((n, r) => n + (r.matches?.length ?? 0), 0)
    const topScorers = scorers ?? []

    content.innerHTML = `
      <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin-bottom: 1rem;">
        ${this.stat('Groups', `${groups.length}`, groups.length === 12 ? 'ok' : (groups.length > 0 ? 'warn' : 'bad'))}
        ${this.stat('Bracket rounds', `${rounds.length}`, rounds.length > 0 ? 'ok' : 'warn')}
        ${this.stat('Knockout matches', `${matchCount}`, matchCount > 0 ? 'ok' : 'warn')}
        ${this.stat('Third place', bracket?.thirdPlacePlayoff ? 'yes' : 'no', bracket?.thirdPlacePlayoff ? 'ok' : 'warn')}
        ${this.stat('Top scorers', `${topScorers.length}`, topScorers.length > 0 ? 'ok' : 'warn')}
      </div>
      ${this.groupsTable(groups)}
      ${this.roundsTable(rounds)}
      ${this.scorersTable(topScorers)}
    `
  }

  private async fetchJSON<T>(path: string): Promise<T | null> {
    try {
      const res = await fetch(path, { headers: { 'Content-Type': 'application/json' } })
      if (!res.ok) return null
      return (await res.json()) as T
    } catch {
      return null
    }
  }

  private stat(label: string, value: string, level: 'ok' | 'warn' | 'bad'): string {
    const color = level === 'ok' ? 'var(--success-color, #1f8b3f)' : level === 'warn' ? 'var(--warning-color, #b8860b)' : 'var(--error-color, #d63b2f)'
    return `
      <div style="border: 1px solid var(--border-color); border-radius: 0.5rem; padding: 0.75rem;">
        <div style="font-size: 0.75rem; color: var(--text-secondary); text-transform: uppercase;">${label}</div>
        <div style="font-size: 1.5rem; font-weight: 700; color: ${color};">${value}</div>
      </div>
    `
  }

  private groupsTable(groups: StandingChild[]): string {
    if (groups.length === 0) return ''
    const rows = groups.map(g => `<li>${g.name ?? 'Group'} — ${g.standings?.entries?.length ?? 0} teams</li>`).join('')
    return `<h3 style="margin-top:1rem;">Groups</h3><ul style="color: var(--text-secondary);">${rows}</ul>`
  }

  private roundsTable(rounds: BracketRound[]): string {
    if (rounds.length === 0) return ''
    const rows = rounds.map(r => `<li>${r.roundName} — ${r.matches?.length ?? 0} matches</li>`).join('')
    return `<h3 style="margin-top:1rem;">Bracket</h3><ul style="color: var(--text-secondary);">${rows}</ul>`
  }

  private scorersTable(scorers: Scorer[]): string {
    if (scorers.length === 0) return ''
    const rows = scorers.slice(0, 10).map(s => `<li>${s.rank}. ${s.playerName} (${s.teamName}) — ${s.goals}</li>`).join('')
    return `<h3 style="margin-top:1rem;">Golden Boot</h3><ol style="color: var(--text-secondary);">${rows}</ol>`
  }
}
