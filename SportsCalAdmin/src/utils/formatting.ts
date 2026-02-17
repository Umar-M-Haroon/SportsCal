import { formatDistanceToNow, format } from 'date-fns'

export function formatBytes(bytes?: number): string {
  if (!bytes) return 'N/A'

  const units = ['B', 'KB', 'MB', 'GB']
  let size = bytes
  let unitIndex = 0

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024
    unitIndex++
  }

  return `${size.toFixed(2)} ${units[unitIndex]}`
}

export function formatTimeAgo(timestamp?: string): string {
  if (!timestamp) return 'Never'

  try {
    const date = new Date(timestamp)
    return formatDistanceToNow(date, { addSuffix: true })
  } catch {
    return 'Invalid date'
  }
}

export function formatDateTime(timestamp?: string): string {
  if (!timestamp) return 'N/A'

  try {
    const date = new Date(timestamp)
    return format(date, 'MMM d, yyyy HH:mm:ss')
  } catch {
    return 'Invalid date'
  }
}

export function formatTTL(ttl?: number): string {
  if (ttl === undefined || ttl === null) return 'No expiration'
  if (ttl < 0) return 'No expiration'

  const hours = Math.floor(ttl / 3600)
  const minutes = Math.floor((ttl % 3600) / 60)
  const seconds = ttl % 60

  if (hours > 0) {
    return `${hours}h ${minutes}m ${seconds}s`
  } else if (minutes > 0) {
    return `${minutes}m ${seconds}s`
  } else {
    return `${seconds}s`
  }
}

export function formatPercentage(value: number): string {
  return `${(value * 100).toFixed(1)}%`
}

export function getStatusBadge(status?: string): { text: string; class: string } {
  if (!status) return { text: 'Unknown', class: 'badge' }

  const statusLower = status.toLowerCase()

  // Check completed/upcoming BEFORE live — "finished" contains "in" which would false-positive as live
  if (['ft', 'aot', 'final', 'post', 'completed', 'finished', 'match finished'].some(s => statusLower.includes(s))) {
    return { text: 'Final', class: 'badge info' }
  }

  if (['ns', 'pre', 'scheduled', 'not started'].some(s => statusLower.includes(s))) {
    return { text: 'Upcoming', class: 'badge warning' }
  }

  if (['live', 'active', 'in progress', 'in play'].some(s => statusLower.includes(s)) || /^\d/.test(statusLower)) {
    return { text: 'Live', class: 'badge success' }
  }

  return { text: status, class: 'badge' }
}

export function showToast(message: string, type: 'success' | 'error' | 'warning' = 'success') {
  const toast = document.createElement('div')
  toast.className = `toast ${type}`
  toast.textContent = message

  document.body.appendChild(toast)

  setTimeout(() => {
    toast.remove()
  }, 5000)
}

export function formatJSON(json: string): string {
  try {
    const parsed = JSON.parse(json)
    return JSON.stringify(parsed, null, 2)
  } catch {
    return json
  }
}

export function syntaxHighlightJSON(json: string): string {
  try {
    const parsed = JSON.parse(json)
    return renderJSONValue(parsed, 0)
  } catch {
    return json.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  }
}

function renderJSONValue(value: any, depth: number): string {
  const indent = '  '.repeat(depth)
  const nextIndent = '  '.repeat(depth + 1)

  if (value === null) {
    return `<span class="json-null">null</span>`
  }

  if (typeof value === 'boolean') {
    return `<span class="json-boolean">${value}</span>`
  }

  if (typeof value === 'number') {
    return `<span class="json-number">${value}</span>`
  }

  if (typeof value === 'string') {
    const escaped = value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
    return `<span class="json-string">"${escaped}"</span>`
  }

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return '<span class="json-punctuation">[]</span>'
    }

    const id = `collapse-${Math.random().toString(36).substr(2, 9)}`
    const preview = value.length === 1 ? '1 item' : `${value.length} items`

    let html = `<span class="json-punctuation">[</span>`
    html += `<span class="json-collapse-btn" data-target="${id}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${preview}</span>`
    html += `\n<div id="${id}" class="json-collapsible">`

    value.forEach((item, index) => {
      html += nextIndent
      html += renderJSONValue(item, depth + 1)
      if (index < value.length - 1) {
        html += '<span class="json-punctuation">,</span>'
      }
      html += '\n'
    })

    html += `</div>${indent}<span class="json-punctuation">]</span>`
    return html
  }

  if (typeof value === 'object') {
    const keys = Object.keys(value)

    if (keys.length === 0) {
      return '<span class="json-punctuation">{}</span>'
    }

    const id = `collapse-${Math.random().toString(36).substr(2, 9)}`
    const preview = keys.length === 1 ? '1 property' : `${keys.length} properties`

    let html = `<span class="json-punctuation">{</span>`
    html += `<span class="json-collapse-btn" data-target="${id}" style="cursor: pointer; color: var(--text-secondary); font-size: 0.75rem; margin-left: 0.5rem;">▼ ${preview}</span>`
    html += `\n<div id="${id}" class="json-collapsible">`

    keys.forEach((key, index) => {
      const escaped = key.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
      html += nextIndent
      html += `<span class="json-key">"${escaped}"</span><span class="json-punctuation">: </span>`
      html += renderJSONValue(value[key], depth + 1)
      if (index < keys.length - 1) {
        html += '<span class="json-punctuation">,</span>'
      }
      html += '\n'
    })

    html += `</div>${indent}<span class="json-punctuation">}</span>`
    return html
  }

  return String(value)
}
