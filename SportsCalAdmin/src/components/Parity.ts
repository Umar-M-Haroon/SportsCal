import { showToast } from '../utils/formatting'

/**
 * Parity view: compares this server's responses against a target environment
 * (dev or prod) for a curated set of endpoints. All comparison work is done
 * server-side by /api/admin/parity; this component just renders the result.
 */

interface ParityResult {
  endpoint: string
  localStatus: number
  targetStatus: number
  match: boolean
  diff: string | null
  localBytes: number
  targetBytes: number
}

interface ParityResponse {
  target: string
  localBase: string
  targetBase: string
  results: ParityResult[]
  matches: number
  mismatches: number
  errors: number
}

export class Parity {
  private container: HTMLElement | null = null
  private target: 'prod' | 'dev' = 'prod'
  private loading = false
  private lastResponse: ParityResponse | null = null
  private lastRunAt: Date | null = null

  render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Parity Check</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <select id="parity-target" style="padding: 0.45rem 0.75rem; border-radius: 0.375rem; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color);">
              <option value="prod">Target: Prod</option>
              <option value="dev">Target: Dev (Tailscale)</option>
            </select>
            <button class="btn btn-primary" id="parity-run" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Run Comparison</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Compares this server's responses to the selected target for a fixed set of endpoints.
          Timestamp / volatile fields are stripped before diffing so live-scoreboard noise doesn't count.
        </p>
        <div id="parity-content"></div>
      </div>
    `

    const selectEl = this.container.querySelector('#parity-target') as HTMLSelectElement | null
    if (selectEl) {
      selectEl.addEventListener('change', () => {
        this.target = selectEl.value as 'prod' | 'dev'
      })
    }
    this.container.querySelector('#parity-run')?.addEventListener('click', () => this.runCheck())
    this.renderBody()
  }

  stop() {
    // nothing to tear down
  }

  private async runCheck() {
    if (this.loading) return
    this.loading = true
    this.renderBody()
    try {
      const resp = await fetch(`/api/admin/parity?target=${encodeURIComponent(this.target)}`, {
        headers: { 'Accept': 'application/json' }
      })
      if (!resp.ok) {
        throw new Error(`HTTP ${resp.status} ${resp.statusText}`)
      }
      this.lastResponse = await resp.json() as ParityResponse
      this.lastRunAt = new Date()
      showToast(`Parity: ${this.lastResponse.matches} match, ${this.lastResponse.mismatches} mismatch, ${this.lastResponse.errors} error`, this.lastResponse.mismatches + this.lastResponse.errors === 0 ? 'success' : 'error')
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err)
      showToast(`Parity check failed: ${msg}`, 'error')
      this.lastResponse = null
    } finally {
      this.loading = false
      this.renderBody()
    }
  }

  private renderBody() {
    const body = this.container?.querySelector('#parity-content')
    if (!body) return
    if (this.loading) {
      body.innerHTML = `<div class="loading">Comparing…</div>`
      return
    }
    if (!this.lastResponse) {
      body.innerHTML = `<div style="color: var(--text-secondary); font-size: 0.875rem;">Click "Run Comparison" to fetch.</div>`
      return
    }

    const r = this.lastResponse
    const summary = `
      <div style="display: flex; gap: 1.5rem; margin-bottom: 1rem; font-size: 0.875rem; color: var(--text-secondary);">
        <div><strong style="color: var(--text-color);">Local:</strong> <code>${escapeHtml(r.localBase)}</code></div>
        <div><strong style="color: var(--text-color);">Target:</strong> <code>${escapeHtml(r.targetBase)}</code></div>
        ${this.lastRunAt ? `<div>ran at ${this.lastRunAt.toLocaleTimeString()}</div>` : ''}
      </div>
      <div style="display: flex; gap: 0.75rem; margin-bottom: 1rem;">
        <span class="badge" style="background: rgba(34,197,94,0.15); color: #16a34a; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${r.matches} match</span>
        <span class="badge" style="background: rgba(234,179,8,0.15); color: #ca8a04; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${r.mismatches} mismatch</span>
        <span class="badge" style="background: rgba(239,68,68,0.15); color: #dc2626; padding: 0.25rem 0.6rem; border-radius: 999px; font-weight: 600; font-size: 0.85rem;">${r.errors} error</span>
      </div>
    `

    const rows = r.results.map(result => {
      const icon = result.match ? '✓' : (result.localStatus === 200 && result.targetStatus === 200 ? '≠' : '⚠')
      const color = result.match ? '#16a34a' : (result.localStatus === 200 && result.targetStatus === 200 ? '#ca8a04' : '#dc2626')
      const diff = result.diff ? `<div style="color: var(--text-secondary); font-size: 0.8rem; margin-top: 0.25rem;">${escapeHtml(result.diff)}</div>` : ''
      return `
        <div style="border-bottom: 1px solid var(--border-color); padding: 0.6rem 0;">
          <div style="display: flex; justify-content: space-between; align-items: center; gap: 1rem;">
            <div style="display: flex; gap: 0.5rem; align-items: center; min-width: 0;">
              <span style="color: ${color}; font-weight: 700; font-size: 1.05rem;">${icon}</span>
              <code style="font-size: 0.85rem; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(result.endpoint)}</code>
            </div>
            <div style="color: var(--text-secondary); font-size: 0.8rem; white-space: nowrap;">
              ${result.localStatus}/${result.targetStatus} · ${formatBytes(result.localBytes)}/${formatBytes(result.targetBytes)}
            </div>
          </div>
          ${diff}
        </div>
      `
    }).join('')

    body.innerHTML = summary + rows
  }
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[c]!))
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`
}
