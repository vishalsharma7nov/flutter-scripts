export type MonitorMode = 'debug' | 'profile' | 'release'

export interface MonitorStatus {
  mode?: MonitorMode | string
  backend?: string
  preferredBackend?: string
  availableBackends?: string[]
  runnableBackends?: string[]
  backendHint?: string
  vmConnected?: boolean
  vmUri?: string | null
  logsStreaming?: boolean
  logsConnected?: boolean
  logLineCount?: number
  logsRevision?: number
  logSessionRevision?: number
  deployRevision?: number
  flutterDeployGeneration?: number
  flutterOutputRevision?: number
  logsError?: string | null
  package?: string
  bundleId?: string
  device?: string
  deviceLogsEnabled?: boolean
  canReinstall?: boolean
  reinstallRunning?: boolean
  reinstallError?: string | null
  projectRoot?: string
  dartPackageName?: string
  fileOpener?: string
  canOpenFiles?: boolean
  screenMirrorAvailable?: boolean
  screenMirrorError?: string | null
  screenWidth?: number
  screenHeight?: number
  screenFrameSequence?: number
  screenTargetFps?: number
  screenDevice?: string
  adbAvailable?: boolean
  flutterAvailable?: boolean
  bindHost?: string
  lanUrl?: string | null
  networkAccessEnabled?: boolean
  flutterRunActive?: boolean
  canHotReload?: boolean
  canHotRestart?: boolean
  canStopFlutter?: boolean
  workerIsolates?: boolean
}

export interface IsolateInfo {
  id?: string
  name?: string
  isSystemIsolate?: boolean
  number?: string | number
  pauseEvent?: { kind?: string } | null
  runnable?: boolean
}

export interface LogsPayload {
  lines?: string[]
  revision?: number
  sessionRevision?: number
  reinstallOutput?: string[]
  flutterDeployGeneration?: number
  flutterOutputRevision?: number
  deployRevision?: number
}

export interface DeviceInfo {
  id?: string
  serial?: string
  name?: string
  state?: string
  model?: string
  product?: string
  transport?: string
}

export interface DevicesPayload {
  devices?: DeviceInfo[]
  selected?: string
  adbAvailable?: boolean
  flutterAvailable?: boolean
}

export interface NativeThread {
  tid?: string
  name?: string
  pid?: string
  state?: string
}

export interface ThreadsPayload {
  ok?: boolean
  error?: string
  package?: string
  device?: string
  pid?: string
  threadCount?: number
  threads?: NativeThread[]
  source?: string
  note?: string
  hints?: string[]
}

async function parseJson<T>(res: Response): Promise<T> {
  const text = await res.text()
  if (!text) {
    if (!res.ok) {
      throw new Error(`Request failed (${res.status}) with empty body`)
    }
    return {} as T
  }
  try {
    return JSON.parse(text) as T
  } catch {
    const snippet = text.replace(/\s+/g, ' ').trim().slice(0, 120)
    if (res.status === 404 || /route not found/i.test(snippet)) {
      throw new Error(
        'Backend API missing — restart the isolate monitor to load the latest server, then Reload GUI.',
      )
    }
    throw new Error(
      `Expected JSON (${res.status}): ${snippet || 'empty response'}`,
    )
  }
}

export async function fetchStatus(): Promise<MonitorStatus> {
  const res = await fetch('/api/status')
  return parseJson(res)
}

export async function fetchLogs(): Promise<LogsPayload> {
  const res = await fetch('/api/logs')
  return parseJson(res)
}

export async function fetchIsolates(): Promise<{ isolates?: IsolateInfo[] }> {
  const res = await fetch('/api/isolates')
  return parseJson(res)
}

export async function fetchThreads(): Promise<ThreadsPayload> {
  const res = await fetch('/api/threads')
  return parseJson(res)
}

export async function fetchDevices(): Promise<DevicesPayload> {
  const res = await fetch('/api/devices')
  return parseJson(res)
}

export async function postJson<T = Record<string, unknown>>(
  path: string,
  body?: unknown,
): Promise<T> {
  const res = await fetch(path, {
    method: 'POST',
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  })
  return parseJson(res)
}

export function openEvents(onReady: (status: MonitorStatus) => void): EventSource {
  const source = new EventSource('/api/events')
  source.addEventListener('ready', (event) => {
    try {
      onReady(JSON.parse((event as MessageEvent).data) as MonitorStatus)
    } catch {
      // ignore malformed SSE payloads
    }
  })
  source.onmessage = (event) => {
    try {
      onReady(JSON.parse(event.data) as MonitorStatus)
    } catch {
      // ignore
    }
  }
  return source
}

export function screenFrameUrl(sequence?: number): string {
  const q = sequence != null ? `?t=${sequence}` : `?t=${Date.now()}`
  return `/api/screen/frame${q}`
}
