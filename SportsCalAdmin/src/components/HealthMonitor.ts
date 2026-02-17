import { apiClient } from '../api/client'
import type { HealthResponse } from '../api/types'
import { formatTimeAgo, showToast } from '../utils/formatting'
import { logger } from '../utils/logger'

export class HealthMonitor {
  private container: HTMLElement | null = null
  private intervalId: ReturnType<typeof setInterval> | null = null
  private lastFetchTime: Date | null = null

  render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">System Health</h2>
          <button class="btn btn-primary" id="refresh-health" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="health-content" class="loading">Loading health status...</div>
      </div>
    `

    // Add refresh button listener
    const refreshBtn = this.container.querySelector('#refresh-health')
    refreshBtn?.addEventListener('click', () => this.manualRefresh())

    // Fetch immediately with timeout
    logger.log('Health Monitor initialized', 'info')
    this.fetchHealthWithTimeout()
    this.intervalId = setInterval(() => this.fetchHealthWithTimeout(), 10000)
  }

  private manualRefresh() {
    logger.log('Manual refresh triggered', 'info')
    showToast('Refreshing health status...', 'success')
    this.fetchHealthWithTimeout()
  }

  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId)
      this.intervalId = null
    }
  }

  private async fetchHealthWithTimeout() {
    const startTime = Date.now()
    logger.log('Fetching health status from /api/admin/health...', 'info')

    try {
      // Add 5 second timeout
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Request timeout after 5s')), 5000)
      )
      const healthPromise = apiClient.getHealth()
      const health = await Promise.race([healthPromise, timeoutPromise]) as any

      const elapsed = Date.now() - startTime
      logger.log(`Health status received in ${elapsed}ms`, 'success')
      this.lastFetchTime = new Date()
      this.displayHealth(health)
    } catch (error) {
      const elapsed = Date.now() - startTime
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      logger.log(`Health fetch failed after ${elapsed}ms: ${errorMsg}`, 'error')
      console.error('Failed to fetch health:', error)

      const contentDiv = this.container?.querySelector('#health-content')
      if (contentDiv) {
        contentDiv.innerHTML = `
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to connect to API</div>
            <div style="color: var(--text-secondary); margin-top: 0.5rem; margin-bottom: 1rem;">
              Make sure the Vapor server is running on port 8081<br/>
              Error: ${errorMsg}
            </div>
            <button class="btn btn-primary" id="retry-health">🔄 Retry</button>
          </div>
        `

        contentDiv.querySelector('#retry-health')?.addEventListener('click', () => this.manualRefresh())
      }
      showToast('Failed to fetch health status', 'error')
    }
  }

  private displayHealth(health: HealthResponse) {
    const contentDiv = this.container?.querySelector('#health-content')
    if (!contentDiv) return

    const isHealthy = health.status === 'healthy'
    const lastFetch = this.lastFetchTime ? formatTimeAgo(this.lastFetchTime.toISOString()) : 'just now'

    contentDiv.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">System Health</h2>
          <span class="badge ${isHealthy ? 'success' : 'danger'}">
            ${health.status.toUpperCase()}
          </span>
        </div>
        <div class="grid grid-3">
          <div class="stat-card">
            <div class="stat-value">${health.redis.keyCount ?? 'N/A'}</div>
            <div class="stat-label">Redis Keys</div>
          </div>
          <div class="stat-card">
            <div class="stat-value">${health.redis.memory ?? 'N/A'}</div>
            <div class="stat-label">Memory Used</div>
          </div>
          <div class="stat-card">
            <div class="stat-value ${health.redis.connected ? 'success' : 'danger'}">${health.redis.connected ? 'Connected' : 'Disconnected'}</div>
            <div class="stat-label">Redis Status</div>
          </div>
        </div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Background Jobs</h2>
        </div>
        <table>
          <thead>
            <tr>
              <th>Job Name</th>
              <th>Schedule</th>
              <th>Last Run</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            ${health.jobs.map(job => {
              const triggerable = ['ESPNTeamFetchJob', 'ScheduleUpdateJob', 'ESPNFetchJob'].includes(job.name)
              return `
              <tr>
                <td>${job.name}</td>
                <td>${job.schedule}</td>
                <td>${formatTimeAgo(job.lastRun)}</td>
                <td><span class="badge ${job.status === 'active' ? 'success' : 'warning'}">${job.status}</span></td>
                <td>${triggerable
                  ? `<button class="btn btn-primary trigger-job-btn" data-job="${job.name}" style="padding: 0.25rem 0.75rem; font-size: 0.8rem;">Run Now</button>`
                  : ''}</td>
              </tr>`
            }).join('')}
          </tbody>
        </table>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Actions</h2>
        </div>
        <div style="display: flex; gap: 1rem; flex-wrap: wrap;">
          <button class="btn btn-primary" id="force-refresh">Force Refresh All Schedules</button>
          <button class="btn btn-primary" id="refresh-schedules">Clear Schedule Cache</button>
          <button class="btn btn-danger" id="clear-cache">Clear All Cache</button>
        </div>
      </div>

      <div style="display: flex; justify-content: space-between; align-items: center; padding: 1rem; background: var(--bg-color); border-radius: 0.375rem; font-size: 0.875rem; color: var(--text-secondary);">
        <span>Last updated: ${lastFetch}</span>
        <span>Server time: ${formatTimeAgo(health.timestamp)}</span>
      </div>
    `

    // Add event listeners
    const forceRefreshBtn = contentDiv.querySelector('#force-refresh')
    forceRefreshBtn?.addEventListener('click', () => this.forceRefresh(forceRefreshBtn as HTMLButtonElement))

    const refreshBtn = contentDiv.querySelector('#refresh-schedules')
    refreshBtn?.addEventListener('click', () => this.refreshSchedules())

    const clearBtn = contentDiv.querySelector('#clear-cache')
    clearBtn?.addEventListener('click', () => this.clearCache())

    // Add trigger job button listeners
    contentDiv.querySelectorAll('.trigger-job-btn').forEach(btn => {
      btn.addEventListener('click', (e) => {
        const jobName = (e.target as HTMLButtonElement).dataset.job
        if (jobName) this.triggerJob(jobName, e.target as HTMLButtonElement)
      })
    })
  }

  private async forceRefresh(btn: HTMLButtonElement) {
    const originalText = btn.textContent
    btn.disabled = true
    btn.textContent = 'Refreshing...'

    try {
      const result = await apiClient.forceRefresh()
      const sportCounts = Object.entries(result.gamesLoaded)
        .filter(([, count]) => count > 0)
        .map(([sport, count]) => `${sport}: ${count}`)
        .join(', ')
      showToast(`${result.message}${sportCounts ? ` (${sportCounts})` : ''}`, 'success')
      this.fetchHealthWithTimeout()
    } catch (error) {
      showToast('Failed to force refresh schedules', 'error')
    } finally {
      btn.disabled = false
      btn.textContent = originalText
    }
  }

  private async refreshSchedules() {
    try {
      const result = await apiClient.refreshSchedules()
      showToast(result.message, 'success')
      this.fetchHealthWithTimeout()
    } catch (error) {
      showToast('Failed to refresh schedules', 'error')
    }
  }

  private async triggerJob(jobName: string, btn: HTMLButtonElement) {
    const originalText = btn.textContent
    btn.disabled = true
    btn.textContent = 'Running...'

    try {
      const result = await apiClient.triggerJob(jobName)
      showToast(result.message, result.success ? 'success' : 'error')
      this.fetchHealthWithTimeout()
    } catch (error) {
      showToast(`Failed to trigger ${jobName}`, 'error')
    } finally {
      btn.disabled = false
      btn.textContent = originalText
    }
  }

  private async clearCache() {
    if (!confirm('Are you sure you want to clear ALL cache? This will delete all Redis keys.')) {
      return
    }

    try {
      const result = await apiClient.clearAllCache()
      showToast(result.message, 'success')
      this.fetchHealthWithTimeout()
    } catch (error) {
      showToast('Failed to clear cache', 'error')
    }
  }
}
