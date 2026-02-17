import { apiClient } from '../api/client'
import type { RedisKeyInfo } from '../api/types'
import { formatBytes, formatTTL, syntaxHighlightJSON, showToast } from '../utils/formatting'
import { logger } from '../utils/logger'

export class RedisViewer {
  private container: HTMLElement | null = null
  private keys: RedisKeyInfo[] = []
  private filteredKeys: RedisKeyInfo[] = []

  async render(container: HTMLElement) {
    this.container = container
    logger.log('Redis Viewer initialized', 'info')
    this.container.innerHTML = '<div class="loading">Loading Redis keys...</div>'

    await this.loadKeys()
  }

  private async loadKeys() {
    logger.log('Fetching Redis keys from /api/admin/redis/keys...', 'info')
    const startTime = Date.now()

    try {
      const response = await apiClient.getRedisKeys()
      const elapsed = Date.now() - startTime
      logger.log(`Loaded ${response.keys.length} Redis keys in ${elapsed}ms`, 'success')

      this.keys = response.keys
      this.filteredKeys = this.keys
      this.displayKeys()
    } catch (error) {
      const elapsed = Date.now() - startTime
      logger.log(`Failed to fetch Redis keys after ${elapsed}ms: ${error}`, 'error')
      console.error('Failed to fetch Redis keys:', error)
      showToast('Failed to fetch Redis keys', 'error')

      if (this.container) {
        this.container.innerHTML = `
          <div class="card">
            <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
              <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
              <div style="font-weight: 600; font-size: 1.125rem;">Failed to load Redis keys</div>
              <button class="btn btn-primary" id="retry-redis" style="margin-top: 1rem;">🔄 Retry</button>
            </div>
          </div>
        `
        this.container.querySelector('#retry-redis')?.addEventListener('click', () => this.loadKeys())
      }
    }
  }

  stop() {
    // Nothing to clean up - event listeners are removed when container is cleared
  }

  private displayKeys() {
    if (!this.container) return

    this.container.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h2 class="card-title">Redis Keys</h2>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-primary" id="refresh-redis" style="padding: 0.5rem 1rem; font-size: 0.875rem;">🔄 Refresh</button>
            <span class="badge info">${this.keys.length} Keys</span>
          </div>
        </div>

        <div style="margin-bottom: 1rem;">
          <input
            type="text"
            id="key-search"
            class="input"
            placeholder="Search keys..."
          />
        </div>

        <div style="max-height: 600px; overflow-y: auto;">
          <table id="keys-table">
            <thead>
              <tr>
                <th>Key</th>
                <th>Type</th>
                <th>Size</th>
                <th>TTL</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody id="keys-table-body">
              ${this.filteredKeys.map((key, index) => this.renderKeyRow(key, index)).join('')}
            </tbody>
          </table>
        </div>
      </div>

      <div id="key-detail" style="display: none;"></div>
    `

    // Add refresh button listener
    const refreshBtn = this.container.querySelector('#refresh-redis')
    refreshBtn?.addEventListener('click', () => {
      logger.log('Manual refresh triggered', 'info')
      showToast('Refreshing Redis keys...', 'success')
      this.loadKeys()
    })

    // Add search listener
    const searchInput = this.container.querySelector('#key-search') as HTMLInputElement
    searchInput.addEventListener('input', (e) => {
      const query = (e.target as HTMLInputElement).value.toLowerCase()
      this.filteredKeys = this.keys.filter(k => k.key.toLowerCase().includes(query))
      this.updateKeysTable()
    })

    // Add event delegation for table actions
    this.setupActionListeners()
  }

  private renderKeyRow(key: RedisKeyInfo, index: number): string {
    return `
      <tr>
        <td style="font-family: monospace; font-size: 0.875rem;">${this.escapeHtml(key.key)}</td>
        <td><span class="badge info">${key.type}</span></td>
        <td>${formatBytes(key.size)}</td>
        <td>${formatTTL(key.ttl)}</td>
        <td style="white-space: nowrap;">
          <button class="btn btn-secondary btn-view" data-index="${index}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; min-width: 70px;">View</button>
          <button class="btn btn-danger btn-delete" data-index="${index}" style="padding: 0.25rem 0.5rem; font-size: 0.75rem; margin-left: 0.25rem;">Delete</button>
        </td>
      </tr>
    `
  }

  private escapeHtml(text: string): string {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  private updateKeysTable() {
    const tbody = this.container?.querySelector('#keys-table-body')
    if (tbody) {
      tbody.innerHTML = this.filteredKeys.map((key, index) => this.renderKeyRow(key, index)).join('')
      // Event delegation is already set up in displayKeys(), no need to re-attach
    }
  }

  private setupActionListeners() {
    // Use event delegation on the table to handle all button clicks
    const table = this.container?.querySelector('#keys-table')

    if (!table) {
      logger.log('Keys table not found, cannot setup listeners', 'error')
      return
    }

    // Add single event listener to table
    const handleClick = (e: Event) => {
      const target = e.target as HTMLElement

      if (target.classList.contains('btn-view')) {
        e.preventDefault()
        e.stopPropagation()

        const index = parseInt(target.dataset.index || '-1')
        logger.log(`View button clicked, index: ${index}, filteredKeys length: ${this.filteredKeys.length}`, 'info')

        if (index >= 0 && index < this.filteredKeys.length) {
          const key = this.filteredKeys[index].key
          logger.log(`Viewing key: ${key}`, 'info')

          // Show loading state
          const button = target as HTMLButtonElement
          button.disabled = true
          button.textContent = 'Loading...'

          this.viewKey(key).finally(() => {
            // Reset button state
            button.disabled = false
            button.textContent = 'View'
          })
        } else {
          logger.log(`Invalid index: ${index}`, 'error')
        }
      } else if (target.classList.contains('btn-delete')) {
        e.preventDefault()
        e.stopPropagation()

        const index = parseInt(target.dataset.index || '-1')
        if (index >= 0 && index < this.filteredKeys.length) {
          const key = this.filteredKeys[index].key
          this.deleteKey(key)
        }
      }
    }

    table.addEventListener('click', handleClick)
    logger.log(`Event delegation set up for ${this.filteredKeys.length} keys`, 'info')
  }

  private async viewKey(key: string) {
    logger.log(`Viewing Redis key: ${key}`, 'info')

    const detailDiv = this.container?.querySelector('#key-detail') as HTMLElement | null

    if (!detailDiv) {
      logger.log('Detail div not found', 'error')
      return
    }

    // Show loading state
    detailDiv.innerHTML = `
      <div class="card">
        <div class="card-header">
          <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(key)}</h3>
        </div>
        <div style="text-align: center; padding: 3rem;">
          <div class="loading">Loading key value...</div>
        </div>
      </div>
    `
    detailDiv.style.display = 'block'

    try {
      const startTime = Date.now()
      const content = await apiClient.getRedisKey(key)
      const elapsed = Date.now() - startTime
      logger.log(`Key content loaded (${content.value.length} bytes) in ${elapsed}ms`, 'success')

      const highlightedJSON = syntaxHighlightJSON(content.value)

      detailDiv.innerHTML = `
        <div class="card">
          <div class="card-header">
            <h3 class="card-title" style="font-family: monospace; font-size: 1rem; word-break: break-all;">${this.escapeHtml(key)}</h3>
            <div style="display: flex; gap: 0.5rem;">
              <span class="badge info">${content.type}</span>
              ${content.ttl ? `<span class="badge warning">TTL: ${formatTTL(content.ttl)}</span>` : ''}
              <span class="badge info">${formatBytes(content.value.length)}</span>
            </div>
          </div>
          <div class="json-viewer"><pre style="margin: 0;">${highlightedJSON}</pre></div>
          <div style="margin-top: 1rem; display: flex; gap: 0.5rem;">
            <button class="btn btn-secondary" id="copy-json">📋 Copy</button>
            <button class="btn btn-danger" id="close-detail">Close</button>
          </div>
        </div>
      `

      detailDiv.querySelector('#copy-json')?.addEventListener('click', () => {
        navigator.clipboard.writeText(content.value)
        showToast('Copied to clipboard', 'success')
      })

      detailDiv.querySelector('#close-detail')?.addEventListener('click', () => {
        if (detailDiv) {
          detailDiv.style.display = 'none'
        }
      })

      // Add collapse/expand functionality for JSON
      this.setupJSONCollapseHandlers(detailDiv)

      // Scroll to the detail view
      detailDiv.scrollIntoView({ behavior: 'smooth', block: 'nearest' })

    } catch (error) {
      logger.log(`Failed to fetch key content: ${error}`, 'error')
      console.error('Failed to fetch key content:', error)
      showToast('Failed to fetch key content', 'error')

      // Show error state
      detailDiv.innerHTML = `
        <div class="card">
          <div style="text-align: center; padding: 3rem; color: var(--danger-color);">
            <div style="font-size: 3rem; margin-bottom: 1rem;">⚠️</div>
            <div style="font-weight: 600; font-size: 1.125rem;">Failed to load key</div>
            <div style="margin-top: 0.5rem; font-size: 0.875rem; color: var(--text-secondary);">${error}</div>
            <button class="btn btn-danger" id="close-error" style="margin-top: 1rem;">Close</button>
          </div>
        </div>
      `

      detailDiv.querySelector('#close-error')?.addEventListener('click', () => {
        if (detailDiv) {
          detailDiv.style.display = 'none'
        }
      })
    }
  }

  private async deleteKey(key: string) {
    if (!confirm(`Are you sure you want to delete key "${key}"?`)) {
      return
    }

    try {
      const result = await apiClient.invalidateKey(key)
      showToast(result.message, result.success ? 'success' : 'warning')

      if (result.success) {
        // Remove key from list
        this.keys = this.keys.filter(k => k.key !== key)
        this.filteredKeys = this.filteredKeys.filter(k => k.key !== key)
        this.updateKeysTable()
      }
    } catch (error) {
      console.error('Failed to delete key:', error)
      showToast('Failed to delete key', 'error')
    }
  }

  private setupJSONCollapseHandlers(container: HTMLElement) {
    const collapseButtons = container.querySelectorAll('.json-collapse-btn')

    collapseButtons.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault()
        const target = e.target as HTMLElement
        const targetId = target.dataset.target

        if (targetId) {
          const collapsible = container.querySelector(`#${targetId}`)

          if (collapsible) {
            const isCollapsed = collapsible.classList.toggle('collapsed')
            target.classList.toggle('collapsed')

            // Update arrow direction
            const currentText = target.textContent || ''
            if (isCollapsed) {
              target.textContent = currentText.replace('▼', '▶')
            } else {
              target.textContent = currentText.replace('▶', '▼')
            }
          }
        }
      })
    })

    logger.log(`Set up ${collapseButtons.length} JSON collapse handlers`, 'info')
  }
}
