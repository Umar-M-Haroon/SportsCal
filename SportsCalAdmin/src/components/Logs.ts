interface LogEntry {
  timestamp: string
  level: string
  label: string
  message: string
  metadata: Record<string, string>
}

interface LogFilterState {
  level: string
  labels: string[]
  search: string
}

export class Logs {
  private container: HTMLElement | null = null
  private ws: WebSocket | null = null
  private entries: LogEntry[] = []
  private maxEntries = 2000
  private paused = false
  private autoScroll = true
  private seenLabels: Set<string> = new Set()
  private filter: LogFilterState = { level: 'debug', labels: [], search: '' }
  private searchDebounce: ReturnType<typeof setTimeout> | null = null

  render(container: HTMLElement) {
    this.container = container
    this.entries = []
    this.seenLabels = new Set()

    container.innerHTML = `
      <div class="logs-container">
        <div class="logs-toolbar">
          <div class="logs-toolbar-row">
            <div class="logs-level-filters">
              <button class="log-level-btn log-level-debug active" data-level="debug">DEBUG</button>
              <button class="log-level-btn log-level-info active" data-level="info">INFO</button>
              <button class="log-level-btn log-level-warning active" data-level="warning">WARN</button>
              <button class="log-level-btn log-level-error active" data-level="error">ERROR</button>
            </div>
            <input type="text" class="input logs-search" placeholder="Search logs..." id="logs-search" />
            <select class="select logs-label-select" id="logs-label-select" style="width: auto; min-width: 150px;">
              <option value="">All subsystems</option>
            </select>
            <div class="logs-actions">
              <button class="btn btn-secondary" id="logs-pause">Pause</button>
              <button class="btn btn-secondary" id="logs-clear">Clear</button>
              <span class="logs-count" id="logs-count">0 entries</span>
            </div>
          </div>
        </div>
        <div class="logs-list" id="logs-list"></div>
      </div>
    `

    this.setupEventListeners()
    this.connect()
  }

  stop() {
    this.disconnect()
  }

  private setupEventListeners() {
    if (!this.container) return

    // Level filter buttons
    this.container.querySelectorAll('.log-level-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        btn.classList.toggle('active')
        this.updateMinLevel()
        this.renderEntries()
      })
    })

    // Search input
    const searchInput = this.container.querySelector('#logs-search') as HTMLInputElement
    searchInput?.addEventListener('input', () => {
      if (this.searchDebounce) clearTimeout(this.searchDebounce)
      this.searchDebounce = setTimeout(() => {
        this.filter.search = searchInput.value
        this.sendFilter()
        this.renderEntries()
      }, 300)
    })

    // Label select
    const labelSelect = this.container.querySelector('#logs-label-select') as HTMLSelectElement
    labelSelect?.addEventListener('change', () => {
      this.filter.labels = labelSelect.value ? [labelSelect.value] : []
      this.sendFilter()
      this.renderEntries()
    })

    // Pause/Resume
    const pauseBtn = this.container.querySelector('#logs-pause')
    pauseBtn?.addEventListener('click', () => {
      this.paused = !this.paused
      pauseBtn.textContent = this.paused ? 'Resume' : 'Pause'
    })

    // Clear
    const clearBtn = this.container.querySelector('#logs-clear')
    clearBtn?.addEventListener('click', () => {
      this.entries = []
      this.renderEntries()
    })

    // Auto-scroll detection
    const list = this.container.querySelector('#logs-list')
    list?.addEventListener('scroll', () => {
      if (!list) return
      const el = list as HTMLElement
      this.autoScroll = el.scrollHeight - el.scrollTop - el.clientHeight < 50
    })
  }

  private updateMinLevel() {
    const levelOrder = ['debug', 'info', 'warning', 'error']
    const activeButtons = this.container?.querySelectorAll('.log-level-btn.active')
    const activeLevels = new Set<string>()
    activeButtons?.forEach(btn => {
      const level = (btn as HTMLElement).dataset.level
      if (level) activeLevels.add(level)
    })

    // Find the minimum active level
    for (const level of levelOrder) {
      if (activeLevels.has(level)) {
        this.filter.level = level
        this.sendFilter()
        return
      }
    }
    this.filter.level = 'error'
    this.sendFilter()
  }

  private connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const url = `${protocol}//${window.location.host}/ws/logs`

    try {
      this.ws = new WebSocket(url)

      this.ws.onmessage = (event) => {
        if (this.paused) return
        try {
          const data = JSON.parse(event.data)
          if (data.type === 'initial' && Array.isArray(data.entries)) {
            this.entries = data.entries
            data.entries.forEach((e: LogEntry) => this.seenLabels.add(e.label))
            this.updateLabelSelect()
            this.renderEntries()
          } else if (data.type === 'entry' && data.entry) {
            this.addEntry(data.entry)
          }
        } catch {
          // ignore parse errors
        }
      }

      this.ws.onclose = () => {
        // Reconnect after delay if still mounted
        setTimeout(() => {
          if (this.container) this.connect()
        }, 3000)
      }
    } catch {
      // ignore connection errors, will retry
    }
  }

  private disconnect() {
    if (this.ws) {
      this.ws.onclose = null
      this.ws.close()
      this.ws = null
    }
  }

  private addEntry(entry: LogEntry) {
    this.entries.push(entry)
    if (this.entries.length > this.maxEntries) {
      this.entries = this.entries.slice(-this.maxEntries)
    }

    const isNewLabel = !this.seenLabels.has(entry.label)
    this.seenLabels.add(entry.label)
    if (isNewLabel) this.updateLabelSelect()

    // Append directly to DOM for performance
    if (this.matchesClientFilter(entry)) {
      const list = this.container?.querySelector('#logs-list')
      if (list) {
        list.appendChild(this.createEntryElement(entry))
        if (this.autoScroll) {
          list.scrollTop = list.scrollHeight
        }
      }
    }

    this.updateCount()
  }

  private matchesClientFilter(entry: LogEntry): boolean {
    const levelOrder = ['trace', 'debug', 'info', 'notice', 'warning', 'error', 'critical']
    const entryIdx = levelOrder.indexOf(entry.level)
    const filterIdx = levelOrder.indexOf(this.filter.level)
    if (entryIdx < filterIdx) return false

    // Check active level buttons
    const activeButtons = this.container?.querySelectorAll('.log-level-btn.active')
    const activeLevels = new Set<string>()
    activeButtons?.forEach(btn => {
      const level = (btn as HTMLElement).dataset.level
      if (level) activeLevels.add(level)
    })
    // Map entry levels to button levels
    const buttonLevel = entry.level === 'notice' ? 'info' : entry.level
    if (!activeLevels.has(buttonLevel)) return false

    if (this.filter.labels.length > 0 && !this.filter.labels.includes(entry.label)) return false
    if (this.filter.search && !entry.message.toLowerCase().includes(this.filter.search.toLowerCase()) &&
        !entry.label.toLowerCase().includes(this.filter.search.toLowerCase())) return false
    return true
  }

  private renderEntries() {
    const list = this.container?.querySelector('#logs-list')
    if (!list) return

    const filtered = this.entries.filter(e => this.matchesClientFilter(e))
    const fragment = document.createDocumentFragment()
    for (const entry of filtered) {
      fragment.appendChild(this.createEntryElement(entry))
    }
    list.innerHTML = ''
    list.appendChild(fragment)

    if (this.autoScroll) {
      list.scrollTop = list.scrollHeight
    }

    this.updateCount()
  }

  private createEntryElement(entry: LogEntry): HTMLElement {
    const el = document.createElement('div')
    el.className = `log-entry log-level-${entry.level}`

    const time = new Date(entry.timestamp).toLocaleTimeString('en-US', {
      hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3
    } as Intl.DateTimeFormatOptions)

    const levelBadge = entry.level.toUpperCase().padEnd(5)

    const metadataStr = Object.keys(entry.metadata).length > 0
      ? `<span class="log-metadata">${Object.entries(entry.metadata).map(([k, v]) => `${k}=${v}`).join(' ')}</span>`
      : ''

    el.innerHTML = `<span class="log-time">${time}</span><span class="log-level-badge log-badge-${entry.level}">${levelBadge}</span><span class="log-label">${entry.label}</span><span class="log-separator">\u2502</span><span class="log-message">${this.escapeHtml(entry.message)}</span>${metadataStr}`

    // Click to expand metadata
    if (Object.keys(entry.metadata).length > 0) {
      el.style.cursor = 'pointer'
      el.addEventListener('click', () => {
        const existing = el.querySelector('.log-metadata-expanded')
        if (existing) {
          existing.remove()
        } else {
          const detail = document.createElement('div')
          detail.className = 'log-metadata-expanded'
          detail.textContent = JSON.stringify(entry.metadata, null, 2)
          el.appendChild(detail)
        }
      })
    }

    return el
  }

  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  private updateLabelSelect() {
    const select = this.container?.querySelector('#logs-label-select') as HTMLSelectElement
    if (!select) return

    const current = select.value
    const sorted = Array.from(this.seenLabels).sort()
    select.innerHTML = '<option value="">All subsystems</option>' +
      sorted.map(l => `<option value="${l}"${l === current ? ' selected' : ''}>${l}</option>`).join('')
  }

  private updateCount() {
    const countEl = this.container?.querySelector('#logs-count')
    if (!countEl) return
    const visible = this.container?.querySelector('#logs-list')?.children.length ?? 0
    countEl.textContent = `${visible} / ${this.entries.length} entries`
  }

  private sendFilter() {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'filter',
        level: this.filter.level,
        labels: this.filter.labels.length > 0 ? this.filter.labels : undefined,
        search: this.filter.search || undefined
      }))
    }
  }
}
