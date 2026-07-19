import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import { fetchThreads, type NativeThread, type ThreadsPayload } from '../api/client'
import {
  DEFAULT_RELEASE_THREAD_BOOKMARK,
  RELEASE_WORKERS,
  THREAD_FILTER_BOOKMARKS,
  filterThreads,
  isFlutterWorkerThread,
  isNamedAppWorkerThread,
  nativeThreadNameHint,
  workerKindLabel,
  type ThreadFilterBookmark,
} from '../lib/releaseWorkers'

interface NativeThreadsPanelProps {
  enabled: boolean
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
}

export function NativeThreadsPanel({ enabled, onFeedback }: NativeThreadsPanelProps) {
  const initialBookmark = THREAD_FILTER_BOOKMARKS.find(
    (b) => b.id === DEFAULT_RELEASE_THREAD_BOOKMARK,
  )
  const [payload, setPayload] = useState<ThreadsPayload | null>(null)
  const [query, setQuery] = useState(initialBookmark?.query ?? '')
  const [caseSensitive, setCaseSensitive] = useState(false)
  const [searchActive, setSearchActive] = useState(!!initialBookmark?.query)
  const [activeBookmarkId, setActiveBookmarkId] = useState(
    initialBookmark?.id ?? DEFAULT_RELEASE_THREAD_BOOKMARK,
  )
  const [showWorkerMap, setShowWorkerMap] = useState(true)
  const [loading, setLoading] = useState(false)
  const didAutoFilter = useRef(false)

  const refresh = useCallback(async () => {
    if (!enabled) return
    setLoading(true)
    try {
      const next = await fetchThreads()
      setPayload(next)
    } catch (error) {
      onFeedback(`Thread refresh failed: ${error}`, { isError: true })
    } finally {
      setLoading(false)
    }
  }, [enabled, onFeedback])

  useEffect(() => {
    if (!enabled || didAutoFilter.current) return
    const bookmark = THREAD_FILTER_BOOKMARKS.find(
      (b) => b.id === DEFAULT_RELEASE_THREAD_BOOKMARK,
    )
    if (!bookmark) return
    didAutoFilter.current = true
    setActiveBookmarkId(bookmark.id)
    setQuery(bookmark.query)
    setSearchActive(!!bookmark.query.trim())
  }, [enabled])

  useEffect(() => {
    if (!enabled) return
    void refresh()
    const timer = window.setInterval(() => void refresh(), 4000)
    return () => window.clearInterval(timer)
  }, [enabled, refresh])

  const threads = payload?.threads || []
  const filtered = useMemo(() => {
    if (!searchActive || !query.trim()) return threads
    return filterThreads(threads, query, caseSensitive)
  }, [threads, query, caseSensitive, searchActive])

  const flutterWorkerCount = useMemo(
    () => threads.filter((t) => isFlutterWorkerThread(t.name || '')).length,
    [threads],
  )
  const namedWorkerCount = useMemo(
    () => threads.filter((t) => isNamedAppWorkerThread(t.name || '')).length,
    [threads],
  )

  if (!enabled) return null

  function applyBookmark(bookmark: ThreadFilterBookmark) {
    setActiveBookmarkId(bookmark.id)
    setQuery(bookmark.query)
    if (!bookmark.query.trim()) {
      setSearchActive(false)
      onFeedback('Showing all native threads.', { isOk: true })
      return
    }
    setSearchActive(true)
    onFeedback(`Thread filter: ${bookmark.label}`)
  }

  function runSearch(event: FormEvent) {
    event.preventDefault()
    const trimmed = query.trim()
    if (!trimmed) {
      setSearchActive(false)
      setActiveBookmarkId('all')
      onFeedback('Thread search cleared.', { isOk: true })
      return
    }
    const match = THREAD_FILTER_BOOKMARKS.find(
      (b) => b.query.trim().toLowerCase() === trimmed.toLowerCase(),
    )
    setActiveBookmarkId(match?.id ?? '')
    setSearchActive(true)
    onFeedback(`Filtering threads for "${trimmed}"…`)
  }

  function clearSearch() {
    setQuery('')
    setSearchActive(false)
    setActiveBookmarkId('all')
    onFeedback('Thread search cleared.', { isOk: true })
  }

  return (
    <section className="isolates-panel native-threads-panel">
      <div className="panel-title-row">
        <h2>Native threads</h2>
        <button
          type="button"
          className="button secondary panel-toggle"
          onClick={() => setShowWorkerMap((v) => !v)}
          title="Dart isolate names vs adb thread names in release"
        >
          {showWorkerMap ? 'Hide worker map' : 'Worker map'}
        </button>
      </div>

      <div className="isolates-search-meta">
        <span>
          {payload?.ok
            ? `${filtered.length}${searchActive ? ` / ${threads.length}` : ''} threads`
            : 'release · no Dart isolates'}
        </span>
        {payload?.pid ? <span> · pid {payload.pid}</span> : null}
        {namedWorkerCount > 0 ? (
          <span> · {namedWorkerCount} named workers</span>
        ) : null}
        {flutterWorkerCount > 0 ? (
          <span> · {flutterWorkerCount} flutter-worker</span>
        ) : null}
        <span> · adb</span>
      </div>

      {showWorkerMap ? (
        <div className="release-worker-map" role="region" aria-label="Release worker naming">
          <p className="release-worker-map-lead">
            In <strong>release</strong>, Dart isolates are hidden. Optionally
            rename worker OS threads to short names like <code>app-wrk-a</code>{' '}
            (≤15 chars) so you can tell them apart in adb.
          </p>
          <table className="release-worker-table">
            <thead>
              <tr>
                <th>Role</th>
                <th>Debug/profile isolate</th>
                <th>Release adb thread</th>
                <th>Log tags</th>
              </tr>
            </thead>
            <tbody>
              {RELEASE_WORKERS.map((w) => (
                <tr key={w.id}>
                  <td>{w.role}</td>
                  <td>
                    <code>{w.dartIsolateName}</code>
                  </td>
                  <td>
                    <code>{w.nativeThreadName}</code>
                  </td>
                  <td>
                    {w.logTags.map((tag) => (
                      <code key={tag} className="log-tag-chip">
                        {tag}
                      </code>
                    ))}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}

      <p className="backend-switch-note native-threads-note">
        {payload?.note ||
          'Names from /proc/.../comm are truncated to 15 characters on Android (e.g. flutter-worker-).'}
      </p>

      <div className="log-bookmarks" role="toolbar" aria-label="Thread filter bookmarks">
        {THREAD_FILTER_BOOKMARKS.map((bookmark) => (
          <button
            key={bookmark.id}
            type="button"
            className={`log-bookmark${activeBookmarkId === bookmark.id ? ' active' : ''}`}
            title={bookmark.title}
            onClick={() => applyBookmark(bookmark)}
          >
            {bookmark.label}
          </button>
        ))}
      </div>

      <form className="search-bar" onSubmit={runSearch}>
        <input
          type="text"
          placeholder="Filter threads (| for OR), e.g. flutter-worker"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value)
            setActiveBookmarkId('')
          }}
          autoComplete="off"
        />
        <label>
          <input
            type="checkbox"
            checked={caseSensitive}
            onChange={(e) => setCaseSensitive(e.target.checked)}
          />
          Case sensitive
        </label>
        <button type="submit" className="button">
          Search
        </button>
        <button type="button" className="button secondary" onClick={clearSearch}>
          Clear
        </button>
        <button
          type="button"
          className="button secondary"
          disabled={loading}
          onClick={() => {
            onFeedback('Refreshing native threads…')
            void refresh().then(() =>
              onFeedback('Native threads refreshed.', { isOk: true }),
            )
          }}
        >
          {loading ? '…' : 'Refresh'}
        </button>
      </form>

      <div className="isolates-table-wrap">
        <table>
          <thead>
            <tr>
              <th>TID</th>
              <th>Name</th>
              <th>PID</th>
            </tr>
          </thead>
          <tbody>
            {!payload?.ok ? (
              <tr>
                <td colSpan={3} className="log-placeholder">
                  {payload?.error || 'Waiting for app process…'}
                </td>
              </tr>
            ) : filtered.length === 0 ? (
              <tr>
                <td colSpan={3} className="log-placeholder">
                  {threads.length === 0
                    ? 'No threads found — is the release app running on device?'
                    : 'No threads match your search.'}
                </td>
              </tr>
            ) : (
              filtered.map((t: NativeThread) => {
                const name = t.name || '—'
                const hint = nativeThreadNameHint(name)
                const kind = workerKindLabel(name)
                const highlight = kind != null
                return (
                  <tr
                    key={`${t.tid}-${name}`}
                    className={
                      highlight
                        ? `thread-row-highlight thread-kind-${kind}`
                        : undefined
                    }
                  >
                    <td>{t.tid}</td>
                    <td title={hint ?? undefined}>
                      <span className="thread-name-cell">
                        <code>{name}</code>
                        {kind ? (
                          <span className={`thread-badge thread-badge-${kind}`}>
                            {kind}
                          </span>
                        ) : null}
                      </span>
                    </td>
                    <td>{t.pid || '—'}</td>
                  </tr>
                )
              })
            )}
          </tbody>
        </table>
      </div>
    </section>
  )
}
