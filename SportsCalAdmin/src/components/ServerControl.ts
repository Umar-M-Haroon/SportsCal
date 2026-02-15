export class ServerControl {
  private container: HTMLElement | null = null
  private eventSource: EventSource | null = null
  private consoleEl: HTMLElement | null = null
  private autoScroll = true

  render(container: HTMLElement) {
    this.container = container
    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Vapor Server</h2>
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            <span id="server-badge" class="status-badge" style="padding: 0.25rem 0.75rem; border-radius: 999px; font-size: 0.75rem; font-weight: 700; text-transform: uppercase;">STOPPED</span>
            <span id="server-pid" style="font-size: 0.75rem; color: var(--text-secondary);"></span>
          </div>
        </div>

        <div style="display: flex; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap;">
          <button class="btn btn-primary" id="srv-start" style="padding: 0.5rem 1rem; font-size: 0.875rem;">Start</button>
          <button class="btn btn-primary" id="srv-stop" style="padding: 0.5rem 1rem; font-size: 0.875rem;" disabled>Stop</button>
          <button class="btn btn-primary" id="srv-restart" style="padding: 0.5rem 1rem; font-size: 0.875rem;" disabled>Restart</button>
          <button class="btn" id="srv-force-kill" style="padding: 0.5rem 1rem; font-size: 0.875rem; background: #dc2626; color: white; display: none;">Force Kill Port 8080</button>
          <div style="margin-left: auto; display: flex; align-items: center; gap: 0.5rem;">
            <label style="font-size: 0.75rem; color: var(--text-secondary); display: flex; align-items: center; gap: 0.25rem;">
              <input type="checkbox" id="srv-autoscroll" checked /> Auto-scroll
            </label>
            <button class="btn" id="srv-clear" style="padding: 0.25rem 0.75rem; font-size: 0.75rem;">Clear</button>
          </div>
        </div>

        <div id="server-console" style="
          background: #0d1117;
          color: #c9d1d9;
          font-family: 'SF Mono', Menlo, Monaco, monospace;
          font-size: 0.75rem;
          line-height: 1.5;
          padding: 0.75rem;
          border-radius: 0.5rem;
          height: 500px;
          overflow-y: auto;
          white-space: pre-wrap;
          word-break: break-all;
        "></div>
      </div>
    `

    this.consoleEl = document.getElementById('server-console')

    document.getElementById('srv-start')!.addEventListener('click', () => this.post('start'))
    document.getElementById('srv-stop')!.addEventListener('click', () => this.post('stop'))
    document.getElementById('srv-restart')!.addEventListener('click', () => this.post('restart'))
    document.getElementById('srv-force-kill')!.addEventListener('click', () => this.post('force-kill'))
    document.getElementById('srv-clear')!.addEventListener('click', () => {
      if (this.consoleEl) this.consoleEl.innerHTML = ''
    })
    document.getElementById('srv-autoscroll')!.addEventListener('change', (e) => {
      this.autoScroll = (e.target as HTMLInputElement).checked
    })

    this.loadHistory()
    this.connectSSE()
    this.checkExternalProcess()
  }

  stop() {
    this.eventSource?.close()
    this.eventSource = null
    this.container = null
    this.consoleEl = null
  }

  private async post(action: string) {
    try {
      await fetch(`/__server/${action}`, { method: 'POST' })
    } catch (e) {
      console.error(`Server ${action} failed:`, e)
    }
    if (action === 'force-kill') {
      setTimeout(() => this.checkExternalProcess(), 500)
    }
  }

  private async loadHistory() {
    try {
      const res = await fetch('/__server/logs/history')
      const data = await res.json()
      for (const raw of data.lines) {
        try {
          const entry = JSON.parse(raw)
          this.appendLine(entry.line, entry.stream)
        } catch {
          this.appendLine(raw, 'stdout')
        }
      }
    } catch { /* no history yet */ }
  }

  private connectSSE() {
    this.eventSource = new EventSource('/__server/logs')

    this.eventSource.addEventListener('log', (e: MessageEvent) => {
      const data = JSON.parse(e.data)
      this.appendLine(data.line, data.stream)
    })

    this.eventSource.addEventListener('state', (e: MessageEvent) => {
      const data = JSON.parse(e.data)
      this.updateState(data.state, data.pid, data.errorMessage)
    })

    this.eventSource.onerror = () => {
      // reconnect is automatic with EventSource
    }
  }

  private appendLine(text: string, stream: 'stdout' | 'stderr') {
    if (!this.consoleEl) return
    const span = document.createElement('span')
    span.textContent = text + '\n'
    if (stream === 'stderr') {
      span.style.color = '#f85149'
    }
    this.consoleEl.appendChild(span)

    // trim DOM if too many children
    while (this.consoleEl.childNodes.length > 5000) {
      this.consoleEl.removeChild(this.consoleEl.firstChild!)
    }

    if (this.autoScroll) {
      this.consoleEl.scrollTop = this.consoleEl.scrollHeight
    }
  }

  private updateState(serverState: string, pid: number | null, error: string) {
    const badge = document.getElementById('server-badge')
    const pidEl = document.getElementById('server-pid')
    const startBtn = document.getElementById('srv-start') as HTMLButtonElement | null
    const stopBtn = document.getElementById('srv-stop') as HTMLButtonElement | null
    const restartBtn = document.getElementById('srv-restart') as HTMLButtonElement | null

    if (!badge) return

    const colors: Record<string, string> = {
      stopped: '#6b7280',
      building: '#f59e0b',
      running: '#22c55e',
      error: '#ef4444',
    }

    badge.textContent = serverState.toUpperCase()
    badge.style.background = colors[serverState] ?? '#6b7280'
    badge.style.color = '#fff'

    if (pidEl) pidEl.textContent = pid ? `PID ${pid}` : ''

    if (startBtn) startBtn.disabled = serverState === 'running' || serverState === 'building'
    if (stopBtn) stopBtn.disabled = serverState === 'stopped'
    if (restartBtn) restartBtn.disabled = serverState === 'stopped'

    if (error) {
      this.appendLine(`ERROR: ${error}`, 'stderr')
    }
  }

  private async checkExternalProcess() {
    try {
      const res = await fetch('/__server/status')
      const data = await res.json()
      const forceKillBtn = document.getElementById('srv-force-kill')
      if (!forceKillBtn) return
      // Show force kill when server is stopped but something might be on 8080
      if (data.state === 'stopped') {
        forceKillBtn.style.display = 'inline-block'
      } else {
        forceKillBtn.style.display = 'none'
      }
    } catch { /* ignore */ }
  }
}
