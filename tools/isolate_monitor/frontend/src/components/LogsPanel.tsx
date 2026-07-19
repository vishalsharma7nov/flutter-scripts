import { useEffect, useMemo, useRef, useState } from 'react'
import type { FormEvent } from 'react'
import {
  DEVICE_LOG_BOOKMARKS,
  DEFAULT_RELEASE_DEVICE_BOOKMARK,
  LOG_WINDOW_LOAD_CHUNK,
  MAX_DOM_LOG_LINES,
  computeLogWindow,
  filterLinesWithIndices,
  formatFileOpenerLabel,
  type LogFilterBookmark,
} from '../lib/logUtils'
import { LogLineView } from './LogLineView'

interface LogsPanelProps {
  title: string
  className?: string
  lines: string[]
  canOpenFiles: boolean
  fileOpenerName: string
  editorHint?: string
  sessionHint?: string
  showLegend?: boolean
  /** Show quick filter bookmarks (device logs). */
  showBookmarks?: boolean
  /** When true, auto-select Trip stream filter (Android release). */
  preferTripStreamFilter?: boolean
  emptyMessage: string
  onOpenFile: (reference: string) => void
  onErrorTagTap: (lineIndex: number, sessionLines: string[]) => void
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
}

export function LogsPanel({
  title,
  className = '',
  lines,
  canOpenFiles,
  fileOpenerName,
  editorHint = '',
  sessionHint,
  showLegend = false,
  showBookmarks = false,
  preferTripStreamFilter = false,
  emptyMessage,
  onOpenFile,
  onErrorTagTap,
  onFeedback,
}: LogsPanelProps) {
  const initialBookmark = preferTripStreamFilter
    ? DEVICE_LOG_BOOKMARKS.find((b) => b.id === DEFAULT_RELEASE_DEVICE_BOOKMARK)
    : null
  const [query, setQuery] = useState(initialBookmark?.query ?? '')
  const [caseSensitive, setCaseSensitive] = useState(false)
  const [searchActive, setSearchActive] = useState(!!initialBookmark?.query)
  const [activeBookmarkId, setActiveBookmarkId] = useState(
    initialBookmark?.id ?? (preferTripStreamFilter ? DEFAULT_RELEASE_DEVICE_BOOKMARK : 'all'),
  )
  const [windowStart, setWindowStart] = useState(0)
  const [followTail, setFollowTail] = useState(true)
  const [showScrollHint, setShowScrollHint] = useState(false)
  const viewRef = useRef<HTMLDivElement>(null)
  const didAutoTrip = useRef(false)

  useEffect(() => {
    if (!preferTripStreamFilter || didAutoTrip.current) return
    const bookmark = DEVICE_LOG_BOOKMARKS.find(
      (b) => b.id === DEFAULT_RELEASE_DEVICE_BOOKMARK,
    )
    if (!bookmark) return
    didAutoTrip.current = true
    setActiveBookmarkId(bookmark.id)
    setQuery(bookmark.query)
    setSearchActive(true)
    setFollowTail(true)
  }, [preferTripStreamFilter])

  const filtered = useMemo(() => {
    if (!searchActive || !query.trim()) {
      return lines.map((line, index) => ({ line, index }))
    }
    return filterLinesWithIndices(lines, query, caseSensitive)
  }, [lines, query, caseSensitive, searchActive])

  const filteredLines = filtered.map((e) => e.line)
  const filteredIndices = filtered.map((e) => e.index)

  const windowed = useMemo(() => {
    const preferTail = followTail && (!searchActive || preferTripStreamFilter)
    const result = computeLogWindow(filteredLines, windowStart, preferTail)
    return {
      ...result,
      indices: result.visibleLines.map((_, i) => {
        const start = result.windowStart
        return filteredIndices[start + i] ?? start + i
      }),
    }
  }, [filteredLines, filteredIndices, windowStart, followTail, searchActive, preferTripStreamFilter])

  useEffect(() => {
    if (followTail && viewRef.current && !searchActive) {
      viewRef.current.scrollTop = viewRef.current.scrollHeight
      setShowScrollHint(false)
    }
  }, [lines.length, followTail, searchActive, windowed.visibleLines.length])

  useEffect(() => {
    // Keep following tail while a release trip-stream filter is active.
    if (followTail && viewRef.current && searchActive && preferTripStreamFilter) {
      viewRef.current.scrollTop = viewRef.current.scrollHeight
    }
  }, [lines.length, followTail, searchActive, preferTripStreamFilter, windowed.visibleLines.length])

  useEffect(() => {
    setWindowStart(windowed.windowStart)
  }, [windowed.windowStart])

  function applyBookmark(bookmark: LogFilterBookmark) {
    setActiveBookmarkId(bookmark.id)
    setQuery(bookmark.query)
    if (!bookmark.query.trim()) {
      setSearchActive(false)
      setFollowTail(true)
      onFeedback('Showing all device logs.', { isOk: true })
      return
    }
    setSearchActive(true)
    setFollowTail(true)
    setShowScrollHint(false)
    setWindowStart(0)
    onFeedback(`Filter: ${bookmark.label} (${bookmark.query})`)
  }

  function runSearch(event?: FormEvent) {
    event?.preventDefault()
    const trimmed = query.trim()
    if (!trimmed) {
      setSearchActive(false)
      setActiveBookmarkId('all')
      setFollowTail(true)
      onFeedback('Log search cleared.', { isOk: true })
      return
    }
    const match = DEVICE_LOG_BOOKMARKS.find(
      (b) => b.query.trim().toLowerCase() === trimmed.toLowerCase(),
    )
    setActiveBookmarkId(match?.id ?? '')
    setSearchActive(true)
    setFollowTail(false)
    setShowScrollHint(false)
    setWindowStart(0)
    onFeedback(`Filtering logs for "${trimmed}"…`)
  }

  function clearSearch() {
    setQuery('')
    setSearchActive(false)
    setActiveBookmarkId('all')
    setFollowTail(true)
    onFeedback('Log search cleared.', { isOk: true })
  }

  function jumpToLatest() {
    if (searchActive && !preferTripStreamFilter) {
      clearSearch()
      return
    }
    setFollowTail(true)
    setShowScrollHint(false)
    if (viewRef.current) {
      viewRef.current.scrollTop = viewRef.current.scrollHeight
    }
    onFeedback('Jumped to latest logs.', { isOk: true })
  }

  function onScroll() {
    const el = viewRef.current
    if (!el) return
    const atBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 8
    setFollowTail(atBottom)
    if (!atBottom && lines.length > 0) {
      setShowScrollHint(true)
    } else {
      setShowScrollHint(false)
    }

    if (
      filteredLines.length > MAX_DOM_LOG_LINES &&
      el.scrollTop <= 72 &&
      windowStart > 0
    ) {
      setWindowStart((start) => Math.max(0, start - LOG_WINDOW_LOAD_CHUNK))
    }
  }

  const hint = canOpenFiles
    ? ` — tap ERROR/FATAL/ASSERT or a file:line link to open in ${formatFileOpenerLabel(fileOpenerName)}`
    : editorHint

  const filterLabel =
    searchActive && query.trim()
      ? ` — ${filtered.length} match${filtered.length === 1 ? '' : 'es'} for "${query.trim()}"`
      : ''

  return (
    <section className={`logs-panel ${className}`.trim()}>
      <h2>{title}</h2>
      <div className="search-meta">
        {sessionHint ? <span className="session-hint">{sessionHint}</span> : null}
        <span>
          {lines.length} line{lines.length === 1 ? '' : 's'}
        </span>
        <span>{filterLabel}</span>
        <span>{hint}</span>
      </div>
      {showBookmarks ? (
        <div className="log-bookmarks" role="toolbar" aria-label="Log filter bookmarks">
          {DEVICE_LOG_BOOKMARKS.map((bookmark) => (
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
      ) : null}
      <form className="search-bar" onSubmit={runSearch}>
        <input
          type="text"
          placeholder={
            className.includes('flutter')
              ? 'Search flutter run output…'
              : 'Filter (use | for OR), e.g. TripStreamWorker|flutter'
          }
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
        <button type="submit" className="button" disabled={!query.trim() && !searchActive}>
          Search
        </button>
        <button type="button" className="button secondary" onClick={clearSearch}>
          Clear
        </button>
      </form>
      {showLegend ? (
        <div className="log-legend" aria-hidden="true">
          <span className="log-verbose">Verbose</span>
          <span className="log-debug">Debug</span>
          <span className="log-info">Info</span>
          <span className="log-warning">Warn</span>
          <span className="log-error">Error</span>
          <span className="log-fatal">Fatal</span>
        </div>
      ) : null}
      {showScrollHint ? (
        <div className="scroll-hint" onClick={jumpToLatest}>
          New output below.
          <button type="button" onClick={(e) => { e.stopPropagation(); jumpToLatest() }}>
            Jump to latest
          </button>
        </div>
      ) : null}
      <div className="log-view" ref={viewRef} onScroll={onScroll}>
        {windowed.windowStart > 0 && filteredLines.length > windowed.visibleLines.length ? (
          <div className="log-window-banner">
            {`Showing lines ${(windowed.windowStart + 1).toLocaleString()}–${(
              windowed.windowStart + windowed.visibleLines.length
            ).toLocaleString()} of ${filteredLines.length.toLocaleString()}. Scroll up for older lines or use Search.`}
          </div>
        ) : null}
        {windowed.visibleLines.length === 0 ? (
          <div className="log-line log-placeholder">{emptyMessage}</div>
        ) : (
          windowed.visibleLines.map((line, i) => (
            <LogLineView
              key={`${windowed.indices[i]}-${line.slice(0, 40)}`}
              line={line}
              lineIndex={windowed.indices[i]}
              query={searchActive ? query : ''}
              caseSensitive={caseSensitive}
              canOpenFiles={canOpenFiles}
              fileOpenerName={fileOpenerName}
              onOpenFile={onOpenFile}
              onErrorTagTap={(idx) => onErrorTagTap(idx, lines)}
            />
          ))
        )}
      </div>
    </section>
  )
}
