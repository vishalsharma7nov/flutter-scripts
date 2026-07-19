export const FILE_REF_PATTERN =
  /((?:package:[^\s:()]+\.dart|file:\/\/[^\s:()]+\.dart|\/[^\s:()]+\.dart|[A-Za-z]:[\\/][^\s:()]+\.dart|[A-Za-z0-9_.][A-Za-z0-9_./\\-]*\.dart)):(\d+)(?::(\d+))?/g

export const FILE_REF_IN_PARENS_PATTERN = /\(([^()]+\.dart:\d+(?::\d+)?)\)/

export const STACK_FRAME_FILE_PATTERN =
  /#\d+\s+[\w.<>,\s$]+\(([^()]+\.dart:\d+(?::\d+)?)\)/

export const ERROR_LEVELS = new Set(['error', 'fatal', 'assert'])
export const STACK_TRACE_LOOKAHEAD = 18
export const MAX_DOM_LOG_LINES = 1200
export const LOG_WINDOW_LOAD_CHUNK = 600

export type LogLevel =
  | 'verbose'
  | 'debug'
  | 'info'
  | 'warning'
  | 'error'
  | 'fatal'
  | 'assert'
  | 'default'

export function normalizeFileRef(
  path: string,
  line: string,
  column?: string,
): string {
  return `${path}:${line}:${column || '1'}`
}

function fileRefFromMatch(match: RegExpMatchArray | null): string | null {
  if (!match) return null
  if (match.length >= 4 && match[1] && match[2]) {
    return normalizeFileRef(match[1], match[2], match[3])
  }
  const grouped = match[1]
  const nested = grouped?.match(/^(.+\.dart):(\d+)(?::(\d+))?$/)
  if (!nested) return null
  return normalizeFileRef(nested[1], nested[2], nested[3])
}

export function extractFirstFileRef(line: string): string | null {
  const patterns = [
    FILE_REF_PATTERN,
    STACK_FRAME_FILE_PATTERN,
    FILE_REF_IN_PARENS_PATTERN,
  ]
  for (const source of patterns) {
    const pattern = new RegExp(
      source.source,
      source.flags.includes('g') ? source.flags : `${source.flags}g`,
    )
    const match = pattern.exec(line)
    const ref = fileRefFromMatch(match)
    if (ref) return ref
  }
  return null
}

export function resolveFileRefFromLines(
  lines: string[],
  lineIndex: number,
): string | null {
  if (lineIndex < 0 || lineIndex >= lines.length) return null
  const direct = extractFirstFileRef(lines[lineIndex])
  if (direct) return direct
  const end = Math.min(lines.length, lineIndex + 1 + STACK_TRACE_LOOKAHEAD)
  for (let i = lineIndex + 1; i < end; i += 1) {
    const ref = extractFirstFileRef(lines[i])
    if (ref) return ref
  }
  return null
}

function levelFromLetter(letter: string): LogLevel {
  switch (letter.toUpperCase()) {
    case 'V':
      return 'verbose'
    case 'D':
      return 'debug'
    case 'I':
      return 'info'
    case 'W':
      return 'warning'
    case 'E':
      return 'error'
    case 'F':
      return 'fatal'
    case 'A':
      return 'assert'
    default:
      return 'default'
  }
}

export function classifyLogLine(line: string): LogLevel {
  const text = line.trim()
  if (!text) return 'default'

  const androidTime = text.match(
    /\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+\d+\s+([VDIWEFA])\s/,
  )
  if (androidTime) return levelFromLetter(androidTime[1])

  const slashLevel = text.match(/(?:^|\s)([VDIWEFA])\/\S+/)
  if (slashLevel) return levelFromLetter(slashLevel[1])

  const spaceLevel = text.match(/\s([VDIWEFA])\s[A-Za-z0-9_.-]+:/)
  if (spaceLevel) return levelFromLetter(spaceLevel[1])

  if (
    /\[(?:stderr)\]/i.test(text) &&
    /\b(error|exception|failed)\b/i.test(text)
  ) {
    return 'error'
  }
  if (/\b(?:E\/flutter|ERROR:flutter)\b/i.test(text)) return 'error'
  if (/\b(?:W\/flutter|WARNING:flutter)\b/i.test(text)) return 'warning'
  if (/\[(?:ERROR|SEVERE)\]/i.test(text)) return 'error'
  if (/\[(?:WARNING|WARN)\]/i.test(text)) return 'warning'
  if (/\[(?:INFO)\]/i.test(text)) return 'info'
  if (/\[(?:DEBUG|FINE)\]/i.test(text)) return 'debug'
  if (/\[(?:VERBOSE|TRACE)\]/i.test(text)) return 'verbose'
  if (/\[(?:FATAL)\]/i.test(text)) return 'fatal'
  if (/\bFATAL EXCEPTION\b|\bFATAL\b/i.test(text)) return 'fatal'
  if (/\bASSERT(?:ION)?(?: FAILED| ERROR)?\b/i.test(text)) return 'assert'
  if (
    /\bUnhandled exception\b/i.test(text) ||
    /\bException\b/.test(text) ||
    /\bError:\b/.test(text) ||
    /\bERROR\b/.test(text)
  ) {
    return 'error'
  }
  if (/\bWARN(?:ING)?\b/i.test(text)) return 'warning'
  if (/\bDEBUG\b/i.test(text)) return 'debug'
  if (/\bINFO\b/i.test(text)) return 'info'
  if (/\bVERBOSE\b|\bTRACE\b/i.test(text)) return 'verbose'
  return 'default'
}

export function levelTagLabel(level: LogLevel): string {
  switch (level) {
    case 'verbose':
      return 'VERBOSE'
    case 'debug':
      return 'DEBUG'
    case 'info':
      return 'INFO'
    case 'warning':
      return 'WARN'
    case 'error':
      return 'ERROR'
    case 'fatal':
      return 'FATAL'
    case 'assert':
      return 'ASSERT'
    default:
      return 'LOG'
  }
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

export function formatFileOpenerLabel(opener: string): string {
  switch (opener) {
    case 'cursor':
      return 'Cursor'
    case 'code':
    case 'vscode':
      return 'VS Code'
    case 'idea':
      return 'IntelliJ'
    case 'android-studio':
      return 'Android Studio'
    case 'textedit':
      return 'TextEdit'
    case 'notepad':
    case 'windows-notepad':
      return 'Notepad'
    default:
      return opener || 'editor'
  }
}

export function modeLabelText(mode: string | undefined): string {
  if (mode === 'profile') return 'profile (isolates + flutter + device logs)'
  if (mode === 'release') return 'release (store build · device logs only, no VM)'
  return 'debug (isolates + flutter + device logs)'
}

export function reinstallButtonLabel(mode: string | undefined): string {
  if (mode === 'release') return 'Reinstall release build'
  if (mode === 'profile') return 'Reinstall profile build'
  return 'Reinstall debug build'
}

export function computeLogWindow(
  lines: string[],
  windowStart: number,
  preferTail = false,
): { visibleLines: string[]; windowStart: number; indices: number[] } {
  const total = lines.length
  if (total <= MAX_DOM_LOG_LINES) {
    return {
      visibleLines: lines,
      windowStart: 0,
      indices: lines.map((_, i) => i),
    }
  }
  let start = preferTail ? total - MAX_DOM_LOG_LINES : windowStart
  start = Math.max(0, Math.min(start, total - MAX_DOM_LOG_LINES))
  const visibleLines = lines.slice(start, start + MAX_DOM_LOG_LINES)
  return {
    visibleLines,
    windowStart: start,
    indices: visibleLines.map((_, i) => start + i),
  }
}

export function filterLinesWithIndices(
  lines: string[],
  query: string,
  caseSensitive: boolean,
): { line: string; index: number }[] {
  const trimmed = query.trim()
  if (!trimmed) {
    return lines.map((line, index) => ({ line, index }))
  }

  // Support grep -E style OR: "TripStreamWorker|TripStreamIsolate|flutter"
  const terms = trimmed
    .split('|')
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => (caseSensitive ? t : t.toLowerCase()))

  const matches: { line: string; index: number }[] = []
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    const haystack = caseSensitive ? line : line.toLowerCase()
    if (terms.some((term) => haystack.includes(term))) {
      matches.push({ line, index })
    }
  }
  return matches
}

/** Quick filter chips for device log panel (release Android focus). */
export type LogFilterBookmark = {
  id: string
  label: string
  /** Empty = show all lines */
  query: string
  title?: string
}

export const DEVICE_LOG_BOOKMARKS: LogFilterBookmark[] = [
  {
    id: 'all',
    label: 'All',
    query: '',
    title: 'Show every buffered device log line',
  },
  {
    id: 'trip-stream',
    label: 'Trip stream',
    query: 'TripStreamIsolate|TripStreamSession|TripStreamNavForwarder|flutter',
    title:
      "adb logcat | grep -E 'TripStreamIsolate|TripStreamSession|TripStreamNavForwarder|flutter'",
  },
  {
    id: 'flutter',
    label: 'Flutter',
    query: 'flutter',
    title: 'Lines mentioning flutter',
  },
  {
    id: 'errors',
    label: 'Errors',
    query: 'ERROR|FATAL|Exception|Unhandled',
    title: 'Error / fatal / exception lines',
  },
]

export const DEFAULT_RELEASE_DEVICE_BOOKMARK = 'trip-stream'
