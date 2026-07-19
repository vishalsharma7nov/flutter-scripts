import { useMemo, useRef, useState } from 'react'
import type { GuiStatus, ScriptItem } from '../api/client'
import { ScriptOptionsForm } from './ScriptOptionsForm'
import {
  ScriptWhenToUse,
  ScriptsWorkflowGuide,
  useWorkflowGuideOpen,
} from './ScriptsWorkflowGuide'
import {
  getFormForScript,
  type FormValues,
  type ScriptFormDef,
} from '../scriptForms'
import {
  SCRIPT_GUIDE,
  SCRIPT_WORKFLOWS,
  isRecommended,
  riskFor,
} from '../scriptWorkflows'
import { extraFor } from '../scriptMeta'
import { pushRecentScript, readRecentScripts } from '../prefs'
import type { GitDeepLink } from '../scriptMeta'

type SelectOption = { value: string; label: string }

type Props = {
  status: GuiStatus | null
  scripts: ScriptItem[]
  selected: ScriptItem | null
  filter: string
  args: string
  formValues: FormValues
  selectedForm: ScriptFormDef | null
  argsPreview: string
  busy: boolean
  error: string
  lines: string[]
  lastExitCode: number | null
  lastExitFile: string | null
  dynamicOptions: Record<string, SelectOption[]>
  onFilterChange: (v: string) => void
  onSelect: (s: ScriptItem) => void
  onFormChange: (v: FormValues) => void
  onExtraChange: (v: string) => void
  onArgsChange: (v: string) => void
  onRun: () => void
  onStop: () => void
  onClearLogs: () => void
  onChangeProject: () => void
  onOpenGit: (tab: 'howto' | 'troubleshoot', id: string) => void
  onWorkflowFilter?: (workflowId: string) => void
  moveSelection?: (delta: number) => void
  logsRef: React.RefObject<HTMLPreElement | null>
}

export function ScriptsWorkspace({
  status,
  scripts,
  selected,
  filter,
  args,
  formValues,
  selectedForm,
  argsPreview,
  busy,
  error,
  lines,
  lastExitCode,
  lastExitFile,
  dynamicOptions,
  onFilterChange,
  onSelect,
  onFormChange,
  onExtraChange,
  onArgsChange,
  onRun,
  onStop,
  onClearLogs,
  onChangeProject,
  onOpenGit,
  logsRef,
}: Props) {
  const listRef = useRef<HTMLDivElement | null>(null)
  const [workflowFilter, setWorkflowFilter] = useState<string>('all')
  const [guideOpen, setGuideOpen] = useWorkflowGuideOpen()
  const [recent, setRecent] = useState<string[]>(() => readRecentScripts())
  const [copiedLogs, setCopiedLogs] = useState(false)

  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase()
    return scripts.filter((s) => {
      if (workflowFilter !== 'all') {
        const meta = SCRIPT_GUIDE[s.file]
        if (!meta?.workflowIds.includes(workflowFilter)) return false
      }
      if (!q) return true
      return (
        s.label.toLowerCase().includes(q) ||
        s.file.toLowerCase().includes(q) ||
        s.description.toLowerCase().includes(q) ||
        String(s.index) === q ||
        (SCRIPT_GUIDE[s.file.split('/').pop() ?? s.file]?.when ?? '')
          .toLowerCase()
          .includes(q)
      )
    })
  }, [scripts, filter, workflowFilter])

  const recentScripts = useMemo(() => {
    return recent
      .map((file) => scripts.find((s) => s.file === file))
      .filter((s): s is ScriptItem => !!s)
      .slice(0, 5)
  }, [recent, scripts])

  const selectByFile = (file: string) => {
    const base = file.replace(/\\/g, '/').split('/').pop() || file
    const match =
      scripts.find((s) => s.file === file) ||
      scripts.find((s) => (s.file.split('/').pop() || s.file) === base)
    if (match) onSelect(match)
  }

  const moveLocal = (delta: number) => {
    if (filtered.length === 0) return
    const idx = selected
      ? filtered.findIndex((s) => s.file === selected.file)
      : -1
    const next = Math.max(
      0,
      Math.min(filtered.length - 1, (idx < 0 ? 0 : idx) + delta),
    )
    onSelect(filtered[next])
  }

  const handleRun = () => {
    if (guideOpen) setGuideOpen(false)
    if (selected) setRecent(pushRecentScript(selected.file))
    onRun()
  }

  const copyLogs = async () => {
    try {
      await navigator.clipboard.writeText(lines.join('\n'))
      setCopiedLogs(true)
      window.setTimeout(() => setCopiedLogs(false), 1500)
    } catch {
      setCopiedLogs(false)
    }
  }

  const failMeta =
    lastExitCode !== null &&
    lastExitCode !== 0 &&
    lastExitFile &&
    (!selected || selected.file === lastExitFile)
      ? extraFor(lastExitFile)
      : undefined

  return (
    <div className="page-scripts">
      <div className="project-chip-bar">
        <div className="project-chip">
          <span className="eyebrow">Active project</span>
          <strong title={status?.projectDir}>
            {status?.projectDir
              ? status.projectDir.split('/').filter(Boolean).slice(-1)[0]
              : '—'}
          </strong>
          <span className="file" title={status?.projectDir}>
            {status?.projectDir ?? ''}
          </span>
          {status?.isFlutterApp ? (
            <span className="pill flutter">Flutter app</span>
          ) : status?.isFlutter ? (
            <span className="pill flutter">Flutter</span>
          ) : (
            <span className="pill warn">Not Flutter</span>
          )}
        </div>
        <button type="button" onClick={onChangeProject}>
          ← Change project
        </button>
      </div>

      <ScriptsWorkflowGuide
        scripts={scripts}
        selectedFile={selected?.file ?? null}
        open={guideOpen}
        onOpenChange={setGuideOpen}
        onSelectFile={selectByFile}
      />

      <div className="main">
        <aside className="sidebar">
          {recentScripts.length > 0 ? (
            <div className="recent-row" aria-label="Recent scripts">
              <span className="eyebrow">Recent</span>
              <div className="recent-chips">
                {recentScripts.map((s) => (
                  <button
                    key={s.file}
                    type="button"
                    className={
                      selected?.file === s.file
                        ? 'recent-chip active'
                        : 'recent-chip'
                    }
                    onClick={() => onSelect(s)}
                    title={s.file}
                  >
                    {s.label}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
          <input
            className="filter"
            placeholder="Filter scripts…"
            value={filter}
            onChange={(e) => onFilterChange(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') {
                e.preventDefault()
                moveLocal(1)
              } else if (e.key === 'ArrowUp') {
                e.preventDefault()
                moveLocal(-1)
              } else if (e.key === 'Enter') {
                e.preventDefault()
                handleRun()
              }
            }}
          />
          <div
            className="workflow-chips"
            role="toolbar"
            aria-label="Filter by workflow"
          >
            <button
              type="button"
              className={
                workflowFilter === 'all'
                  ? 'workflow-chip active'
                  : 'workflow-chip'
              }
              onClick={() => setWorkflowFilter('all')}
            >
              All
            </button>
            {SCRIPT_WORKFLOWS.map((wf) => (
              <button
                key={wf.id}
                type="button"
                className={
                  workflowFilter === wf.id
                    ? 'workflow-chip active'
                    : 'workflow-chip'
                }
                onClick={() => setWorkflowFilter(wf.id)}
                title={wf.when}
              >
                {wf.chip}
              </button>
            ))}
          </div>
          <div className="list" ref={listRef} role="listbox">
            {filtered.map((s) => {
              const active = selected?.file === s.file
              const form = getFormForScript(s.file)
              const hasForm = !!form && form.fields.length > 0
              const risk = riskFor(s.file)
              const recommended = isRecommended(s.file)
              return (
                <button
                  key={s.file}
                  type="button"
                  role="option"
                  aria-selected={active}
                  className={`item${active ? ' active' : ''}`}
                  onClick={() => onSelect(s)}
                  onDoubleClick={() => {
                    onSelect(s)
                    handleRun()
                  }}
                >
                  <div className="item-top">
                    <span className="idx">{s.index})</span>
                    <span className="label">{s.label}</span>
                    {recommended ? (
                      <span className="pill rec-badge">Rec</span>
                    ) : null}
                    {risk ? (
                      <span
                        className={`pill ${
                          risk.level === 'danger'
                            ? 'danger-badge'
                            : 'caution-badge'
                        }`}
                        title={risk.message}
                      >
                        {risk.level === 'danger' ? 'Danger' : 'Caution'}
                      </span>
                    ) : null}
                    {hasForm ? (
                      <span className="pill form-badge">GUI</span>
                    ) : null}
                    <span className="file">{s.file}</span>
                  </div>
                  <div className="desc">{s.description}</div>
                </button>
              )
            })}
            {filtered.length === 0 && (
              <p className="empty">No scripts match.</p>
            )}
          </div>
        </aside>

        <section className="panel">
          <div className="run-bar">
            <div className="selected">
              {selected ? (
                <>
                  <strong>{selected.label}</strong>
                  <span className="file">{selected.file}</span>
                </>
              ) : (
                <span>Select a script</span>
              )}
            </div>

            {selected ? (
              <ScriptWhenToUse file={selected.file} onOpenGit={onOpenGit} />
            ) : null}

            {selectedForm ? (
              <ScriptOptionsForm
                def={selectedForm}
                values={formValues}
                extra={args}
                dynamicOptions={dynamicOptions}
                onChange={onFormChange}
                onExtraChange={onExtraChange}
                disabled={!selected || !!status?.running}
              />
            ) : (
              <input
                className="args"
                placeholder="Optional args (e.g. --aab --env prod)"
                value={args}
                onChange={(e) => onArgsChange(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault()
                    handleRun()
                  }
                }}
                disabled={!selected || !!status?.running}
              />
            )}

            {selected && argsPreview ? (
              <p className="args-preview dim">
                Will run:{' '}
                <code>
                  {selected.file} {argsPreview}
                </code>
              </p>
            ) : null}

            <div className="run-actions">
              <button
                type="button"
                className="primary"
                disabled={
                  !selected || !!status?.running || busy || !status?.isFlutter
                }
                onClick={handleRun}
                title={
                  status?.isFlutter
                    ? undefined
                    : 'Set a Flutter-compatible project first'
                }
              >
                Run
              </button>
              <button
                type="button"
                className="danger"
                disabled={!status?.running || busy}
                onClick={onStop}
              >
                Stop
              </button>
              <button
                type="button"
                onClick={onClearLogs}
                disabled={lines.length === 0}
              >
                Clear logs
              </button>
              <button
                type="button"
                onClick={() => void copyLogs()}
                disabled={lines.length === 0}
              >
                {copiedLogs ? 'Copied' : 'Copy logs'}
              </button>
            </div>
          </div>
          {error && <p className="error">{error}</p>}
          {failMeta?.onFail && lastExitCode !== null && lastExitCode !== 0 ? (
            <div className="fail-guide">
              <p>
                <strong>Exited {lastExitCode}. </strong>
                {failMeta.onFail.message}
              </p>
              <div className="fail-actions">
                {failMeta.onFail.workflowId ? (
                  <button
                    type="button"
                    onClick={() =>
                      setWorkflowFilter(failMeta.onFail!.workflowId!)
                    }
                  >
                    Filter workflow
                  </button>
                ) : null}
                {(failMeta.onFail.gitLinks as GitDeepLink[] | undefined)?.map(
                  (link) => (
                    <button
                      key={`${link.tab}-${link.id}`}
                      type="button"
                      onClick={() => onOpenGit(link.tab, link.id)}
                    >
                      Git: {link.label}
                    </button>
                  ),
                )}
              </div>
            </div>
          ) : null}
          <pre className="logs" ref={logsRef}>
            {lines.length === 0 ? (
              <span className="dim">
                Select a script, fill its options, then Run. Output appears
                here.
              </span>
            ) : (
              lines.map((line, i) => (
                <div key={`${i}-${line.slice(0, 24)}`}>{line}</div>
              ))
            )}
          </pre>
        </section>
      </div>
    </div>
  )
}
