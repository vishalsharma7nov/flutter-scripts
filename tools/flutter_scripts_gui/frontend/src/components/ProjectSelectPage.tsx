import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  fetchProjects,
  setProject,
  type GuiStatus,
  type NearbyProject,
} from '../api/client'

type Props = {
  status: GuiStatus | null
  busy: boolean
  lines: string[]
  onSelected: () => void
  onStatus: (s: GuiStatus) => void
  onError: (message: string) => void
  onLogLine: (line: string) => void
  logsRef: React.RefObject<HTMLPreElement | null>
}

export function ProjectSelectPage({
  status,
  busy,
  lines,
  onSelected,
  onStatus,
  onError,
  onLogLine,
  logsRef,
}: Props) {
  const [projects, setProjects] = useState<NearbyProject[]>([])
  const [filter, setFilter] = useState('')
  const [source, setSource] = useState('')
  const [loadingList, setLoadingList] = useState(false)
  const [working, setWorking] = useState(false)
  const [picked, setPicked] = useState<NearbyProject | null>(null)

  const refreshList = useCallback(async () => {
    setLoadingList(true)
    try {
      const data = await fetchProjects()
      setProjects(data.projects)
      const current = data.projects.find((p) => p.isCurrent) ?? null
      setPicked((prev) => prev ?? current)
      onError('')
    } catch (e) {
      onError(e instanceof Error ? e.message : String(e))
    } finally {
      setLoadingList(false)
    }
  }, [onError])

  useEffect(() => {
    void refreshList()
  }, [refreshList])

  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase()
    if (!q) return projects
    return projects.filter(
      (p) =>
        p.name.toLowerCase().includes(q) || p.path.toLowerCase().includes(q),
    )
  }, [projects, filter])

  const applySource = async (raw: string) => {
    const value = raw.trim()
    if (!value || busy || working) return
    setWorking(true)
    onError('')
    onLogLine(`Resolving project: ${value}`)
    try {
      const result = await setProject(value)
      onLogLine(`Active project: ${result.projectDir}`)
      const st = await fetch('/api/status').then((r) => r.json())
      onStatus(st)
      await refreshList()
      if (!result.isFlutter) {
        onError('Path set but Flutter check failed')
        return
      }
      onSelected()
    } catch (e) {
      onError(e instanceof Error ? e.message : String(e))
    } finally {
      setWorking(false)
    }
  }

  const continueWithCurrent = async () => {
    if (picked) {
      await applySource(picked.path)
      return
    }
    if (status?.isFlutter && status.projectDir) {
      onSelected()
      return
    }
    onError('Select a Flutter project first')
  }

  return (
    <div className="page-project">
      <section className="project-hero">
        <p className="eyebrow">Page 1 · Project</p>
        <h2>Select a Flutter project</h2>
        <p className="hero-copy">
          Choose a local app, or paste a path / git URL. Scripts run against this
          project on the next screen.
        </p>
      </section>

      <div className="project-paste-row">
        <input
          className="project-input"
          placeholder="Paste git URL, owner/repo, or local Flutter path…"
          value={source}
          onChange={(e) => setSource(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              void applySource(source)
            }
          }}
          disabled={busy || working}
        />
        <button
          type="button"
          className="primary"
          disabled={!source.trim() || busy || working}
          onClick={() => void applySource(source)}
        >
          {working ? 'Working…' : 'Use path / clone'}
        </button>
      </div>

      <div className="project-select-panel">
        <div className="project-select-toolbar">
          <input
            className="filter"
            placeholder="Filter discovered projects…"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            disabled={loadingList}
          />
          <button
            type="button"
            onClick={() => void refreshList()}
            disabled={loadingList || working}
          >
            {loadingList ? 'Scanning…' : 'Rescan'}
          </button>
        </div>

        <div className="project-list" role="listbox">
          {filtered.map((p) => {
            const active = picked?.path === p.path
            return (
              <button
                key={p.path}
                type="button"
                role="option"
                aria-selected={active}
                className={`item${active ? ' active' : ''}`}
                onClick={() => setPicked(p)}
                onDoubleClick={() => void applySource(p.path)}
              >
                <div className="item-top">
                  <span className="label">{p.name}</span>
                  {p.isFlutterApp ? (
                    <span className="pill flutter">app</span>
                  ) : (
                    <span className="pill">package</span>
                  )}
                  {p.isCurrent ? (
                    <span className="pill form-badge">current</span>
                  ) : null}
                </div>
                <div className="desc">{p.path}</div>
              </button>
            )
          })}
          {filtered.length === 0 && (
            <p className="empty">
              {loadingList
                ? 'Scanning ~/StudioProjects…'
                : 'No Flutter projects found. Paste a path or git URL above.'}
            </p>
          )}
        </div>
      </div>

      <div className="project-continue">
        <div className="selected">
          {picked ? (
            <>
              <strong>{picked.name}</strong>
              <span className="file">{picked.path}</span>
            </>
          ) : status?.projectDir ? (
            <>
              <strong>Current</strong>
              <span className="file">{status.projectDir}</span>
            </>
          ) : (
            <span className="dim">No project selected yet</span>
          )}
        </div>
        <div className="project-continue-actions">
          <p className="project-next-hint dim">
            Next: on Scripts, open the workflow guide or use chips (Debug /
            Build / …) to pick what to run.
          </p>
          <button
            type="button"
            className="primary"
            disabled={working || busy || (!picked && !status?.isFlutter)}
            onClick={() => void continueWithCurrent()}
          >
            Continue to scripts →
          </button>
        </div>
      </div>

      {(lines.length > 0 || working) && (
        <pre className="logs project-logs" ref={logsRef}>
          {lines.length === 0 ? (
            <span className="dim">Clone / resolve output…</span>
          ) : (
            lines.map((line, i) => (
              <div key={`${i}-${line.slice(0, 24)}`}>{line}</div>
            ))
          )}
        </pre>
      )}
    </div>
  )
}
