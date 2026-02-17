import { apiClient } from '../api/client'
import type { DataGapsResponse } from '../api/types'
import { formatPercentage, showToast } from '../utils/formatting'

export class DataGaps {
  private container: HTMLElement | null = null

  async render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = '<div class="loading">Analyzing data gaps...</div>'

    try {
      const gaps = await apiClient.getDataGaps()
      this.displayGaps(gaps)
    } catch (error) {
      console.error('Failed to fetch data gaps:', error)
      showToast('Failed to analyze data gaps', 'error')
    }
  }

  stop() {
    // Nothing to clean up
  }

  private displayGaps(gaps: DataGapsResponse) {
    if (!this.container) return

    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Data Completeness Analysis</h2>
          <span class="badge ${gaps.summary.overallCompleteness > 0.95 ? 'success' : gaps.summary.overallCompleteness > 0.8 ? 'warning' : 'danger'}">
            ${formatPercentage(gaps.summary.overallCompleteness)} Complete
          </span>
        </div>

        <div class="grid grid-3">
          <div class="stat-card">
            <div class="stat-value">${gaps.summary.totalLeagues}</div>
            <div class="stat-label">Total Leagues</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${gaps.summary.totalGames}</div>
            <div class="stat-label">Total Games</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${gaps.summary.leaguesWithIssues}</div>
            <div class="stat-label">Leagues with Issues</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">League Details</h2>
        </div>
        <table>
          <thead>
            <tr>
              <th>League</th>
              <th>Sport</th>
              <th>Total Games</th>
              <th>Missing Badges</th>
              <th>Missing Scores</th>
              <th>Missing Timestamps</th>
              <th>Completeness</th>
            </tr>
          </thead>
          <tbody>
            ${gaps.leagues
              .sort((a, b) => a.completeness - b.completeness)
              .map(league => this.renderLeagueRow(league))
              .join('')}
          </tbody>
        </table>
      </div>

      ${this.renderRecommendations(gaps)}
    `
  }

  private renderLeagueRow(league: any): string {
    const completeness = league.completeness
    const badgeClass = completeness > 0.95 ? 'success' : completeness > 0.8 ? 'warning' : 'danger'

    return `
      <tr>
        <td style="font-weight: 500;">${league.league}</td>
        <td>${league.sport}</td>
        <td>${league.totalGames}</td>
        <td ${league.gamesWithoutBadges > 0 ? 'style="color: var(--danger-color); font-weight: 600;"' : ''}>${league.gamesWithoutBadges}</td>
        <td ${league.gamesWithoutScores > 0 ? 'style="color: var(--warning-color); font-weight: 600;"' : ''}>${league.gamesWithoutScores}</td>
        <td ${league.gamesWithoutTimestamps > 0 ? 'style="color: var(--danger-color); font-weight: 600;"' : ''}>${league.gamesWithoutTimestamps}</td>
        <td><span class="badge ${badgeClass}">${formatPercentage(completeness)}</span></td>
      </tr>
    `
  }

  private renderRecommendations(gaps: DataGapsResponse): string {
    const issues = gaps.leagues.filter(l => l.completeness < 1.0)

    if (issues.length === 0) {
      return `
        <div class="card">
          <div style="text-align: center; padding: 2rem; color: var(--success-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">✓</div>
            <div style="font-weight: 600; font-size: 1.125rem;">All data looks good!</div>
            <div style="color: var(--text-secondary); margin-top: 0.5rem;">No data gaps detected.</div>
          </div>
        </div>
      `
    }

    return `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Recommendations</h2>
        </div>
        <ul style="list-style: none; padding: 0;">
          ${issues.map(league => {
            const recommendations = []
            if (league.gamesWithoutBadges > 0) {
              recommendations.push(`Missing ${league.gamesWithoutBadges} team badges`)
            }
            if (league.gamesWithoutScores > 0) {
              recommendations.push(`Missing ${league.gamesWithoutScores} scores`)
            }
            if (league.gamesWithoutTimestamps > 0) {
              recommendations.push(`Missing ${league.gamesWithoutTimestamps} timestamps`)
            }

            return `
              <li style="padding: 0.75rem 0; border-bottom: 1px solid var(--border-color);">
                <div style="font-weight: 600; margin-bottom: 0.25rem;">${league.league}</div>
                <div style="font-size: 0.875rem; color: var(--text-secondary);">
                  ${recommendations.join(' • ')}
                </div>
              </li>
            `
          }).join('')}
        </ul>
      </div>
    `
  }
}
