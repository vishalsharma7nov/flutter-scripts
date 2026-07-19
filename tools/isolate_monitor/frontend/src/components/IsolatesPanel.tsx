import { useMemo, useState } from 'react'
import type { FormEvent } from 'react'
import type { IsolateInfo } from '../api/client'

interface IsolatesPanelProps {
  isolates: IsolateInfo[]
  hidden?: boolean
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
}

function isolateStatus(isolate: IsolateInfo): string {
  const kind = isolate.pauseEvent?.kind
  if (kind && kind !== 'Resume') return kind
  if (isolate.runnable === false) return 'not runnable'
  return 'Running'
}

export function IsolatesPanel({ isolates, hidden, onFeedback }: IsolatesPanelProps) {
  const [query, setQuery] = useState('')
  const [caseSensitive, setCaseSensitive] = useState(false)
  const [searchActive, setSearchActive] = useState(false)

  const filtered = useMemo(() => {
    if (!searchActive || !query.trim()) return isolates
    const needle = caseSensitive ? query.trim() : query.trim().toLowerCase()
    return isolates.filter((iso) => {
      const hay = [
        iso.id,
        iso.name,
        isolateStatus(iso),
        String(iso.number ?? ''),
        iso.isSystemIsolate ? 'system' : '',
      ]
        .filter(Boolean)
        .join(' ')
      return (caseSensitive ? hay : hay.toLowerCase()).includes(needle)
    })
  }, [isolates, query, caseSensitive, searchActive])

  function runSearch(event: FormEvent) {
    event.preventDefault()
    const trimmed = query.trim()
    if (!trimmed) {
      setSearchActive(false)
      onFeedback('Isolate search cleared.', { isOk: true })
      return
    }
    setSearchActive(true)
    onFeedback(`Filtering isolates for "${trimmed}"…`)
  }

  if (hidden) return null

  return (
    <section className="isolates-panel">
      <h2>Dart isolates</h2>
      <div className="isolates-search-meta">
        <span>
          {searchActive
            ? `${filtered.length} / ${isolates.length} isolates`
            : `${isolates.length} isolates`}
        </span>
        <span>
          {searchActive && query.trim()
            ? ` — ${filtered.length} match${filtered.length === 1 ? '' : 'es'} for "${query.trim()}"`
            : ''}
        </span>
      </div>
      <form className="search-bar" onSubmit={runSearch}>
        <input
          type="text"
          placeholder="Search isolates (main, running, paused…)"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
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
        <button
          type="button"
          className="button secondary"
          onClick={() => {
            setQuery('')
            setSearchActive(false)
            onFeedback('Isolate search cleared.', { isOk: true })
          }}
        >
          Clear
        </button>
      </form>
      <div className="isolates-table-wrap">
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Name</th>
              <th>Status</th>
              <th>Number</th>
              <th>System</th>
            </tr>
          </thead>
          <tbody>
            {filtered.length === 0 ? (
              <tr>
                <td colSpan={5} className="log-placeholder">
                  {isolates.length === 0
                    ? 'No isolates yet — waiting for VM…'
                    : 'No isolates match your search.'}
                </td>
              </tr>
            ) : (
              filtered.map((iso) => (
                <tr key={String(iso.id ?? iso.number ?? iso.name)}>
                  <td>{iso.id ?? '—'}</td>
                  <td>{iso.name ?? '—'}</td>
                  <td>{isolateStatus(iso)}</td>
                  <td>{iso.number ?? '—'}</td>
                  <td>{iso.isSystemIsolate ? 'yes' : 'no'}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </section>
  )
}
