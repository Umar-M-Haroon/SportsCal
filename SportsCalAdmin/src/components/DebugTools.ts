import { apiClient } from '../api/client'
import { showToast } from '../utils/formatting'

export class DebugTools {
  private container: HTMLElement | null = null
  private intervalId: ReturnType<typeof setInterval> | null = null

  render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Push-to-Start Registrations</h2>
          <button class="btn btn-primary" id="refresh-registrations" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="registrations-content" class="loading">Loading registrations...</div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Pipeline Status</h2>
          <button class="btn btn-primary" id="refresh-pipeline" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
        </div>
        <div id="pipeline-content" class="loading">Loading diagnostics...</div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Trigger Push-to-Start</h2>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Send a push-to-start Live Activity notification to registered devices.
          Select an event ID from the registrations above, or type one manually.
        </p>

        <div style="display: flex; flex-direction: column; gap: 0.75rem; max-width: 500px;">
          <div>
            <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Event ID</label>
            <input type="text" id="debug-event-id" placeholder="debug-fake-XXXXXXXX"
              style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color); font-family: monospace;" />
          </div>
          <div style="display: flex; gap: 0.75rem;">
            <div style="flex: 1;">
              <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Home Team</label>
              <input type="text" id="debug-home-team" value="Debug Lions"
                style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color);" />
            </div>
            <div style="flex: 1;">
              <label style="display: block; font-weight: 600; margin-bottom: 0.25rem; font-size: 0.875rem;">Away Team</label>
              <input type="text" id="debug-away-team" value="Debug Tigers"
                style="width: 100%; padding: 0.5rem; border: 1px solid var(--border-color); border-radius: 0.375rem; background: var(--bg-color); color: var(--text-color);" />
            </div>
          </div>
          <div style="display: flex; gap: 0.75rem; align-self: flex-start;">
            <button class="btn btn-primary" id="trigger-push-to-start">
              Send Push-to-Start
            </button>
            <button class="btn btn-primary" id="trigger-all-push-to-start" style="background: var(--success-color, #22c55e);">
              Start All Debug Games
            </button>
          </div>
        </div>

        <div id="debug-result" style="margin-top: 1rem;"></div>
      </div>

      <div class="card">
        <div class="card-header">
          <h2 class="card-title">How to Test</h2>
        </div>
        <ol style="color: var(--text-secondary); line-height: 1.8; padding-left: 1.25rem;">
          <li>On the iOS app: <strong>Settings → Developer → Live Activity Testing</strong></li>
          <li>Create a fake upcoming game → tap its menu → <strong>Auto-Follow</strong></li>
          <li>Wait for the registration to appear above (refresh if needed)</li>
          <li><strong>Force-quit the iOS app</strong></li>
          <li>Click the event ID above to select it, then tap <strong>Send Push-to-Start</strong></li>
          <li>A Live Activity should appear on the device lock screen</li>
        </ol>
      </div>
    `

    this.container.querySelector('#refresh-registrations')?.addEventListener('click', () => this.fetchRegistrations())
    this.container.querySelector('#refresh-pipeline')?.addEventListener('click', () => this.fetchDiagnostics())
    this.container.querySelector('#trigger-push-to-start')?.addEventListener('click', () => {
      this.triggerPushToStart(this.container!.querySelector('#trigger-push-to-start') as HTMLButtonElement)
    })
    this.container.querySelector('#trigger-all-push-to-start')?.addEventListener('click', () => {
      this.triggerAllPushToStart(this.container!.querySelector('#trigger-all-push-to-start') as HTMLButtonElement)
    })

    this.fetchRegistrations()
    this.fetchDiagnostics()
    this.intervalId = setInterval(() => {
      this.fetchRegistrations()
      this.fetchDiagnostics()
    }, 10000)
  }

  stop() {
    if (this.intervalId) {
      clearInterval(this.intervalId)
      this.intervalId = null
    }
  }

  private async fetchDiagnostics() {
    const contentDiv = this.container?.querySelector('#pipeline-content')
    if (!contentDiv) return

    try {
      const data = await apiClient.getPushToStartDiagnostics()

      let html = `
        <div style="display: flex; gap: 0.75rem; flex-wrap: wrap; margin-bottom: 1rem;">
          ${data.system.map(check => `
            <span class="badge ${check.ok ? 'success' : 'danger'}" style="padding: 0.375rem 0.75rem; font-size: 0.8rem;">
              ${check.ok ? '✅' : '❌'} ${check.name}: ${check.detail}
            </span>
          `).join('')}
        </div>
      `

      if (data.tokens.length === 0) {
        html += `<div style="color: var(--text-secondary); font-size: 0.875rem;">No tokens registered — pipeline steps will appear here once a device registers.</div>`
      } else {
        for (const token of data.tokens) {
          html += `
            <div style="margin-bottom: 1rem; padding: 0.75rem; border: 1px solid var(--border-color); border-radius: 0.375rem;">
              <div style="font-weight: 600; margin-bottom: 0.5rem; font-family: monospace; font-size: 0.8rem;">${token.tokenPrefix}</div>
              <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
                ${token.steps.map(step => {
                  const colors: Record<string, string> = { green: '#22c55e', yellow: '#eab308', red: '#ef4444' }
                  const bg: Record<string, string> = { green: 'rgba(34,197,94,0.1)', yellow: 'rgba(234,179,8,0.1)', red: 'rgba(239,68,68,0.1)' }
                  return `<span style="display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.25rem 0.5rem; border-radius: 0.25rem; font-size: 0.75rem; background: ${bg[step.status] || bg.red}; color: ${colors[step.status] || colors.red}; border: 1px solid ${colors[step.status] || colors.red}30;">
                    <span style="width: 8px; height: 8px; border-radius: 50%; background: ${colors[step.status] || colors.red};"></span>
                    ${step.name}
                    <span style="opacity: 0.7; font-size: 0.7rem;">(${step.detail})</span>
                  </span>`
                }).join('')}
              </div>
            </div>
          `
        }
      }

      contentDiv.innerHTML = html
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      contentDiv.innerHTML = `
        <div style="color: var(--danger-color); font-size: 0.875rem;">
          Failed to load diagnostics: ${errorMsg}
        </div>
      `
    }
  }

  private async fetchRegistrations() {
    const contentDiv = this.container?.querySelector('#registrations-content')
    if (!contentDiv) return

    try {
      const data = await apiClient.getPushToStartRegistrations()

      if (data.totalTokens === 0) {
        contentDiv.innerHTML = `
          <div style="text-align: center; padding: 2rem; color: var(--text-secondary);">
            <div style="font-size: 2rem; margin-bottom: 0.5rem;">📭</div>
            <div>No push-to-start registrations found.</div>
            <div style="font-size: 0.875rem; margin-top: 0.25rem;">Create a fake game and auto-follow it in the iOS app first.</div>
          </div>
        `
        return
      }

      let html = `
        <div style="font-size: 0.875rem; color: var(--text-secondary); margin-bottom: 0.75rem;">
          ${data.totalTokens} registered device(s). Click an event ID to select it for triggering.
        </div>
        <table>
          <thead>
            <tr>
              <th>Token</th>
              <th>Favorites</th>
              <th>Event IDs</th>
            </tr>
          </thead>
          <tbody>
      `

      for (const reg of data.registrations) {
        const eventButtons = reg.eventIDs.map(id =>
          `<button class="select-event-btn badge info" data-event-id="${id}"
            style="cursor: pointer; border: none; margin: 0.125rem;"
            title="Click to select">${id}</button>`
        ).join(' ')

        const favoritesBadges = reg.favorites.map(f =>
          `<span class="badge success" style="margin: 0.125rem;">${f}</span>`
        ).join(' ')

        html += `
          <tr>
            <td><code style="font-size: 0.75rem;">${reg.tokenPrefix}</code></td>
            <td>${favoritesBadges || '<span style="color: var(--text-secondary);">none</span>'}</td>
            <td>${eventButtons || '<span style="color: var(--text-secondary);">none</span>'}</td>
          </tr>
        `
      }

      html += '</tbody></table>'
      contentDiv.innerHTML = html

      // Add click handlers for event ID buttons
      contentDiv.querySelectorAll('.select-event-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          const eventID = (e.target as HTMLElement).dataset.eventId
          if (eventID) {
            const input = this.container?.querySelector('#debug-event-id') as HTMLInputElement
            if (input) {
              input.value = eventID
              input.focus()
              showToast(`Selected: ${eventID}`, 'success')
            }
          }
        })
      })
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      contentDiv.innerHTML = `
        <div style="text-align: center; padding: 2rem; color: var(--danger-color);">
          <div style="font-size: 2rem; margin-bottom: 0.5rem;">⚠️</div>
          <div>Failed to load registrations: ${errorMsg}</div>
        </div>
      `
    }
  }

  private async triggerAllPushToStart(btn: HTMLButtonElement) {
    const originalText = btn.textContent
    btn.disabled = true
    btn.textContent = 'Starting all...'

    const resultDiv = this.container?.querySelector('#debug-result')
    const homeTeam = (this.container?.querySelector('#debug-home-team') as HTMLInputElement)?.value?.trim() || 'Debug Lions'
    const awayTeam = (this.container?.querySelector('#debug-away-team') as HTMLInputElement)?.value?.trim() || 'Debug Tigers'

    try {
      const data = await apiClient.getPushToStartRegistrations()
      const allEventIDs = new Set<string>()
      for (const reg of data.registrations) {
        for (const id of reg.eventIDs) {
          allEventIDs.add(id)
        }
      }

      if (allEventIDs.size === 0) {
        showToast('No event IDs found in registrations', 'error')
        return
      }

      let totalNotified = 0
      const results: string[] = []
      const allTraces: string[] = []
      const allErrors: string[] = []

      for (const eventID of allEventIDs) {
        try {
          const result = await apiClient.triggerDebugPushToStart(eventID, homeTeam, awayTeam)
          totalNotified += result.notified
          results.push(`${eventID}: ${result.notified} device(s)${result.reason ? ` (${result.reason})` : ''}`)
          if (result.trace) allTraces.push(`--- ${eventID} ---\n${result.trace}`)
          if (result.errors?.length) allErrors.push(...result.errors.map(e => `${eventID}: ${e}`))
        } catch (error) {
          const msg = error instanceof Error ? error.message : 'Unknown error'
          results.push(`${eventID}: failed (${msg})`)
        }
      }

      if (resultDiv) {
        resultDiv.innerHTML = `
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${totalNotified > 0 ? 'rgba(34,197,94,0.1)' : 'rgba(234,179,8,0.1)'};">
            <strong>${totalNotified > 0 ? '✅' : '⚠️'} Triggered ${allEventIDs.size} event(s), notified ${totalNotified} device(s)</strong>
            <div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">
              ${results.map(r => `<div>${r}</div>`).join('')}
            </div>
            ${allErrors.length ? `<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${allErrors.join('\n')}</pre></div>` : ''}
            ${allTraces.length ? `<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${allTraces.join('\n\n')}</pre></details>` : ''}
          </div>
        `
      }

      showToast(`Started all: ${totalNotified} device(s) notified across ${allEventIDs.size} event(s)`, totalNotified > 0 ? 'success' : 'error')
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      if (resultDiv) {
        resultDiv.innerHTML = `
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Failed:</strong> ${errorMsg}
          </div>
        `
      }
      showToast('Failed to trigger all push-to-starts', 'error')
    } finally {
      btn.disabled = false
      btn.textContent = originalText
    }
  }

  private async triggerPushToStart(btn: HTMLButtonElement) {
    const eventID = (this.container?.querySelector('#debug-event-id') as HTMLInputElement)?.value?.trim()
    const homeTeam = (this.container?.querySelector('#debug-home-team') as HTMLInputElement)?.value?.trim()
    const awayTeam = (this.container?.querySelector('#debug-away-team') as HTMLInputElement)?.value?.trim()

    if (!eventID) {
      showToast('Event ID is required — select one from the registrations above', 'error')
      return
    }

    const originalText = btn.textContent
    btn.disabled = true
    btn.textContent = 'Sending...'

    const resultDiv = this.container?.querySelector('#debug-result')

    try {
      const result = await apiClient.triggerDebugPushToStart(eventID, homeTeam || 'Debug Lions', awayTeam || 'Debug Tigers')

      if (resultDiv) {
        const reasonLabels: Record<string, string> = {
          no_registrations: 'No push-to-start tokens found in Redis',
          apns_not_configured: 'APNS not configured (missing APNSkeyID/TeamID env vars)',
          no_match: 'Registrations exist but no favorites or event IDs matched'
        }
        const reasonText = result.reason ? reasonLabels[result.reason] || result.reason : ''

        resultDiv.innerHTML = `
          <div style="padding: 1rem; border-radius: 0.375rem; background: ${result.notified > 0 ? 'rgba(34,197,94,0.1)' : 'rgba(234,179,8,0.1)'};">
            <strong>${result.notified > 0 ? '✅' : '⚠️'} Notified ${result.notified} device(s)</strong>
            ${result.tokens?.length ? `<div style="margin-top: 0.5rem; font-family: monospace; font-size: 0.8rem; color: var(--text-secondary);">Tokens: ${result.tokens.join(', ')}</div>` : ''}
            ${reasonText ? `<div style="margin-top: 0.5rem; color: var(--warning-color, #eab308); font-weight: 600;">${reasonText}</div>` : ''}
            ${result.errors?.length ? `<div style="margin-top: 0.5rem; color: var(--danger-color);"><strong>APNS Errors:</strong><pre style="margin: 0.25rem 0; font-size: 0.75rem; white-space: pre-wrap;">${result.errors.join('\n')}</pre></div>` : ''}
            ${result.trace ? `<details style="margin-top: 0.75rem;"><summary style="cursor: pointer; font-size: 0.8rem; color: var(--text-secondary);">Server Trace</summary><pre style="margin-top: 0.5rem; padding: 0.75rem; background: var(--bg-color); border: 1px solid var(--border-color); border-radius: 0.25rem; font-size: 0.7rem; white-space: pre-wrap; overflow-x: auto; color: var(--text-secondary);">${result.trace}</pre></details>` : ''}
          </div>
        `
      }

      showToast(`Push-to-start sent to ${result.notified} device(s)`, result.notified > 0 ? 'success' : 'error')
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Unknown error'
      if (resultDiv) {
        resultDiv.innerHTML = `
          <div style="padding: 1rem; border-radius: 0.375rem; background: rgba(239,68,68,0.1); color: var(--danger-color);">
            <strong>❌ Request Failed:</strong> ${errorMsg}
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">Make sure the Vapor server is running.</div>
          </div>
        `
      }
      showToast('Failed to trigger push-to-start', 'error')
    } finally {
      btn.disabled = false
      btn.textContent = originalText
    }
  }
}
