import { useCallback, useEffect, useRef, useState } from 'react'
import {
  fetchDevices,
  postJson,
  screenFrameUrl,
  type DeviceInfo,
  type MonitorStatus,
} from '../api/client'

interface ScreenPanelProps {
  status: MonitorStatus | null
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
  onStatusMaybeChanged: () => void
}

const SCREEN_FRAME_MS = 66
const SCREEN_TAP_THRESHOLD_PX = 10

export function ScreenPanel({
  status,
  onFeedback,
  onStatusMaybeChanged,
}: ScreenPanelProps) {
  const [devices, setDevices] = useState<DeviceInfo[]>([])
  const [selected, setSelected] = useState('')
  const [deviceStatus, setDeviceStatus] = useState('')
  const [paused, setPaused] = useState(false)
  const [frameSrc, setFrameSrc] = useState('')
  const [connectHost, setConnectHost] = useState('')
  const [pairHost, setPairHost] = useState('')
  const [pairPort, setPairPort] = useState('')
  const [pairCode, setPairCode] = useState('')
  const pointerStart = useRef<{ x: number; y: number; clientX: number; clientY: number } | null>(
    null,
  )
  const frameRef = useRef<HTMLDivElement>(null)
  const imgRef = useRef<HTMLImageElement>(null)

  const [connectMode, setConnectMode] = useState<'debug' | 'profile' | 'release'>('debug')

  const available = status?.screenMirrorAvailable === true
  const showPanel =
    status?.deviceLogsEnabled === true ||
    status?.adbAvailable === true ||
    status?.flutterAvailable === true ||
    available

  useEffect(() => {
    if (status?.mode === 'debug' || status?.mode === 'profile' || status?.mode === 'release') {
      setConnectMode(status.mode)
    }
  }, [status?.mode])

  const refreshDevices = useCallback(async () => {
    try {
      const payload = await fetchDevices()
      const list = payload.devices || []
      setDevices(list)
      const next =
        payload.selected ||
        status?.screenDevice ||
        status?.device ||
        list[0]?.id ||
        list[0]?.serial ||
        ''
      setSelected(next)
      setDeviceStatus(
        payload.adbAvailable === false
          ? 'adb not available'
          : `${list.length} device${list.length === 1 ? '' : 's'}`,
      )
    } catch (error) {
      setDeviceStatus(`Device scan failed: ${error}`)
    }
  }, [status?.device, status?.screenDevice])

  useEffect(() => {
    if (showPanel) {
      void refreshDevices()
    }
  }, [showPanel, refreshDevices])

  useEffect(() => {
    if (!available || paused) {
      setFrameSrc('')
      return
    }
    const tick = () => {
      setFrameSrc(screenFrameUrl(status?.screenFrameSequence))
    }
    tick()
    const timer = window.setInterval(tick, SCREEN_FRAME_MS)
    return () => window.clearInterval(timer)
  }, [available, paused, status?.screenFrameSequence])

  if (!showPanel) return null

  function normalizePoint(clientX: number, clientY: number) {
    const rect = imgRef.current?.getBoundingClientRect()
    if (!rect || rect.width <= 0 || rect.height <= 0) {
      return { x: 0, y: 0 }
    }
    const width = status?.screenWidth || rect.width
    const height = status?.screenHeight || rect.height
    const x = ((clientX - rect.left) / rect.width) * width
    const y = ((clientY - rect.top) / rect.height) * height
    return {
      x: Math.max(0, Math.min(width, Math.round(x))),
      y: Math.max(0, Math.min(height, Math.round(y))),
    }
  }

  async function selectDevice(id: string) {
    setSelected(id)
    if (!id) return
    onFeedback(`Connecting to ${id} (${connectMode})…`)
    const payload = await postJson<{ ok?: boolean; error?: string; message?: string }>(
      '/api/devices/select',
      { device: id, serial: id, mode: connectMode },
    )
    if (!payload.ok) {
      onFeedback(payload.error || payload.message || 'Connect failed', { isError: true })
      return
    }
    onFeedback(payload.message || `Connected to ${id}`, { isOk: true })
    onStatusMaybeChanged()
  }

  async function applyMode(mode: 'debug' | 'profile' | 'release') {
    setConnectMode(mode)
    onFeedback(`Switching to ${mode}…`)
    const payload = await postJson<{ ok?: boolean; error?: string; message?: string }>(
      '/api/mode',
      { mode },
    )
    if (!payload.ok) {
      onFeedback(payload.error || payload.message || 'Mode switch failed', { isError: true })
      return
    }
    onFeedback(payload.message || `Mode: ${mode}`, { isOk: true })
    onStatusMaybeChanged()
  }

  return (
    <aside className={`screen-panel${available ? '' : ''}`}>
      <h2>Device screen</h2>
      <div className="screen-panel-body">
        <div className="device-controls">
          <div className="device-row">
            <select
              aria-label="Build mode"
              value={connectMode}
              onChange={(e) =>
                void applyMode(e.target.value as 'debug' | 'profile' | 'release')
              }
              title="debug = VM+hot reload · profile = near-release+VM · release = store build, logs only"
            >
              <option value="debug">debug</option>
              <option value="profile">profile</option>
              <option value="release">release</option>
            </select>
            <select
              aria-label="ADB device"
              value={selected}
              onChange={(e) => setSelected(e.target.value)}
            >
              {devices.length === 0 ? (
                <option value="">No devices</option>
              ) : (
                <>
                  <option value="">Select a device…</option>
                  {devices.map((d) => {
                    const id = d.id || d.serial || ''
                    const label = [d.name || d.model || id, d.state].filter(Boolean).join(' · ')
                    return (
                      <option key={id} value={id}>
                        {label}
                      </option>
                    )
                  })}
                </>
              )}
            </select>
            <button
              type="button"
              className="button"
              disabled={!selected}
              onClick={() => void selectDevice(selected)}
            >
              Connect
            </button>
            <button
              type="button"
              className="button secondary"
              onClick={() => {
                onFeedback('Scanning devices…')
                void refreshDevices().then(() =>
                  onFeedback('Device list refreshed.', { isOk: true }),
                )
              }}
            >
              Scan
            </button>
          </div>
          {status?.device ? (
            <p className="device-active-hint">
              Active: {status.device}
              {status.mode ? ` · ${status.mode}` : ''}
            </p>
          ) : null}
          <details>
            <summary>Manual IP / pairing</summary>
            <div className="device-row" style={{ marginTop: 6 }}>
              <input
                type="text"
                placeholder="192.168.1.20:5555"
                value={connectHost}
                onChange={(e) => setConnectHost(e.target.value)}
                autoComplete="off"
              />
              <button
                type="button"
                className="button secondary"
                onClick={async () => {
                  const address = connectHost.trim()
                  if (!address) {
                    onFeedback('Enter device address as host:port', { isError: true })
                    return
                  }
                  onFeedback(`Connecting to ${address}…`)
                  const payload = await postJson<{
                    ok?: boolean
                    error?: string
                    message?: string
                  }>('/api/devices/connect', { address })
                  if (!payload.ok) {
                    onFeedback(payload.error || payload.message || 'Connect failed', {
                      isError: true,
                    })
                    return
                  }
                  onFeedback(payload.message || `Connected to ${address}`, { isOk: true })
                  await refreshDevices()
                  await selectDevice(address)
                  onStatusMaybeChanged()
                }}
              >
                Connect IP
              </button>
            </div>
            <div className="device-row" style={{ marginTop: 6 }}>
              <input
                type="text"
                placeholder="Host"
                value={pairHost}
                onChange={(e) => setPairHost(e.target.value)}
                autoComplete="off"
              />
              <input
                type="text"
                placeholder="Port"
                value={pairPort}
                onChange={(e) => setPairPort(e.target.value)}
                autoComplete="off"
              />
              <input
                type="text"
                placeholder="Code"
                value={pairCode}
                onChange={(e) => setPairCode(e.target.value)}
                autoComplete="off"
              />
              <button
                type="button"
                className="button secondary"
                onClick={async () => {
                  if (!pairHost.trim() || !pairPort.trim() || !pairCode.trim()) {
                    onFeedback('Host, port, and pairing code are required', { isError: true })
                    return
                  }
                  onFeedback('Pairing device…')
                  const payload = await postJson<{
                    ok?: boolean
                    error?: string
                    message?: string
                  }>('/api/devices/pair', {
                    host: pairHost.trim(),
                    port: pairPort.trim(),
                    code: pairCode.trim(),
                  })
                  if (!payload.ok) {
                    onFeedback(payload.error || payload.message || 'Pair failed', {
                      isError: true,
                    })
                    return
                  }
                  onFeedback(payload.message || 'Paired', { isOk: true })
                  await refreshDevices()
                }}
              >
                Pair
              </button>
            </div>
          </details>
          <p className="device-hint">
            USB or LAN devices — connect with IP:port for wireless debugging.
          </p>
          <p className="device-status">{deviceStatus}</p>
        </div>
        <p className="screen-meta">
          {available
            ? 'Android mirror via adb. Click to tap, drag to swipe.'
            : status?.screenMirrorError || 'Screen mirror unavailable'}
        </p>
        <div
          ref={frameRef}
          className="screen-frame"
          onPointerDown={(event) => {
            if (!available || paused) return
            const point = normalizePoint(event.clientX, event.clientY)
            pointerStart.current = {
              ...point,
              clientX: event.clientX,
              clientY: event.clientY,
            }
            ;(event.target as HTMLElement).setPointerCapture?.(event.pointerId)
          }}
          onPointerUp={async (event) => {
            if (!available || paused || !pointerStart.current) return
            const start = pointerStart.current
            pointerStart.current = null
            const end = normalizePoint(event.clientX, event.clientY)
            const dx = event.clientX - start.clientX
            const dy = event.clientY - start.clientY
            const dist = Math.hypot(dx, dy)
            if (dist < SCREEN_TAP_THRESHOLD_PX) {
              await postJson('/api/screen/tap', { x: end.x, y: end.y })
            } else {
              await postJson('/api/screen/swipe', {
                x1: start.x,
                y1: start.y,
                x2: end.x,
                y2: end.y,
              })
            }
          }}
        >
          {available && frameSrc ? (
            <img ref={imgRef} src={frameSrc} alt="Android device screen" />
          ) : null}
        </div>
      </div>
      <div className="screen-actions">
        <button
          type="button"
          className="button secondary"
          onClick={() => {
            setPaused((p) => !p)
            onFeedback(paused ? 'Screen mirror resumed.' : 'Screen mirror paused.', {
              isOk: true,
            })
          }}
        >
          {paused ? 'Resume' : 'Pause'}
        </button>
        <button
          type="button"
          className="button secondary"
          onClick={async () => {
            onFeedback('Launching scrcpy…')
            const payload = await postJson<{
              ok?: boolean
              error?: string
              message?: string
            }>('/api/screen/scrcpy')
            if (!payload.ok) {
              onFeedback(payload.error || payload.message || 'scrcpy failed', {
                isError: true,
              })
              return
            }
            onFeedback(payload.message || 'scrcpy launched', { isOk: true })
          }}
        >
          Open scrcpy
        </button>
      </div>
    </aside>
  )
}
