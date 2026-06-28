/**
 * Monetization Funnel view: turns the per-day `client.*` telemetry counters
 * (written by RedisTelemetry, exposed at /api/admin/telemetry) into an actual
 * funnel so you can see where users drop between hitting a Pro gate, seeing the
 * paywall, and purchasing — plus activation and engagement signals.
 *
 * Counter keys are `telemetry:client.<event>:<epochDay>`; the admin endpoint
 * returns them as { "client.<event>": { "<epochDay>": count } }. We sum each
 * event over the selected trailing window.
 */
import { apiClient } from '../api/client'

const EVENTS = [
  'gate_hit',
  'paywall_shown',
  'paywall_dismissed',
  'purchase_completed',
  'trial_started',
  'activation_first_favorite',
  'activation_notifications_enabled',
  'ad_upsell_tapped',
  'rating_prompt_shown',
] as const

type EventName = (typeof EVENTS)[number]
type Totals = Record<EventName, number>

export class MonetizationFunnel {
  private container: HTMLElement | null = null
  private days = 14

  render(container: HTMLElement) {
    this.container = container
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Monetization Funnel</h2>
          <div style="display:flex; gap:0.5rem; align-items:center;">
            <select id="funnel-range" style="padding:0.4rem 0.6rem; border-radius:6px;">
              <option value="7">Last 7 days</option>
              <option value="14" selected>Last 14 days</option>
              <option value="30">Last 30 days</option>
            </select>
            <button class="btn btn-primary" id="funnel-refresh" style="padding:0.5rem 1rem; font-size:0.875rem;">Refresh</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Client telemetry over the selected window. Counters retain ~30 days.
        </p>
        <div id="funnel-body">Loading…</div>
      </div>
    `

    const range = container.querySelector('#funnel-range') as HTMLSelectElement
    range.addEventListener('change', () => {
      this.days = parseInt(range.value, 10) || 14
      this.load()
    })
    container.querySelector('#funnel-refresh')?.addEventListener('click', () => this.load())
    this.load()
  }

  private async load() {
    const body = this.container?.querySelector('#funnel-body')
    if (!body) return
    body.innerHTML = 'Loading…'
    try {
      const { counters } = await apiClient.getTelemetry()
      body.innerHTML = this.renderBody(this.sum(counters))
    } catch (err) {
      body.innerHTML = `<div class="badge danger">Failed to load telemetry: ${
        err instanceof Error ? err.message : String(err)
      }</div>`
    }
  }

  /** Sum each client.<event> over the trailing `this.days` window. */
  private sum(counters: Record<string, Record<string, number>>): Totals {
    const today = Math.floor(Date.now() / 86_400_000)
    const totals = {} as Totals
    for (const event of EVENTS) {
      const byDay = counters[`client.${event}`] || {}
      let total = 0
      for (let d = today - this.days + 1; d <= today; d++) {
        total += byDay[String(d)] || 0
      }
      totals[event] = total
    }
    return totals
  }

  private pct(numerator: number, denominator: number): string {
    if (denominator <= 0) return '—'
    return `${((numerator / denominator) * 100).toFixed(1)}%`
  }

  private renderBody(t: Totals): string {
    const conversions = t.purchase_completed + t.trial_started
    // Funnel stages, widest at top. Bars are scaled to the largest stage.
    const stages = [
      { label: 'Pro gate hit', value: t.gate_hit, note: 'user blocked by a Pro feature' },
      { label: 'Paywall shown', value: t.paywall_shown, note: this.pct(t.paywall_shown, t.gate_hit) + ' of gate hits' },
      { label: 'Purchase or trial', value: conversions, note: this.pct(conversions, t.paywall_shown) + ' of paywalls' },
    ]
    const maxStage = Math.max(1, ...stages.map((s) => s.value))

    const bars = stages
      .map((s) => {
        const w = Math.max(2, Math.round((s.value / maxStage) * 100))
        return `
          <div style="margin-bottom:0.85rem;">
            <div style="display:flex; justify-content:space-between; font-size:0.85rem; margin-bottom:0.25rem;">
              <span><strong>${s.label}</strong></span>
              <span style="color:var(--text-secondary);">${s.value.toLocaleString()} · ${s.note}</span>
            </div>
            <div style="background:var(--bg-secondary, #1e1e1e); border-radius:6px; overflow:hidden;">
              <div style="width:${w}%; background:var(--accent, #3b82f6); height:22px; border-radius:6px;"></div>
            </div>
          </div>`
      })
      .join('')

    const stat = (label: string, value: number, sub = '') => `
      <div class="stat-card">
        <div class="stat-value">${value.toLocaleString()}</div>
        <div class="stat-label">${label}${sub ? ` <span style="color:var(--text-secondary)">(${sub})</span>` : ''}</div>
      </div>`

    return `
      <div style="max-width:680px; margin-bottom:1.5rem;">${bars}</div>

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Conversion</h3>
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${stat('Gate → Paywall', t.paywall_shown, this.pct(t.paywall_shown, t.gate_hit))}
        ${stat('Paywall → Buy/Trial', t.purchase_completed + t.trial_started, this.pct(t.purchase_completed + t.trial_started, t.paywall_shown))}
        ${stat('Purchases', t.purchase_completed)}
        ${stat('Trials started', t.trial_started)}
        ${stat('Paywall dismissed', t.paywall_dismissed, this.pct(t.paywall_dismissed, t.paywall_shown))}
        ${stat('Ad “remove ads” taps', t.ad_upsell_tapped)}
      </div>

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Activation & engagement</h3>
      <div class="stats-grid">
        ${stat('First favorite added', t.activation_first_favorite)}
        ${stat('Notifications enabled', t.activation_notifications_enabled)}
        ${stat('Rating prompts shown', t.rating_prompt_shown)}
      </div>
    `
  }
}
