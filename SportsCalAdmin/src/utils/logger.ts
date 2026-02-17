// Connection status logger
export class ConnectionLogger {
  private logContainer: HTMLElement | null = null
  private logs: string[] = []
  private maxLogs = 50

  constructor() {
    this.createLogContainer()
  }

  private createLogContainer() {
    // Create floating log console
    const container = document.createElement('div')
    container.id = 'connection-log'
    container.style.cssText = `
      position: fixed;
      bottom: 1rem;
      right: 1rem;
      width: 400px;
      max-height: 300px;
      background: var(--surface-color);
      border: 1px solid var(--border-color);
      border-radius: 0.5rem;
      box-shadow: var(--shadow-lg);
      z-index: 1000;
      display: none;
      flex-direction: column;
    `

    container.innerHTML = `
      <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.75rem; border-bottom: 1px solid var(--border-color);">
        <span style="font-weight: 600; font-size: 0.875rem;">Connection Log</span>
        <div>
          <button id="clear-log" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; margin-right: 0.5rem; border: 1px solid var(--border-color); background: var(--surface-color); border-radius: 0.25rem; cursor: pointer;">Clear</button>
          <button id="close-log" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; border: 1px solid var(--border-color); background: var(--surface-color); border-radius: 0.25rem; cursor: pointer;">Close</button>
        </div>
      </div>
      <div id="log-content" style="padding: 0.75rem; overflow-y: auto; flex: 1; font-family: monospace; font-size: 0.75rem;"></div>
    `

    document.body.appendChild(container)
    this.logContainer = container

    // Add button listeners
    document.getElementById('clear-log')?.addEventListener('click', () => this.clear())
    document.getElementById('close-log')?.addEventListener('click', () => this.hide())

    // Add toggle button in header
    this.addToggleButton()
  }

  private addToggleButton() {
    const header = document.querySelector('.header')
    if (header) {
      const btn = document.createElement('button')
      btn.textContent = '📋 Log'
      btn.style.cssText = `
        padding: 0.5rem 1rem;
        border: 1px solid var(--border-color);
        background: var(--surface-color);
        border-radius: 0.375rem;
        cursor: pointer;
        font-size: 0.875rem;
      `
      btn.addEventListener('click', () => this.toggle())
      header.appendChild(btn)
    }
  }

  log(message: string, type: 'info' | 'success' | 'error' | 'warning' = 'info') {
    const timestamp = new Date().toLocaleTimeString()
    const color = {
      info: 'var(--text-secondary)',
      success: 'var(--success-color)',
      error: 'var(--danger-color)',
      warning: 'var(--warning-color)'
    }[type]

    const logEntry = `[${timestamp}] ${message}`
    this.logs.push(logEntry)

    if (this.logs.length > this.maxLogs) {
      this.logs.shift()
    }

    const content = document.getElementById('log-content')
    if (content) {
      const entry = document.createElement('div')
      entry.style.color = color
      entry.textContent = logEntry
      content.appendChild(entry)
      content.scrollTop = content.scrollHeight
    }

    console.log(`[ConnectionLog] ${logEntry}`)
  }

  clear() {
    this.logs = []
    const content = document.getElementById('log-content')
    if (content) {
      content.innerHTML = ''
    }
  }

  show() {
    if (this.logContainer) {
      this.logContainer.style.display = 'flex'
    }
  }

  hide() {
    if (this.logContainer) {
      this.logContainer.style.display = 'none'
    }
  }

  toggle() {
    if (this.logContainer) {
      const isVisible = this.logContainer.style.display === 'flex'
      if (isVisible) {
        this.hide()
      } else {
        this.show()
      }
    }
  }
}

export const logger = new ConnectionLogger()
