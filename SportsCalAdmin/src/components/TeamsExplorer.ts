import { apiClient } from '../api/client'
import type { Team } from '../api/types'
import { showToast } from '../utils/formatting'

export class TeamsExplorer {
  private container: HTMLElement | null = null
  private teams: Team[] = []
  private filteredTeams: Team[] = []

  async render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = '<div class="loading">Loading teams...</div>'

    try {
      this.teams = await apiClient.getTeams()
      this.filteredTeams = this.teams
      this.displayTeams()
    } catch (error) {
      console.error('Failed to fetch teams:', error)
      showToast('Failed to fetch teams', 'error')
    }
  }

  stop() {
    // Nothing to clean up
  }

  private displayTeams() {
    if (!this.container) return

    const teamsWithoutBadges = this.teams.filter(t => !t.strTeamBadge).length

    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Teams</h2>
          <div style="display: flex; gap: 0.5rem;">
            <span class="badge info">${this.teams.length} Total</span>
            ${teamsWithoutBadges > 0 ? `<span class="badge warning">${teamsWithoutBadges} Missing Badges</span>` : ''}
          </div>
        </div>

        <div style="margin-bottom: 1rem;">
          <input
            type="text"
            id="team-search"
            class="input"
            placeholder="Search teams..."
          />
        </div>

        <div id="teams-grid" class="grid grid-3">
          ${this.filteredTeams.map(team => this.renderTeamCard(team)).join('')}
        </div>
      </div>
    `

    // Add search listener
    const searchInput = this.container.querySelector('#team-search') as HTMLInputElement
    searchInput.addEventListener('input', (e) => {
      const query = (e.target as HTMLInputElement).value.toLowerCase()
      this.filteredTeams = this.teams.filter(t =>
        t.strTeam?.toLowerCase().includes(query) ||
        t.strTeamShort?.toLowerCase().includes(query) ||
        t.strAlternate?.toLowerCase().includes(query)
      )
      this.updateTeamsGrid()
    })
  }

  private renderTeamCard(team: Team): string {
    return `
      <div class="card" style="text-align: center; padding: 1rem;">
        ${team.strTeamBadge
          ? `<img src="${team.strTeamBadge}" alt="${team.strTeam}" style="width: 64px; height: 64px; margin: 0 auto 0.5rem; object-fit: contain;">`
          : `<div style="width: 64px; height: 64px; margin: 0 auto 0.5rem; background-color: var(--border-color); border-radius: 0.375rem; display: flex; align-items: center; justify-content: center; color: var(--text-secondary);">No Logo</div>`
        }
        <div style="font-weight: 600; margin-bottom: 0.25rem;">${team.strTeam || 'Unknown'}</div>
        ${team.strTeamShort ? `<div style="font-size: 0.875rem; color: var(--text-secondary);">${team.strTeamShort}</div>` : ''}
        ${team.idTeam ? `<div style="font-size: 0.75rem; color: var(--text-secondary); margin-top: 0.25rem;">ID: ${team.idTeam}</div>` : ''}
      </div>
    `
  }

  private updateTeamsGrid() {
    const grid = this.container?.querySelector('#teams-grid')
    if (grid) {
      grid.innerHTML = this.filteredTeams.map(team => this.renderTeamCard(team)).join('')
    }
  }
}
