import { useEffect, useState } from 'react'
import type { ScriptItem } from '../api/client'
import {
  SCRIPT_WORKFLOWS,
  isRecommended,
  readGuideOpen,
  resolveScript,
  riskFor,
  type ScriptWorkflow,
  writeGuideOpen,
  SCRIPT_GUIDE,
} from '../scriptWorkflows'
import { extraFor } from '../scriptMeta'

type Props = {
  scripts: ScriptItem[]
  selectedFile: string | null
  open: boolean
  onOpenChange: (open: boolean) => void
  onSelectFile: (file: string) => void
}

export function ScriptsWorkflowGuide({
  scripts,
  selectedFile,
  open,
  onOpenChange,
  onSelectFile,
}: Props) {
  const [activeId, setActiveId] = useState<string>(SCRIPT_WORKFLOWS[0]?.id ?? '')

  const active: ScriptWorkflow | undefined =
    SCRIPT_WORKFLOWS.find((w) => w.id === activeId) ?? SCRIPT_WORKFLOWS[0]

  return (
    <section className="workflow-guide" aria-label="Script workflows">
      <div className="workflow-guide-top">
        <div>
          <p className="eyebrow">Workflow</p>
          <h2>What to use when</h2>
          <p className="hero-copy">
            Pick a situation below, then choose the matching script. Click a
            step to select it in the list and run it on the right.
          </p>
        </div>
        <button
          type="button"
          onClick={() => onOpenChange(!open)}
          aria-expanded={open}
        >
          {open ? 'Hide guide' : 'Show guide'}
        </button>
      </div>

      {open && active ? (
        <div className="workflow-body">
          <div className="workflow-tabs" role="tablist" aria-label="Workflows">
            {SCRIPT_WORKFLOWS.map((wf) => (
              <button
                key={wf.id}
                type="button"
                role="tab"
                aria-selected={wf.id === active.id}
                className={
                  wf.id === active.id ? 'workflow-tab active' : 'workflow-tab'
                }
                onClick={() => setActiveId(wf.id)}
              >
                {wf.title}
              </button>
            ))}
          </div>

          <div className="workflow-panel">
            <p className="workflow-when">
              <strong>When: </strong>
              {active.when}
            </p>
            <p className="dim">{active.summary}</p>
            <ol className="workflow-steps">
              {active.steps.map((step, i) => {
                const script = resolveScript(scripts, step.file)
                const selected = script != null && selectedFile === script.file
                const known = !!script
                const risk = riskFor(step.file)
                return (
                  <li key={step.file}>
                    <button
                      type="button"
                      className={`workflow-step${selected ? ' active' : ''}${
                        known ? '' : ' missing'
                      }`}
                      disabled={!known}
                      onClick={() => known && onSelectFile(step.file)}
                      title={
                        known
                          ? `Select ${script.label}`
                          : 'Script not in catalog on this machine'
                      }
                    >
                      <span className="workflow-step-idx">{i + 1}</span>
                      <span className="workflow-step-body">
                        <span className="workflow-step-title">
                          {script?.label ?? step.file}
                          {step.recommended ? (
                            <span className="pill rec-badge">Recommended</span>
                          ) : null}
                          {risk ? (
                            <span
                              className={`pill ${
                                risk.level === 'danger'
                                  ? 'danger-badge'
                                  : 'caution-badge'
                              }`}
                            >
                              {risk.level === 'danger' ? 'Destructive' : 'Caution'}
                            </span>
                          ) : null}
                          <span className="file">{script?.file ?? step.file}</span>
                        </span>
                        <span className="workflow-step-when">{step.when}</span>
                        {step.tip ? (
                          <span className="workflow-step-tip">{step.tip}</span>
                        ) : null}
                      </span>
                    </button>
                  </li>
                )
              })}
            </ol>
          </div>
        </div>
      ) : null}
    </section>
  )
}

type MetaProps = {
  file: string
  onOpenGit?: (tab: 'howto' | 'troubleshoot', id: string) => void
}

/** Compact “when to use” blurb for the selected script run panel. */
export function ScriptWhenToUse({ file, onOpenGit }: MetaProps) {
  const meta = SCRIPT_GUIDE[file]
  const risk = riskFor(file)
  const extra = extraFor(file)
  if (!meta && !risk && !extra) return null
  return (
    <div className="script-when">
      {meta ? (
        <>
          <p className="eyebrow">
            {meta.category}
            {isRecommended(file) ? ' · Recommended' : ''}
          </p>
          <p>
            <strong>When to use: </strong>
            {meta.when}
          </p>
          {meta.tip ? <p className="dim">{meta.tip}</p> : null}
        </>
      ) : null}
      {extra?.help ? (
        <p className="script-help">
          <strong>Flags: </strong>
          {extra.help}
        </p>
      ) : null}
      {risk ? (
        <p className={risk.level === 'danger' ? 'risk-danger' : 'risk-caution'}>
          <strong>
            {risk.level === 'danger' ? 'Destructive: ' : 'Caution: '}
          </strong>
          {risk.message}
        </p>
      ) : null}
      {extra?.gitLinks?.length && onOpenGit ? (
        <div className="git-links">
          {extra.gitLinks.map((link) => (
            <button
              key={`${link.tab}-${link.id}`}
              type="button"
              className="linkish"
              onClick={() => onOpenGit(link.tab, link.id)}
            >
              Open Git tool → {link.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  )
}

/** Hook: guide open state with localStorage (default collapsed). */
export function useWorkflowGuideOpen() {
  const [open, setOpen] = useState(false)

  useEffect(() => {
    setOpen(readGuideOpen())
  }, [])

  function setGuideOpen(next: boolean) {
    setOpen(next)
    writeGuideOpen(next)
  }

  return [open, setGuideOpen] as const
}
