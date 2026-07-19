import { useCallback, useEffect, useRef, useState } from 'react'
import type { CSSProperties } from 'react'
import {
  fetchIsolates,
  fetchLogs,
  fetchStatus,
  openEvents,
  postJson,
  type IsolateInfo,
  type MonitorStatus,
} from './api/client'
import { Header } from './components/Header'
import { IsolatesPanel } from './components/IsolatesPanel'
import { NativeThreadsPanel } from './components/NativeThreadsPanel'
import { LogsPanel } from './components/LogsPanel'
import { ScreenPanel } from './components/ScreenPanel'
import {
  formatFileOpenerLabel,
  resolveFileRefFromLines,
} from './lib/logUtils'
import './styles/monitor.css'

interface UiAction {
  message: string
  isError: boolean
  isOk: boolean
  busy: boolean
}

const emptyAction: UiAction = {
  message: '',
  isError: false,
  isOk: false,
  busy: false,
}

export default function App() {
  const [status, setStatus] = useState<MonitorStatus | null>(null)
  const [statusText, setStatusText] = useState('Starting monitor...')
  const [statusClass, setStatusClass] = useState<'waiting' | 'connected'>('waiting')
  const [flutterLines, setFlutterLines] = useState<string[]>([])
  const [deviceLines, setDeviceLines] = useState<string[]>([])
  const [isolates, setIsolates] = useState<IsolateInfo[]>([])
  const [flutterStatus, setFlutterStatus] = useState('')
  const [flutterStatusError, setFlutterStatusError] = useState(false)
  const [uiAction, setUiAction] = useState<UiAction>(emptyAction)
  const [busy, setBusy] = useState({
    refresh: false,
    reloadGui: false,
    reinstall: false,
    hotReload: false,
    hotRestart: false,
    stop: false,
  })
  const [splitRatio, setSplitRatio] = useState(0.55)
  const clearTimer = useRef<number | null>(null)
  const refreshInFlight = useRef(false)
  const lastIsolatesFetch = useRef(0)
  const flutterGen = useRef(-1)
  const sessionRev = useRef(-1)

  const showFeedback = useCallback(
    (message: string, opts: { isError?: boolean; isOk?: boolean } = {}) => {
      if (clearTimer.current) {
        window.clearTimeout(clearTimer.current)
        clearTimer.current = null
      }
      setUiAction({
        message,
        isError: !!opts.isError,
        isOk: !!opts.isOk,
        busy: !!message && !opts.isError && !opts.isOk,
      })
      if (opts.isOk && message) {
        clearTimer.current = window.setTimeout(() => setUiAction(emptyAction), 2500)
      }
    },
    [],
  )

  const refresh = useCallback(
    async (statusOverride?: MonitorStatus, force = false) => {
      if (refreshInFlight.current && !statusOverride && !force) return
      refreshInFlight.current = true
      try {
        const next = statusOverride || (await fetchStatus())
        setStatus(next)

        const debugMode = next.mode === 'debug'
        const profileMode = next.mode === 'profile'
        const storeReleaseMode = next.mode === 'release'
        const connected = next.vmConnected === true
        const logsStreaming = next.logsStreaming === true
        const deviceLogsLive = next.logsConnected === true
        const deviceLogsEnabled = next.deviceLogsEnabled === true

        const logPart = deviceLogsLive
          ? `${next.logLineCount} log lines`
          : logsStreaming
            ? 'logcat connected'
            : deviceLogsEnabled
              ? 'connecting logs'
              : ''
        const vmPart = connected
          ? `VM ${next.vmUri || 'connected'}`
          : storeReleaseMode
            ? 'no VM service in store release'
            : profileMode
              ? 'waiting for profile VM service'
              : 'waiting for VM service'

        if (connected || deviceLogsLive) {
          setStatusClass('connected')
        } else {
          setStatusClass('waiting')
        }

        if (connected && deviceLogsLive) {
          setStatusText(
            `${vmPart} · streaming ${logPart} from ${next.device || 'device'}`,
          )
        } else if (connected) {
          setStatusText(logPart ? `${vmPart} · ${logPart}` : vmPart)
        } else if (deviceLogsLive) {
          setStatusText(
            `Streaming ${logPart} from ${next.device || next.package || 'device'} · ${vmPart}`,
          )
        } else if (logsStreaming) {
          setStatusText(`Logcat connected on ${next.device || 'device'} — ${vmPart}...`)
        } else {
          setStatusText(
            logPart
              ? storeReleaseMode
                ? `Waiting for store release app — ${logPart}`
                : profileMode
                  ? `Waiting for profile app — ${logPart} · ${vmPart}`
                  : `Waiting for debug app — ${logPart}`
              : storeReleaseMode
                ? 'Waiting for Flutter release app... Build/run is in progress.'
                : profileMode
                  ? 'Waiting for Flutter profile app... Build/run is in progress.'
                  : 'Waiting for Flutter debug app... Build/run is in progress.',
          )
        }

        if (deviceLogsEnabled) {
          const logsPayload = await fetchLogs()
          const nextGen = logsPayload.flutterDeployGeneration ?? 0
          const flutterOut = logsPayload.reinstallOutput || []
          if (nextGen !== flutterGen.current) {
            flutterGen.current = nextGen
            setFlutterLines(flutterOut)
          } else {
            setFlutterLines(flutterOut)
          }

          const nextSession = logsPayload.sessionRevision ?? 0
          const lines = logsPayload.lines || []
          if (nextSession !== sessionRev.current) {
            sessionRev.current = nextSession
            setDeviceLines(lines)
          } else {
            setDeviceLines(lines)
          }
        }

        if (connected && !storeReleaseMode) {
          const now = Date.now()
          if (force || now - lastIsolatesFetch.current > 2500) {
            lastIsolatesFetch.current = now
            try {
              const payload = await fetchIsolates()
              setIsolates(payload.isolates || [])
            } catch {
              // ignore isolate fetch errors
            }
          }
        } else {
          setIsolates([])
        }

        void debugMode
      } catch (error) {
        setStatusClass('waiting')
        setStatusText(`Monitor error: ${error}`)
      } finally {
        refreshInFlight.current = false
      }
    },
    [],
  )

  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    if (params.has('_reload')) {
      params.delete('_reload')
      const cleanQuery = params.toString()
      window.history.replaceState(
        null,
        '',
        `${window.location.pathname}${cleanQuery ? `?${cleanQuery}` : ''}${window.location.hash}`,
      )
    }

    void refresh(undefined, true)
    const source = openEvents((s) => {
      void refresh(s, true)
    })
    const timer = window.setInterval(() => void refresh(), 1000)
    return () => {
      source.close()
      window.clearInterval(timer)
    }
  }, [refresh])

  async function openFileReference(reference: string) {
    if (!reference) return
    if (!status?.canOpenFiles) {
      showFeedback(
        'File open unavailable — start the monitor with your Flutter project path.',
        { isError: true },
      )
      return
    }
    showFeedback('Opening file in editor…')
    try {
      const payload = await postJson<{
        ok?: boolean
        error?: string
        path?: string
        line?: number
        opener?: string
      }>('/api/open-file', { reference })
      if (!payload.ok) {
        showFeedback(payload.error || 'Could not open file in editor', { isError: true })
        return
      }
      showFeedback(
        `Opened ${payload.path}:${payload.line} in ${formatFileOpenerLabel(payload.opener || status.fileOpener || '')}`,
        { isOk: true },
      )
    } catch (error) {
      showFeedback(`Open file failed: ${error}`, { isError: true })
    }
  }

  function onErrorTagTap(lineIndex: number, sessionLines: string[]) {
    showFeedback('Looking for source file in stack trace…')
    const ref = resolveFileRefFromLines(sessionLines, lineIndex)
    if (!ref) {
      showFeedback(
        'No file:line found for this error — check the stack trace below.',
        { isError: true },
      )
      return
    }
    void openFileReference(ref)
  }

  async function runFlutterAction(
    path: string,
    pending: string,
    key: 'hotReload' | 'hotRestart' | 'stop',
  ) {
    setFlutterStatus(pending)
    setFlutterStatusError(false)
    showFeedback(pending)
    setBusy((b) => ({ ...b, [key]: true }))
    try {
      const payload = await postJson<{
        ok?: boolean
        error?: string
        message?: string
      }>(path)
      if (!payload.ok) {
        const message = payload.error || payload.message || 'Action failed'
        setFlutterStatus(message)
        setFlutterStatusError(true)
        showFeedback(message, { isError: true })
      } else {
        const message = payload.message || 'Done'
        setFlutterStatus(message)
        setFlutterStatusError(false)
        showFeedback(message, { isOk: true })
      }
      await refresh(undefined, true)
    } catch (error) {
      const message = `Action failed: ${error}`
      setFlutterStatus(message)
      setFlutterStatusError(true)
      showFeedback(message, { isError: true })
    } finally {
      setBusy((b) => ({ ...b, [key]: false }))
    }
  }

  const deviceLogsEnabled = status?.deviceLogsEnabled === true
  const storeReleaseMode = status?.mode === 'release'
  const showRight =
    deviceLogsEnabled ||
    status?.adbAvailable === true ||
    status?.flutterAvailable === true ||
    status?.screenMirrorAvailable === true

  return (
    <div className="app-shell">
      <Header
        status={status}
        statusText={statusText}
        statusClass={statusClass}
        flutterStatus={flutterStatus}
        flutterStatusError={flutterStatusError}
        uiAction={uiAction}
        busy={busy}
        onFeedback={showFeedback}
        onBackendChanged={() => void refresh(undefined, true)}
        onRefresh={async () => {
          setBusy((b) => ({ ...b, refresh: true }))
          showFeedback('Refreshing UI — fetching status, logs, and isolates…')
          try {
            await refresh(undefined, true)
            showFeedback('UI refreshed.', { isOk: true })
          } catch (error) {
            showFeedback(`Refresh failed: ${error}`, { isError: true })
          } finally {
            setBusy((b) => ({ ...b, refresh: false }))
          }
        }}
        onReloadGui={() => {
          setBusy((b) => ({ ...b, reloadGui: true }))
          showFeedback('Reloading page — loading latest monitor UI…')
          window.setTimeout(() => {
            const url = new URL(window.location.href)
            url.searchParams.set('_reload', String(Date.now()))
            window.location.replace(url.toString())
          }, 150)
        }}
        onReinstall={async () => {
          setBusy((b) => ({ ...b, reinstall: true }))
          showFeedback('Starting reinstall — rebuilding and redeploying app…')
          setFlutterLines(['Starting reinstall...'])
          setDeviceLines([])
          sessionRev.current = -1
          flutterGen.current = -1
          try {
            const res = await fetch('/api/reinstall', { method: 'POST' })
            const payload = (await res.json()) as {
              ok?: boolean
              error?: string
              message?: string
            }
            if (!res.ok) {
              const message = payload.error || 'Reinstall failed'
              setFlutterLines([message])
              showFeedback(message, { isError: true })
              return
            }
            const message = payload.message || 'Reinstall started'
            setFlutterLines([message])
            showFeedback(message, { isOk: true })
            await refresh(undefined, true)
          } catch (error) {
            showFeedback(`Reinstall failed: ${error}`, { isError: true })
          } finally {
            setBusy((b) => ({ ...b, reinstall: false }))
          }
        }}
        onHotReload={() =>
          void runFlutterAction('/api/flutter/hot-reload', 'Sending hot reload…', 'hotReload')
        }
        onHotRestart={() =>
          void runFlutterAction(
            '/api/flutter/hot-restart',
            'Sending hot restart…',
            'hotRestart',
          )
        }
        onStop={() => {
          if (!window.confirm('Stop the running Flutter app?')) return
          void runFlutterAction('/api/flutter/stop', 'Stopping Flutter app…', 'stop')
        }}
      />

      <main
        className={`monitor-layout${showRight ? ' has-right-panel' : ''}`}
        id="monitor-layout"
      >
        <div className="monitor-left" id="monitor-left">
          {deviceLogsEnabled ? (
            <div
              className="logs-split-stack has-resize"
              style={
                {
                  ['--split-top']: `${Math.round(splitRatio * 100)}%`,
                } as CSSProperties
              }
            >
              <LogsPanel
                title="Flutter logs"
                className="flutter-logs-panel"
                lines={flutterLines}
                canOpenFiles={status?.canOpenFiles === true}
                fileOpenerName={status?.fileOpener || ''}
                emptyMessage="Flutter run output will appear here when deploy starts."
                onOpenFile={(ref) => void openFileReference(ref)}
                onErrorTagTap={onErrorTagTap}
                onFeedback={showFeedback}
              />
              <div
                className="panel-resize-handle"
                role="separator"
                aria-orientation="horizontal"
                aria-label="Resize Flutter and device log panels"
                tabIndex={0}
                onPointerDown={(event) => {
                  const stack = (event.currentTarget.parentElement as HTMLElement) || null
                  if (!stack) return
                  const rect = stack.getBoundingClientRect()
                  const onMove = (ev: PointerEvent) => {
                    const y = ev.clientY - rect.top
                    const next = Math.min(0.85, Math.max(0.15, y / rect.height))
                    setSplitRatio(next)
                  }
                  const onUp = () => {
                    window.removeEventListener('pointermove', onMove)
                    window.removeEventListener('pointerup', onUp)
                  }
                  window.addEventListener('pointermove', onMove)
                  window.addEventListener('pointerup', onUp)
                }}
              />
              <LogsPanel
                title="Device logs"
                className="device-logs-panel"
                lines={deviceLines}
                canOpenFiles={status?.canOpenFiles === true}
                fileOpenerName={status?.fileOpener || ''}
                sessionHint="Session buffer kept until reinstall."
                showLegend
                showBookmarks
                preferTripStreamFilter={storeReleaseMode}
                emptyMessage={
                  storeReleaseMode
                    ? 'No matching device logs yet. Trip stream filter: TripStreamIsolate|TripStreamSession|TripStreamNavForwarder|flutter'
                    : 'No log lines yet for this session.'
                }
                onOpenFile={(ref) => void openFileReference(ref)}
                onErrorTagTap={onErrorTagTap}
                onFeedback={showFeedback}
              />
            </div>
          ) : null}
        </div>

        {showRight ? (
          <div className="monitor-right" id="monitor-right">
            <IsolatesPanel
              isolates={isolates}
              hidden={storeReleaseMode}
              onFeedback={showFeedback}
            />
            <NativeThreadsPanel
              enabled={storeReleaseMode}
              onFeedback={showFeedback}
            />
            <ScreenPanel
              status={status}
              onFeedback={showFeedback}
              onStatusMaybeChanged={() => void refresh(undefined, true)}
            />
          </div>
        ) : null}
      </main>
    </div>
  )
}
