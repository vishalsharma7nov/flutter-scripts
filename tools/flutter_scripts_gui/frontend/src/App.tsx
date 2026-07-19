import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  fetchReleasePackages,
  fetchScripts,
  fetchStatus,
  openLogStream,
  runScript,
  stopScript,
  type GuiStatus,
  type LogEvent,
  type ReleasePackage,
  type ScriptItem,
} from './api/client'
import { ProjectSelectPage } from './components/ProjectSelectPage'
import { ScriptsWorkspace } from './components/ScriptsWorkspace'
import { ShortcutsHelp } from './components/ShortcutsHelp'
import { LocalizationPanel } from './components/LocalizationPanel'
import {
  GitToolPanel,
  type GitDeepLinkTarget,
} from './git-tool/GitToolPanel'
import {
  buildArgsFromForm,
  defaultValuesFor,
  getFormForScript,
  isFieldVisible,
  type FormValues,
} from './scriptForms'
import {
  readDensity,
  writeDensity,
  type Density,
} from './prefs'

type AppPage = 'project' | 'scripts' | 'git' | 'l10n'

function parseArgs(raw: string): string[] {
  const trimmed = raw.trim()
  if (!trimmed) return []
  const out: string[] = []
  const re = /"([^"]*)"|'([^']*)'|(\S+)/g
  let m: RegExpExecArray | null
  while ((m = re.exec(trimmed)) !== null) {
    out.push(m[1] ?? m[2] ?? m[3] ?? '')
  }
  return out
}

export default function App() {
  const [page, setPage] = useState<AppPage>('project')
  const [status, setStatus] = useState<GuiStatus | null>(null)
  const [scripts, setScripts] = useState<ScriptItem[]>([])
  const [filter, setFilter] = useState('')
  const [selected, setSelected] = useState<ScriptItem | null>(null)
  const [args, setArgs] = useState('')
  const [formValues, setFormValues] = useState<FormValues>({})
  const [lines, setLines] = useState<string[]>([])
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [releasePackages, setReleasePackages] = useState<ReleasePackage[]>([])
  const [lastExitCode, setLastExitCode] = useState<number | null>(null)
  const [lastExitFile, setLastExitFile] = useState<string | null>(null)
  const [gitDeepLink, setGitDeepLink] = useState<GitDeepLinkTarget | null>(
    null,
  )
  const [shortcutsOpen, setShortcutsOpen] = useState(false)
  const [density, setDensity] = useState<Density>(() => readDensity())
  const logsRef = useRef<HTMLPreElement | null>(null)
  const pageRef = useRef(page)
  pageRef.current = page

  const selectedForm = useMemo(
    () => (selected ? getFormForScript(selected.file) : null),
    [selected],
  )

  const builtArgs = useMemo(() => {
    if (selectedForm) {
      return buildArgsFromForm(selectedForm, formValues, args)
    }
    return parseArgs(args)
  }, [selectedForm, formValues, args])

  const argsPreview = useMemo(() => builtArgs.join(' '), [builtArgs])

  const refresh = useCallback(async () => {
    try {
      const [st, list, packages] = await Promise.all([
        fetchStatus(),
        fetchScripts(),
        fetchReleasePackages(),
      ])
      setStatus(st)
      setScripts(list)
      setReleasePackages(packages)
      setError('')
      setSelected((prev) => {
        if (prev && list.some((s) => s.file === prev.file)) {
          return list.find((s) => s.file === prev.file) ?? prev
        }
        return list[0] ?? null
      })
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    }
  }, [])

  useEffect(() => {
    void refresh()
  }, [refresh])

  useEffect(() => {
    document.documentElement.dataset.density = density
    writeDensity(density)
  }, [density])

  useEffect(() => {
    if (!selected) {
      setFormValues({})
      return
    }
    const def = getFormForScript(selected.file)
    setFormValues(def ? defaultValuesFor(def) : {})
    setArgs('')
  }, [selected?.file])

  useEffect(() => {
    if (!selectedForm || releasePackages.length === 0) return
    const needsPackage = selectedForm.fields.some((f) => f.id === 'package')
    if (!needsPackage) return
    setFormValues((prev) => {
      if (String(prev.package ?? '').trim()) return prev
      return { ...prev, package: releasePackages[0]?.id ?? '' }
    })
  }, [selectedForm, releasePackages])

  useEffect(() => {
    const es = openLogStream((ev: LogEvent) => {
      if (ev.type === 'started') {
        setLastExitCode(null)
        setLastExitFile(ev.file ?? null)
      }
      if (ev.type === 'exited') {
        setLastExitCode(typeof ev.code === 'number' ? ev.code : null)
        if (ev.file) setLastExitFile(ev.file)
      }
      const text =
        ev.line ??
        (ev.type === 'exited' ? `exited code=${ev.code ?? '?'}` : ev.type)
      setLines((prev) => [...prev.slice(-2000), text])
      if (ev.type === 'started' || ev.type === 'exited') {
        void fetchStatus().then(setStatus).catch(() => undefined)
      }
    })
    return () => es.close()
  }, [])

  useEffect(() => {
    const el = logsRef.current
    if (!el) return
    el.scrollTop = el.scrollHeight
  }, [lines])

  const onStop = useCallback(async () => {
    setBusy(true)
    setError('')
    try {
      await stopScript()
      await refresh()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }, [refresh])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null
      const typing =
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      if (e.key === '?' && !typing && !e.metaKey && !e.ctrlKey) {
        e.preventDefault()
        setShortcutsOpen((v) => !v)
        return
      }
      if (e.key === 'Escape') {
        if (shortcutsOpen) {
          setShortcutsOpen(false)
          return
        }
        if (pageRef.current === 'scripts' && status?.running) {
          e.preventDefault()
          void onStop()
        }
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onStop, shortcutsOpen, status?.running])

  const filteredScripts = useMemo(() => {
    const q = filter.trim().toLowerCase()
    if (!q) return scripts
    return scripts.filter(
      (s) =>
        s.label.toLowerCase().includes(q) ||
        s.file.toLowerCase().includes(q) ||
        s.description.toLowerCase().includes(q) ||
        String(s.index) === q,
    )
  }, [scripts, filter])

  const dynamicOptions = useMemo(
    () => ({
      'release-packages': releasePackages.map((p) => ({
        value: p.id,
        label: `${p.id} — ${p.title}`,
      })),
    }),
    [releasePackages],
  )

  const onRun = async () => {
    if (!selected || status?.running) return
    if (selectedForm) {
      for (const field of selectedForm.fields) {
        if (!isFieldVisible(field, formValues)) continue
        if (
          field.required &&
          field.type !== 'checkbox' &&
          !String(formValues[field.id] ?? '').trim()
        ) {
          setError(`Missing required: ${field.label}`)
          return
        }
      }
    }
    setBusy(true)
    setError('')
    try {
      await runScript(selected.file, builtArgs)
      await refresh()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const moveSelection = (delta: number) => {
    if (filteredScripts.length === 0) return
    const idx = selected
      ? filteredScripts.findIndex((s) => s.file === selected.file)
      : -1
    const next = Math.max(
      0,
      Math.min(filteredScripts.length - 1, (idx < 0 ? 0 : idx) + delta),
    )
    setSelected(filteredScripts[next])
  }

  const openGit = useCallback((tab: 'howto' | 'troubleshoot', id: string) => {
    setGitDeepLink({ tab, id })
    setPage('git')
  }, [])

  const clearDeepLink = useCallback(() => setGitDeepLink(null), [])

  const toggleDensity = () => {
    setDensity((d) => (d === 'compact' ? 'comfortable' : 'compact'))
  }

  return (
    <div className={`app density-${density}`}>
      <header className="header">
        <div className="header-top">
          <div>
            <h1>Flutter Scripts</h1>
            <p className="meta dim" title={status?.scriptsDir}>
              scripts: {status?.scriptsDir ?? '…'}
            </p>
          </div>
          <div className="header-actions">
            {status?.running ? (
              <span className="pill running">running {status.runningFile}</span>
            ) : (
              <span className="pill idle">idle</span>
            )}
            <button
              type="button"
              onClick={toggleDensity}
              title="Toggle compact layout"
            >
              {density === 'compact' ? 'Comfortable' : 'Compact'}
            </button>
            <button
              type="button"
              onClick={() => setShortcutsOpen(true)}
              title="Keyboard shortcuts (?)"
            >
              ?
            </button>
            <button type="button" onClick={() => void refresh()} disabled={busy}>
              Refresh
            </button>
          </div>
        </div>
        <nav className="view-tabs" aria-label="Pages">
          <button
            type="button"
            className={page === 'project' ? 'view-tab active' : 'view-tab'}
            onClick={() => setPage('project')}
          >
            1 · Project
          </button>
          <button
            type="button"
            className={page === 'scripts' ? 'view-tab active' : 'view-tab'}
            onClick={() => setPage('scripts')}
            disabled={!status?.isFlutter}
            title={
              status?.isFlutter
                ? undefined
                : 'Select a Flutter project on page 1 first'
            }
          >
            2 · Scripts
          </button>
          <button
            type="button"
            className={page === 'git' ? 'view-tab active' : 'view-tab'}
            onClick={() => setPage('git')}
          >
            3 · Git LLM
          </button>
          <button
            type="button"
            className={page === 'l10n' ? 'view-tab active' : 'view-tab'}
            onClick={() => setPage('l10n')}
            disabled={!status?.isFlutter}
            title={
              status?.isFlutter
                ? undefined
                : 'Select a Flutter project on page 1 first'
            }
          >
            4 · Localization
          </button>
        </nav>
      </header>

      {error && page !== 'scripts' ? <p className="error">{error}</p> : null}

      {page === 'project' ? (
        <ProjectSelectPage
          status={status}
          busy={busy || !!status?.running}
          lines={lines}
          logsRef={logsRef}
          onSelected={() => {
            setPage('scripts')
            void refresh()
          }}
          onStatus={setStatus}
          onError={setError}
          onLogLine={(line) => setLines((prev) => [...prev.slice(-2000), line])}
        />
      ) : null}

      {page === 'scripts' ? (
        <ScriptsWorkspace
          status={status}
          scripts={scripts}
          selected={selected}
          filter={filter}
          args={args}
          formValues={formValues}
          selectedForm={selectedForm}
          argsPreview={argsPreview}
          busy={busy}
          error={error}
          lines={lines}
          lastExitCode={lastExitCode}
          lastExitFile={lastExitFile}
          dynamicOptions={dynamicOptions}
          onFilterChange={setFilter}
          onSelect={setSelected}
          onFormChange={setFormValues}
          onExtraChange={setArgs}
          onArgsChange={setArgs}
          onRun={() => void onRun()}
          onStop={() => void onStop()}
          onClearLogs={() => setLines([])}
          onChangeProject={() => setPage('project')}
          onOpenGit={openGit}
          moveSelection={moveSelection}
          logsRef={logsRef}
        />
      ) : null}

      {page === 'git' ? (
        <GitToolPanel
          deepLink={gitDeepLink}
          onDeepLinkConsumed={clearDeepLink}
          projectDir={status?.projectDir}
          onProjectChanged={() => void refresh()}
        />
      ) : null}

      {page === 'l10n' ? (
        <LocalizationPanel
          projectDir={status?.projectDir}
          isFlutter={!!status?.isFlutter}
          onChangeProject={() => setPage('project')}
        />
      ) : null}

      <ShortcutsHelp
        open={shortcutsOpen}
        onClose={() => setShortcutsOpen(false)}
      />
    </div>
  )
}
