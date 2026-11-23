/**
 * Monetization Funnel view: turns the per-day `client.*` telemetry counters
 * (exposed at /api/admin/telemetry) into an actual funnel so you can see where
 * users drop between hitting a Pro gate, seeing the paywall, and purchasing —
 * plus active users (the denominator) and activation/engagement signals.
 *
 * Client events are channel-tagged (appstore / testflight / debug; `unknown` is
 * pre-channel app builds), keyed `telemetry:client.<event>:<channel>:<epochDay>`.
 * The old `telemetry:client.<event>:<epochDay>` counters are still shown under
 * "Legacy". Active users and per-user conversion come from server-side
 * HyperLogLogs of install IDs (unique counts, ~1% error).
 */
import { apiClient } from '../api/client'
import type { TelemetryResponse } from '../api/types'

const EVENTS = [
  'gate_hit',
  'paywall_shown',
  'paywall_dismissed',
  'purchase_completed',
  'trial_started',
  'paywall_plan_selected',
  'paywall_purchase_started',
  'paywall_purchase_cancelled',
  'paywall_purchase_failed',
  'paywall_restore',
  'activation_first_favorite',
  'activation_notifications_enabled',
  'ad_upsell_tapped',
  'rating_prompt_shown',
  'app_active',
] as const

type EventName = (typeof EVENTS)[number]
type Totals = Record<EventName, number>

const CHANNELS = ['appstore', 'testflight', 'debug', 'unknown', 'all', 'legacy'] as const
type ChannelChoice = (typeof CHANNELS)[number]
const CHANNEL_LABELS: Record<ChannelChoice, string> = {
  appstore: 'App Store',
  testflight: 'TestFlight',
  debug: 'Debug builds',
  unknown: 'Unknown (pre-channel builds)',
  all: 'All channels',
  legacy: 'Legacy (pre-channel counters)',
}
/** Real channels summed for "All" (legacy counters are added on top). */
const REAL_CHANNELS = ['appstore', 'testflight', 'debug', 'unknown']

/** Bounded value sets the server breaks paywall events out by (`other` = anything else). */
const PLANS = ['monthly', 'annual', 'lifetime']
const PLATFORM_LABELS: Record<string, string> = { ios: 'iOS', macos: 'Mac', other: 'Unknown' }

type Stage = { label: string; value: number; note: string }

export class MonetizationFunnel {
  private container: HTMLElement | null = null
  private days = 14
  private channel: ChannelChoice = 'appstore'

  render(container: HTMLElement) {
    this.container = container
    const options = CHANNELS.map(
      (c) => `<option value="${c}"${c === this.channel ? ' selected' : ''}>${CHANNEL_LABELS[c]}</option>`
    ).join('')
    container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Monetization Funnel</h2>
          <div style="display:flex; gap:0.5rem; align-items:center;">
            <select id="funnel-channel" style="padding:0.4rem 0.6rem; border-radius:6px;">${options}</select>
            <select id="funnel-range" style="padding:0.4rem 0.6rem; border-radius:6px;">
              <option value="7">Last 7 days</option>
              <option value="14" selected>Last 14 days</option>
              <option value="30">Last 30 days</option>
            </select>
            <button class="btn btn-primary" id="funnel-refresh" style="padding:0.5rem 1rem; font-size:0.875rem;">Refresh</button>
          </div>
        </div>
        <p style="color: var(--text-secondary); margin-bottom: 1rem;">
          Client telemetry over the selected window. Event counters retain ~30 days;
          active-user and unique-install sets retain ~90 days.
        </p>
        <div id="funnel-body">Loading…</div>
      </div>
    `

    const range = container.querySelector('#funnel-range') as HTMLSelectElement
    range.addEventListener('change', () => {
      this.days = parseInt(range.value, 10) || 14
      this.load()
    })
    const channel = container.querySelector('#funnel-channel') as HTMLSelectElement
    channel.addEventListener('change', () => {
      this.channel = channel.value as ChannelChoice
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
      const data = await apiClient.getTelemetry(this.days)
      body.innerHTML = this.renderBody(data)
    } catch (err) {
      body.innerHTML = `<div class="badge danger">Failed to load telemetry: ${
        err instanceof Error ? err.message : String(err)
      }</div>`
    }
  }

  /** Days in the trailing window, as the epochDay strings the API keys by. */
  private windowDays(today: number): string[] {
    const out: string[] = []
    for (let d = today - this.days + 1; d <= today; d++) out.push(String(d))
    return out
  }

  private sumDays(byDay: Record<string, number> | undefined, days: string[]): number {
    if (!byDay) return 0
    return days.reduce((acc, d) => acc + (byDay[d] || 0), 0)
  }

  /** event → day → count maps that make up the selected channel. */
  private sources(data: TelemetryResponse): Record<string, Record<string, number>>[] {
    const legacy = data.counters || {}
    const channels = data.channels || {}
    switch (this.channel) {
      case 'legacy':
        return [legacy]
      case 'all':
        return [legacy, ...REAL_CHANNELS.map((c) => channels[c] || {})]
      default:
        return [channels[this.channel] || {}]
    }
  }

  /** Sum each client.<event> over the trailing window for the selected channel. */
  private sum(data: TelemetryResponse, days: string[]): Totals {
    const sources = this.sources(data)
    const totals = {} as Totals
    for (const event of EVENTS) {
      totals[event] = sources.reduce((acc, src) => acc + this.sumDays(src[`client.${event}`], days), 0)
    }
    return totals
  }

  /** `field=value` → count for one event's breakouts, summed over the window. */
  private breakouts(data: TelemetryResponse, event: string, days: string[]): [string, number][] {
    const channels = this.channel === 'all' ? REAL_CHANNELS : this.channel === 'legacy' ? [] : [this.channel]
    const acc: Record<string, number> = {}
    for (const c of channels) {
      const byDim = data.dimensions?.[c]?.[`client.${event}`] || {}
      for (const [dim, byDay] of Object.entries(byDim)) {
        acc[dim] = (acc[dim] || 0) + this.sumDays(byDay, days)
      }
    }
    return Object.entries(acc)
      .filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1])
  }

  private pct(numerator: number, denominator: number): string {
    if (denominator <= 0) return '—'
    return `${((numerator / denominator) * 100).toFixed(1)}%`
  }

  private renderBody(data: TelemetryResponse): string {
    const days = this.windowDays(data.today)
    const t = this.sum(data, days)
    const conversions = t.purchase_completed + t.trial_started
    // Funnel stages, widest at top. Bars are scaled to the largest stage.
    const stages = [
      { label: 'Pro gate hit', value: t.gate_hit, note: 'user blocked by a Pro feature' },
      { label: 'Paywall shown', value: t.paywall_shown, note: this.pct(t.paywall_shown, t.gate_hit) + ' of gate hits' },
      { label: 'Purchase or trial', value: conversions, note: this.pct(conversions, t.paywall_shown) + ' of paywalls' },
    ]
    const bars = this.renderBars(stages)

    const stat = (label: string, value: number | string, sub = '') => `
      <div class="stat-card">
        <div class="stat-value">${typeof value === 'number' ? value.toLocaleString() : value}</div>
        <div class="stat-label">${label}${sub ? ` <span style="color:var(--text-secondary)">(${sub})</span>` : ''}</div>
      </div>`

    return `
      ${this.renderActiveUsers(data)}

      ${this.renderActivation(data)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Funnel (events)</h3>
      <div style="max-width:680px; margin-bottom:1.5rem;">${bars}</div>

      ${this.renderPerUser(data)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Conversion (events)</h3>
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${stat('Gate → Paywall', t.paywall_shown, this.pct(t.paywall_shown, t.gate_hit))}
        ${stat('Paywall → Buy/Trial', conversions, this.pct(conversions, t.paywall_shown))}
        ${stat('Purchases', t.purchase_completed)}
        ${stat('Trials started', t.trial_started)}
        ${stat('Paywall dismissed', t.paywall_dismissed, this.pct(t.paywall_dismissed, t.paywall_shown))}
        ${stat('Ad “remove ads” taps', t.ad_upsell_tapped)}
      </div>

      ${this.renderPaywall(data, days, t)}

      ${this.renderBreakouts(data, days)}

      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Activation & engagement</h3>
      <div class="stats-grid">
        ${stat('First favorite added', t.activation_first_favorite)}
        ${stat('Notifications enabled', t.activation_notifications_enabled)}
        ${stat('Rating prompts shown', t.rating_prompt_shown)}
        ${stat('app_active pings', t.app_active)}
      </div>
    `
  }

  /** Horizontal funnel bars, scaled to the widest stage. */
  private renderBars(stages: Stage[]): string {
    const maxStage = Math.max(1, ...stages.map((s) => s.value))
    return stages
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
  }

  private renderActiveUsers(data: TelemetryResponse): string {
    if (this.channel === 'legacy') return ''
    const au = data.activeUsers?.[this.channel]
    if (!au) return ''
    const card = (label: string, value: number | string, sub = '') => `
      <div class="stat-card">
        <div class="stat-value">${typeof value === 'number' ? value.toLocaleString() : value}</div>
        <div class="stat-label">${label}${sub ? ` <span style="color:var(--text-secondary)">(${sub})</span>` : ''}</div>
      </div>`
    const platforms = Object.entries(au.byPlatform || {})
      .filter(([, c]) => c.mau > 0)
      .map(([p, c]) => `<tr><td>${p}</td><td>${c.dau}</td><td>${c.wau}</td><td>${c.mau}</td></tr>`)
      .join('')
    const daily = Object.entries(au.daily || {}).sort((a, b) => Number(a[0]) - Number(b[0]))
    const maxDaily = Math.max(1, ...daily.map(([, n]) => n))
    const spark = daily
      .map(([day, n]) => {
        const date = new Date(Number(day) * 86_400_000).toISOString().slice(5, 10)
        const h = Math.max(2, Math.round((n / maxDaily) * 48))
        return `<div title="${date}: ${n}" style="flex:1; display:flex; flex-direction:column; justify-content:flex-end; align-items:center;">
            <div style="width:100%; height:${h}px; background:var(--accent, #3b82f6); border-radius:3px 3px 0 0;"></div>
          </div>`
      })
      .join('')
    return `
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Active users (unique installs, UTC days)</h3>
      <div class="stats-grid" style="margin-bottom:1rem;">
        ${card('DAU', au.total.dau, 'today, partial')}
        ${card('WAU', au.total.wau, '7 days')}
        ${card('MAU', au.total.mau, '30 days')}
        ${card('WAU / MAU', this.pct(au.total.wau, au.total.mau), 'stickiness')}
      </div>
      <div style="display:flex; gap:2px; height:52px; max-width:680px; margin-bottom:0.5rem;">${spark}</div>
      ${
        platforms
          ? `<table style="max-width:420px; margin-bottom:1.5rem;">
              <thead><tr><th>Platform</th><th>DAU</th><th>WAU</th><th>MAU</th></tr></thead>
              <tbody>${platforms}</tbody>
            </table>`
          : '<p style="color:var(--text-secondary); margin-bottom:1.5rem;">No app_active pings yet for this channel.</p>'
      }
    `
  }

  /**
   * Install-once activation funnel plus D1/D7/D14/D30 retention per install
   * week. Both count only installs first seen on a cohort-aware build — legacy
   * (upgraded) installs never send activation events or join a cohort — so the
   * top of the funnel is new installs, not MAU. "All" and real channels only.
   */
  private renderActivation(data: TelemetryResponse): string {
    if (this.channel === 'legacy') return ''
    const u = data.uniqueInstalls?.[this.channel] || {}
    const funnel = data.activationFunnel || []
    const installs = u['cohort.installs'] || 0
    const labels: Record<string, string> = {
      activation_onboarding_started: 'Onboarding started',
      activation_onboarding_completed: 'Onboarding completed',
      activation_first_favorite: 'First favorite',
      activation_notifications_granted: 'Notifications allowed',
      activation_notifications_denied: 'Notifications denied',
      activation_first_reminder_set: 'First reminder set',
      activation_first_live_activity: 'First Live Activity',
      activation_widget_installed: 'Widget installed',
      activation_first_game_detail_opened: 'First game detail opened',
    }
    const steps = [{ label: 'New installs', value: installs }].concat(
      funnel.map((e) => ({ label: labels[e] || e, value: u[`client.${e}`] || 0 }))
    )
    const funnelRows = steps
      .map(
        (s) => `<tr><td>${s.label}</td><td>${s.value.toLocaleString()}</td><td>${
          s.label === 'New installs' ? '' : this.pct(s.value, installs)
        }</td></tr>`
      )
      .join('')

    const sportRows = this.breakouts(data, 'activation_onboarding_completed', this.windowDays(data.today))
      .map(([dim, n]) => `${dim.split('=').slice(1).join('=')}: ${n}`)
      .join(' · ')

    const marks = ['d1', 'd7', 'd14', 'd30']
    const weeks = data.retention?.[this.channel] || []
    const cell = (week: { installs: number; retained: Record<string, number>; complete: Record<string, boolean> }, mark: string) => {
      if (!(mark in week.retained)) return '<td style="color:var(--text-secondary)">—</td>'
      const n = week.retained[mark]
      const pending = week.complete[mark] ? '' : ' <span style="color:var(--text-secondary)" title="still filling in">…</span>'
      return `<td>${this.pct(n, week.installs)} <span style="color:var(--text-secondary)">(${n})</span>${pending}</td>`
    }
    const weekRows = weeks
      .map((w) => {
        const date = new Date(w.weekStart * 86_400_000).toISOString().slice(0, 10)
        return `<tr><td>${date}</td><td>${w.installs.toLocaleString()}</td>${marks.map((m) => cell(w, m)).join('')}</tr>`
      })
      .join('')

    return `
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Activation (new installs, install-once events, ${data.windowDays}d)</h3>
      <table style="max-width:520px; margin-bottom:0.5rem;">
        <thead><tr><th>Step</th><th>Installs</th><th>% of new</th></tr></thead>
        <tbody>${funnelRows}</tbody>
      </table>
      ${sportRows ? `<p style="color:var(--text-secondary); margin-bottom:1rem;">Sports picked at onboarding: ${sportRows}</p>` : ''}

      <h3 style="margin:1rem 0 0.75rem; font-size:0.95rem;">Retention by install week (active exactly N days after install, UTC)</h3>
      ${
        weekRows
          ? `<table style="max-width:680px; margin-bottom:0.5rem;">
              <thead><tr><th>Week of</th><th>Installs</th><th>D1</th><th>D7</th><th>D14</th><th>D30</th></tr></thead>
              <tbody>${weekRows}</tbody>
            </table>
            <p style="color:var(--text-secondary); margin-bottom:1.5rem;">… = some install days in the week haven't reached that mark yet. Upgraded (legacy) installs are excluded.</p>`
          : '<p style="color:var(--text-secondary); margin-bottom:1.5rem;">No retention data (server predates cohorts).</p>'
      }
    `
  }

  private renderPerUser(data: TelemetryResponse): string {
    if (this.channel === 'legacy') return ''
    const u = data.uniqueInstalls?.[this.channel]
    if (!u) return ''
    const get = (e: string) => u[`client.${e}`] || 0
    const paywall = get('paywall_shown')
    const converters = get('purchase_or_trial')
    const mau = data.activeUsers?.[this.channel]?.total.mau || 0
    const stat = (label: string, value: number, sub = '') => `
      <div class="stat-card">
        <div class="stat-value">${value.toLocaleString()}</div>
        <div class="stat-label">${label}${sub ? ` <span style="color:var(--text-secondary)">(${sub})</span>` : ''}</div>
      </div>`
    return `
      <h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Per-user conversion (unique installs, ${data.windowDays}d)</h3>
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${stat('Users hitting a gate', get('gate_hit'))}
        ${stat('Users shown paywall', paywall, this.pct(paywall, mau) + ' of MAU')}
        ${stat('Users who bought/trialed', converters, this.pct(converters, paywall) + ' of paywall users')}
        ${stat('Purchasers', get('purchase_completed'))}
        ${stat('Trialers', get('trial_started'))}
        ${stat('Users adding a favorite', get('activation_first_favorite'), this.pct(get('activation_first_favorite'), mau) + ' of MAU')}
      </div>
    `
  }

  /** value → count for one event's `field` breakout over the window (selected channel). */
  /** Paid purchases plus trials started, by `field` (both carry the paywall's context). */
  private boughtDim(data: TelemetryResponse, field: string, days: string[]): Record<string, number> {
    const out = this.dim(data, 'purchase_completed', field, days)
    for (const [k, v] of Object.entries(this.dim(data, 'trial_started', field, days))) out[k] = (out[k] || 0) + v
    return out
  }

  private dim(data: TelemetryResponse, event: string, field: string, days: string[]): Record<string, number> {
    const out: Record<string, number> = {}
    for (const [key, n] of this.breakouts(data, event, days)) {
      const [f, ...rest] = key.split('=')
      if (f === field) out[rest.join('=')] = n
    }
    return out
  }

  /**
   * In-paywall funnel: shown → purchase started → completed (purchase or trial),
   * plus plan mix, per-trigger conversion, iOS vs Mac, restore and dismiss
   * outcomes. Breakdowns read the `field=value` counters the server keeps for
   * paywall events, so they're per-event (not per-user), channel-tagged only,
   * and all zero until the paywall-funnel app build ships.
   */
  private renderPaywall(data: TelemetryResponse, days: string[], t: Totals): string {
    const heading = '<h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Paywall</h3>'
    if (this.channel === 'legacy') {
      return `${heading}<p style="color:var(--text-secondary); margin-bottom:1.5rem;">Paywall breakdowns are channel-tagged only — pick a channel.</p>`
    }
    const muted = (text: string) => `<span style="color:var(--text-secondary)">${text}</span>`
    const n = (v: number) => v.toLocaleString()
    const subhead = (text: string) => `<h4 style="margin:0.5rem 0 0.5rem; font-size:0.85rem;">${text}</h4>`
    const completed = t.purchase_completed + t.trial_started
    const started = t.paywall_purchase_started
    /** Known keys always shown (zeros included); `other` only when non-zero. */
    const keysWithOther = (known: string[], maps: Record<string, number>[]) =>
      maps.some((m) => (m.other || 0) > 0) ? [...known, 'other'] : known

    // 1. Funnel.
    const bars = this.renderBars([
      { label: 'Paywall shown', value: t.paywall_shown, note: 'every open, incl. direct' },
      { label: 'Purchase started', value: started, note: this.pct(started, t.paywall_shown) + ' of shown' },
      {
        label: 'Completed (purchase or trial)',
        value: completed,
        note: `${this.pct(completed, started)} of started · ${this.pct(completed, t.paywall_shown)} of shown`,
      },
    ])
    const startedUsers = data.uniqueInstalls?.[this.channel]?.['client.paywall_purchase_started'] || 0
    const stat = (label: string, value: number, sub = '') => `
      <div class="stat-card">
        <div class="stat-value">${n(value)}</div>
        <div class="stat-label">${label}${sub ? ` ${muted(`(${sub})`)}` : ''}</div>
      </div>`
    const funnelStats = `
      <div class="stats-grid" style="margin-bottom:1.5rem;">
        ${stat('Purchase cancelled', t.paywall_purchase_cancelled, this.pct(t.paywall_purchase_cancelled, started) + ' of started')}
        ${stat('Purchase failed', t.paywall_purchase_failed, this.pct(t.paywall_purchase_failed, started) + ' of started')}
        ${stat('Users who started a purchase', startedUsers, 'unique installs')}
        ${stat('Plan row taps', t.paywall_plan_selected)}
      </div>`

    // 2. Plan mix.
    const selected = this.dim(data, 'paywall_plan_selected', 'plan', days)
    const startedByPlan = this.dim(data, 'paywall_purchase_started', 'plan', days)
    const cancelledByPlan = this.dim(data, 'paywall_purchase_cancelled', 'plan', days)
    const failedByPlan = this.dim(data, 'paywall_purchase_failed', 'plan', days)
    const boughtByPlan = this.boughtDim(data, 'plan', days)
    const planRows = keysWithOther(PLANS, [selected, startedByPlan, cancelledByPlan, failedByPlan, boughtByPlan])
      .map((p) => {
        const st = startedByPlan[p] || 0
        const done = boughtByPlan[p] || 0
        return `<tr><td>${p}</td><td>${n(selected[p] || 0)}</td><td>${n(st)}</td><td>${n(cancelledByPlan[p] || 0)}</td><td>${n(failedByPlan[p] || 0)}</td><td>${n(done)}</td><td>${this.pct(done, st)}</td></tr>`
      })
      .join('')
    const planTable = `
      <table style="max-width:680px; margin-bottom:0.5rem;">
        <thead><tr><th>Plan</th><th>Selected</th><th>Started</th><th>Cancelled</th><th>Failed</th><th>Purchased</th><th>Started → bought</th></tr></thead>
        <tbody>${planRows}</tbody>
      </table>
      <p style="color:var(--text-secondary); margin-bottom:1.5rem;">“Selected” counts taps that switched plan rows. “Purchased” counts paid purchases and trials started from the paywall.</p>`

    // 3. Trigger conversion + featured.
    const shownByTrigger = this.dim(data, 'paywall_shown', 'trigger', days)
    const startedByTrigger = this.dim(data, 'paywall_purchase_started', 'trigger', days)
    const boughtByTrigger = this.boughtDim(data, 'trigger', days)
    const dismissedByTrigger = this.dim(data, 'paywall_dismissed', 'trigger', days)
    const triggers = [...new Set([shownByTrigger, startedByTrigger, boughtByTrigger, dismissedByTrigger].flatMap(Object.keys))]
      .sort((a, b) => (shownByTrigger[b] || 0) - (shownByTrigger[a] || 0))
    const triggerRows = triggers
      .map((tr) => {
        const shown = shownByTrigger[tr] || 0
        const done = boughtByTrigger[tr] || 0
        return `<tr><td>${tr}</td><td>${n(shown)}</td><td>${n(startedByTrigger[tr] || 0)}</td><td>${n(done)}</td><td>${this.pct(done, shown)}</td><td>${n(dismissedByTrigger[tr] || 0)}</td></tr>`
      })
      .join('')
    const triggerTable = triggerRows
      ? `<table style="max-width:680px; margin-bottom:1rem;">
          <thead><tr><th>Trigger</th><th>Shown</th><th>Started</th><th>Purchased</th><th>Shown → bought</th><th>Dismissed</th></tr></thead>
          <tbody>${triggerRows}</tbody>
        </table>`
      : `<p style="color:var(--text-secondary); margin-bottom:1rem;">No trigger-tagged paywall events yet.</p>`
    const featured = Object.entries(this.dim(data, 'paywall_shown', 'featured', days)).sort((a, b) => b[1] - a[1])
    const featuredTable = featured.length
      ? `<table style="max-width:420px; margin-bottom:1.5rem;">
          <thead><tr><th>Featured (paywall led with)</th><th>Shown</th><th>% of shown</th></tr></thead>
          <tbody>${featured.map(([f, c]) => `<tr><td>${f}</td><td>${n(c)}</td><td>${this.pct(c, t.paywall_shown)}</td></tr>`).join('')}</tbody>
        </table>`
      : ''

    // 4. iOS vs Mac.
    const shownByPlatform = this.dim(data, 'paywall_shown', 'platform', days)
    const startedByPlatform = this.dim(data, 'paywall_purchase_started', 'platform', days)
    const boughtByPlatform = this.boughtDim(data, 'platform', days)
    const platformRows = keysWithOther(['ios', 'macos'], [shownByPlatform, startedByPlatform, boughtByPlatform])
      .map((p) => {
        const shown = shownByPlatform[p] || 0
        const st = startedByPlatform[p] || 0
        const done = boughtByPlatform[p] || 0
        return `<tr><td>${PLATFORM_LABELS[p] || p}</td><td>${n(shown)}</td><td>${n(st)}</td><td>${n(done)}</td><td>${this.pct(st, shown)}</td><td>${this.pct(done, shown)}</td></tr>`
      })
      .join('')
    const platformTable = `
      <table style="max-width:680px; margin-bottom:1.5rem;">
        <thead><tr><th>Platform</th><th>Shown</th><th>Started</th><th>Purchased</th><th>Shown → started</th><th>Shown → bought</th></tr></thead>
        <tbody>${platformRows}</tbody>
      </table>`

    // 5. Restore + dismiss outcomes.
    const outcomeTable = (title: string, labels: Record<string, string>, counts: Record<string, number>, total: number) => {
      const rows = keysWithOther(Object.keys(labels), [counts])
        .map((k) => `<tr><td>${labels[k] || 'Other'}</td><td>${n(counts[k] || 0)}</td><td>${this.pct(counts[k] || 0, total)}</td></tr>`)
        .join('')
      return `<table style="max-width:420px; margin-bottom:1rem;">
          <thead><tr><th>${title}</th><th>Count</th><th>%</th></tr></thead><tbody>${rows}</tbody>
        </table>`
    }
    const restore = this.dim(data, 'paywall_restore', 'result', days)
    const outcome = this.dim(data, 'paywall_dismissed', 'outcome', days)

    return `
      ${heading}
      <div style="max-width:680px; margin-bottom:1rem;">${bars}</div>
      ${funnelStats}

      ${subhead('Plan mix')}
      ${planTable}

      ${subhead('By trigger')}
      ${triggerTable}
      ${featuredTable}

      ${subhead('iOS vs Mac')}
      ${platformTable}

      ${subhead('Outcomes')}
      <div style="display:flex; gap:1.5rem; flex-wrap:wrap; margin-bottom:1.5rem;">
        ${outcomeTable('Restore result', { restored: 'Restored', none: 'Nothing to restore' }, restore, t.paywall_restore)}
        ${outcomeTable('Dismissed', { purchased: 'After purchase', closed: 'Closed' }, outcome, t.paywall_dismissed)}
      </div>
    `
  }

  private renderBreakouts(data: TelemetryResponse, days: string[]): string {
    const table = (title: string, rows: [string, number][]) => {
      if (rows.length === 0) return ''
      const body = rows
        .map(([dim, n]) => `<tr><td>${dim.split('=').slice(1).join('=')}</td><td>${n.toLocaleString()}</td></tr>`)
        .join('')
      return `<table style="max-width:420px; margin-bottom:1rem;">
          <thead><tr><th>${title}</th><th>Count</th></tr></thead><tbody>${body}</tbody>
        </table>`
    }
    const only = (rows: [string, number][], field: string) => rows.filter(([dim]) => dim.startsWith(`${field}=`))
    const html =
      table('Paywall trigger', only(this.breakouts(data, 'paywall_shown', days), 'trigger')) +
      table('Gate hit feature', only(this.breakouts(data, 'gate_hit', days), 'feature'))
    if (!html) return ''
    return `<h3 style="margin:0.5rem 0 0.75rem; font-size:0.95rem;">Breakdowns</h3>${html}`
  }
}
