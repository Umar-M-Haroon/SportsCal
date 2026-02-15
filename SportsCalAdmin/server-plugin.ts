import type { Plugin } from 'vite'
import { spawn, execSync, type ChildProcess } from 'child_process'
import { resolve } from 'path'
import type { ServerResponse } from 'http'

type ServerState = 'stopped' | 'building' | 'running' | 'error'

const MAX_LOG_LINES = 5000
const ANSI_REGEX = /\x1b\[[0-9;]*[a-zA-Z]/g

export function serverControlPlugin(): Plugin {
  let state: ServerState = 'stopped'
  let childProcess: ChildProcess | null = null
  let errorMessage = ''
  let logBuffer: string[] = []
  let starting = false
  const sseClients: Set<ServerResponse> = new Set()
  const serverDir = resolve(__dirname, '../SportsCalAPI/SportsCalServer')

  function pushLog(line: string, stream: 'stdout' | 'stderr') {
    const clean = line.replace(ANSI_REGEX, '')
    logBuffer.push(JSON.stringify({ line: clean, stream }))
    if (logBuffer.length > MAX_LOG_LINES) {
      logBuffer = logBuffer.slice(logBuffer.length - MAX_LOG_LINES)
    }
    for (const res of sseClients) {
      try {
        res.write(`event: log\ndata: ${JSON.stringify({ line: clean, stream })}\n\n`)
      } catch { /* client disconnected */ }
    }
  }

  function broadcastState() {
    const data = JSON.stringify({ state, pid: childProcess?.pid ?? null, errorMessage })
    for (const res of sseClients) {
      try {
        res.write(`event: state\ndata: ${data}\n\n`)
      } catch { /* client disconnected */ }
    }
  }

  function setState(s: ServerState, err = '') {
    state = s
    errorMessage = err
    broadcastState()
  }

  function findProcessOnPort(): number | null {
    try {
      const output = execSync('lsof -ti:8080', { encoding: 'utf-8' }).trim()
      if (output) {
        const pids = output.split('\n').map(p => parseInt(p, 10)).filter(p => !isNaN(p))
        return pids.length > 0 ? pids[0] : null
      }
    } catch { /* no process on port */ }
    return null
  }

  function stopServer(): Promise<void> {
    return new Promise((resolve) => {
      if (!childProcess) {
        setState('stopped')
        resolve()
        return
      }

      const cp = childProcess
      childProcess = null

      const killTimer = setTimeout(() => {
        try { cp.kill('SIGKILL') } catch { /* already dead */ }
      }, 3000)

      cp.once('exit', () => {
        clearTimeout(killTimer)
        setState('stopped')
        resolve()
      })

      try { cp.kill('SIGTERM') } catch { /* already dead */ }
    })
  }

  function startServer(): Promise<void> {
    if (starting) return Promise.resolve()
    starting = true

    return new Promise((resolvePromise) => {
      setState('building')
      pushLog('--- Building Vapor server ---', 'stdout')

      const build = spawn('swift', ['build'], { cwd: serverDir, env: { ...process.env } })

      build.stdout?.on('data', (data: Buffer) => {
        data.toString().split('\n').filter(Boolean).forEach(l => pushLog(l, 'stdout'))
      })
      build.stderr?.on('data', (data: Buffer) => {
        data.toString().split('\n').filter(Boolean).forEach(l => pushLog(l, 'stderr'))
      })

      build.once('exit', (code) => {
        if (code !== 0) {
          setState('error', `swift build exited with code ${code}`)
          pushLog(`--- Build failed (exit code ${code}) ---`, 'stderr')
          starting = false
          resolvePromise()
          return
        }

        pushLog('--- Build succeeded, starting server ---', 'stdout')
        setState('running')

        const run = spawn('swift', ['run', 'Run', 'serve', '--hostname', '0.0.0.0', '--port', '8080'], {
          cwd: serverDir,
          env: { ...process.env },
        })

        childProcess = run

        run.stdout?.on('data', (data: Buffer) => {
          data.toString().split('\n').filter(Boolean).forEach(l => pushLog(l, 'stdout'))
        })
        run.stderr?.on('data', (data: Buffer) => {
          data.toString().split('\n').filter(Boolean).forEach(l => pushLog(l, 'stderr'))
        })

        run.once('exit', (code) => {
          if (childProcess === run) {
            childProcess = null
            if (state === 'running') {
              setState('error', `Server exited unexpectedly (code ${code})`)
              pushLog(`--- Server exited (code ${code}) ---`, 'stderr')
            }
          }
          starting = false
        })

        starting = false
        resolvePromise()
      })
    })
  }

  function sendJson(res: ServerResponse, data: unknown, status = 200) {
    res.writeHead(status, { 'Content-Type': 'application/json' })
    res.end(JSON.stringify(data))
  }

  function cleanup() {
    if (childProcess) {
      try { childProcess.kill('SIGKILL') } catch { /* ignore */ }
      childProcess = null
    }
    for (const res of sseClients) {
      try { res.end() } catch { /* ignore */ }
    }
    sseClients.clear()
  }

  process.on('SIGINT', () => { cleanup(); process.exit(0) })
  process.on('SIGTERM', () => { cleanup(); process.exit(0) })
  process.on('exit', cleanup)

  return {
    name: 'server-control',
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        const url = req.url ?? ''

        if (url === '/__server/status' && req.method === 'GET') {
          sendJson(res, { state, pid: childProcess?.pid ?? null, errorMessage })
          return
        }

        if (url === '/__server/start' && req.method === 'POST') {
          if (state === 'running' || state === 'building') {
            sendJson(res, { ok: false, message: `Server is already ${state}` })
            return
          }
          startServer()
          sendJson(res, { ok: true, message: 'Starting server' })
          return
        }

        if (url === '/__server/stop' && req.method === 'POST') {
          if (state === 'stopped') {
            sendJson(res, { ok: false, message: 'Server is already stopped' })
            return
          }
          stopServer()
          sendJson(res, { ok: true, message: 'Stopping server' })
          return
        }

        if (url === '/__server/restart' && req.method === 'POST') {
          stopServer().then(() => startServer())
          sendJson(res, { ok: true, message: 'Restarting server' })
          return
        }

        if (url === '/__server/force-kill' && req.method === 'POST') {
          const pid = findProcessOnPort()
          if (pid) {
            try {
              process.kill(pid, 'SIGKILL')
              pushLog(`Force-killed process ${pid} on port 8080`, 'stdout')
              sendJson(res, { ok: true, message: `Killed process ${pid}` })
            } catch (e: any) {
              sendJson(res, { ok: false, message: `Failed to kill: ${e.message}` })
            }
          } else {
            sendJson(res, { ok: false, message: 'No process found on port 8080' })
          }
          return
        }

        if (url === '/__server/logs' && req.method === 'GET') {
          res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
          })
          res.write(`event: state\ndata: ${JSON.stringify({ state, pid: childProcess?.pid ?? null, errorMessage })}\n\n`)
          sseClients.add(res)
          req.on('close', () => sseClients.delete(res))
          return
        }

        if (url === '/__server/logs/history' && req.method === 'GET') {
          sendJson(res, { lines: logBuffer })
          return
        }

        next()
      })

      server.httpServer?.on('close', cleanup)
    },
  }
}
