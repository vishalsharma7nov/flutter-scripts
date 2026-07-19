/** Optional filters for named Dart isolate → OS thread mapping (≤15 chars on Android). */

export type ReleaseWorkerRef = {
  id: string
  /** Shown in debug/profile Dart isolates panel (VM service). */
  dartIsolateName: string
  /** OS thread name set via pthread (≤15 chars). Visible in release adb. */
  nativeThreadName: string
  /** dart:developer log name: tags in device logcat. */
  logTags: string[]
  role: string
}

/**
 * Example named workers. Override patterns in your app as you like —
 * bookmarks below use the nativeThreadName values only.
 */
export const RELEASE_WORKERS: ReleaseWorkerRef[] = [
  {
    id: 'worker-a',
    dartIsolateName: 'BackgroundWorkerA',
    nativeThreadName: 'app-wrk-a',
    logTags: ['BackgroundWorkerA', 'IsolateWorkerThread'],
    role: 'Example background isolate A',
  },
  {
    id: 'worker-b',
    dartIsolateName: 'BackgroundWorkerB',
    nativeThreadName: 'app-wrk-b',
    logTags: ['BackgroundWorkerB', 'IsolateWorkerThread'],
    role: 'Example background isolate B',
  },
  {
    id: 'worker-c',
    dartIsolateName: 'BackgroundWorkerC',
    nativeThreadName: 'app-wrk-c',
    logTags: ['BackgroundWorkerC', 'IsolateWorkerThread'],
    role: 'Example background isolate C',
  },
  {
    id: 'nav',
    dartIsolateName: 'main',
    nativeThreadName: 'main',
    logTags: [],
    role: 'App main isolate / UI thread',
  },
]

export type ThreadFilterBookmark = {
  id: string
  label: string
  query: string
  title?: string
}

export const THREAD_FILTER_BOOKMARKS: ThreadFilterBookmark[] = [
  {
    id: 'all',
    label: 'All',
    query: '',
    title: 'Show every native thread',
  },
  {
    id: 'named-workers',
    label: 'Named workers',
    query: 'app-wrk-a|app-wrk-b|app-wrk-c',
    title: 'Named isolate workers (after your app renames OS threads)',
  },
  {
    id: 'flutter-workers',
    label: 'Flutter workers',
    query: 'flutter-worker',
    title: 'Unnamed Dart workers (engine pool / before rename)',
  },
  {
    id: 'worker-a',
    label: 'Worker A',
    query: 'app-wrk-a',
    title: 'BackgroundWorkerA → app-wrk-a',
  },
  {
    id: 'worker-b',
    label: 'Worker B',
    query: 'app-wrk-b',
    title: 'BackgroundWorkerB → app-wrk-b',
  },
  {
    id: 'worker-c',
    label: 'Worker C',
    query: 'app-wrk-c',
    title: 'BackgroundWorkerC → app-wrk-c',
  },
  {
    id: 'dart',
    label: 'Dart VM',
    query: 'DartVM|dart',
    title: 'Dart VM / runtime threads',
  },
]

export const DEFAULT_RELEASE_THREAD_BOOKMARK = 'named-workers'

export function filterThreads<
  T extends { tid?: string; name?: string; pid?: string; state?: string },
>(threads: T[], query: string, caseSensitive: boolean): T[] {
  const trimmed = query.trim()
  if (!trimmed) return threads
  const terms = trimmed
    .split('|')
    .map((t) => t.trim())
    .filter(Boolean)
    .map((t) => (caseSensitive ? t : t.toLowerCase()))
  return threads.filter((t) => {
    const hay = [t.tid, t.name, t.pid, t.state].filter(Boolean).join(' ')
    const stack = caseSensitive ? hay : hay.toLowerCase()
    return terms.some((term) => stack.includes(term))
  })
}

export function isNamedAppWorkerThread(name: string): boolean {
  const lower = name.toLowerCase()
  return (
    lower.includes('app-wrk-a') ||
    lower.includes('app-wrk-b') ||
    lower.includes('app-wrk-c')
  )
}

export function isFlutterWorkerThread(name: string): boolean {
  return name.toLowerCase().includes('flutter-worker')
}

export function workerKindLabel(name: string): string | null {
  const lower = name.toLowerCase()
  if (lower.includes('app-wrk-a')) return 'worker-a'
  if (lower.includes('app-wrk-b')) return 'worker-b'
  if (lower.includes('app-wrk-c')) return 'worker-c'
  if (isFlutterWorkerThread(name)) return 'worker'
  return null
}

/** adb /proc/.../comm names are capped at 15 characters on Android. */
export function nativeThreadNameHint(name: string): string | null {
  const kind = workerKindLabel(name)
  if (kind === 'worker-a') {
    return 'BackgroundWorkerA OS name (app-wrk-a)'
  }
  if (kind === 'worker-b') {
    return 'BackgroundWorkerB OS name (app-wrk-b)'
  }
  if (kind === 'worker-c') {
    return 'BackgroundWorkerC OS name (app-wrk-c)'
  }
  if (kind === 'worker') {
    return 'Unnamed Dart worker — rebuild app with OS thread rename, or idle flutter pool thread'
  }
  if (name === 'main' || name.startsWith('main ')) {
    return 'App main thread'
  }
  return null
}
