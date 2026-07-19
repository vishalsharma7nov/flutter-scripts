import { useMemo, useState } from 'react'
import {
  applyLocalization,
  checkLocalization,
  type LocalizationCheckResult,
  type LocalizationSuggestion,
} from '../api/client'

type Step = 1 | 2 | 3 | 4

type Props = {
  projectDir?: string
  isFlutter?: boolean
  onChangeProject: () => void
}

function toastCopy(text: string) {
  void navigator.clipboard.writeText(text).then(
    () => undefined,
    () => undefined,
  )
}

function SuggestionCard({
  item,
  templateArb,
}: {
  item: LocalizationSuggestion
  templateArb: string
}) {
  return (
    <article className="l10n-card">
      <header className="l10n-card-head">
        <span className={`l10n-chip ${item.kind === 'hardcoded' ? 'warn' : 'danger'}`}>
          {item.kind}
        </span>
        <code className="l10n-key">l10n.{item.suggestedKey}</code>
      </header>
      <p className="l10n-path">
        {item.relative}
        {item.line != null ? `:${item.line}` : ''}
        {item.text ? (
          <>
            {' '}
            — <em>&quot;{item.text}&quot;</em>
          </>
        ) : null}
      </p>
      <ol className="l10n-steps">
        {item.steps.map((s) => (
          <li key={s}>{s}</li>
        ))}
      </ol>
      <div className="l10n-code-grid">
        <div>
          <div className="l10n-code-label">
            {templateArb || 'template.arb'}
            <button type="button" className="ghost" onClick={() => toastCopy(item.arbEn)}>
              Copy
            </button>
          </div>
          <pre>{item.arbEn}</pre>
        </div>
        <div>
          <div className="l10n-code-label">
            Dart
            <button type="button" className="ghost" onClick={() => toastCopy(item.dartAfter)}>
              Copy
            </button>
          </div>
          <pre>
            {item.dartBefore ? `- ${item.dartBefore}\n` : ''}
            {`+ ${item.dartAfter}`}
          </pre>
        </div>
      </div>
    </article>
  )
}

export function LocalizationPanel({
  projectDir,
  isFlutter,
  onChangeProject,
}: Props) {
  const [step, setStep] = useState<Step>(1)
  const [pathFilter, setPathFilter] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [hardcodedResult, setHardcodedResult] =
    useState<LocalizationCheckResult | null>(null)
  const [fullResult, setFullResult] = useState<LocalizationCheckResult | null>(
    null,
  )
  const [suggestionsResult, setSuggestionsResult] =
    useState<LocalizationCheckResult | null>(null)
  const [applyResult, setApplyResult] = useState<LocalizationCheckResult | null>(
    null,
  )

  const paths = useMemo(
    () =>
      pathFilter
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean),
    [pathFilter],
  )

  const run = async (mode: 'hardcoded' | 'full' | 'suggestions') => {
    if (!isFlutter) {
      setError('Select a Flutter project on the Project tab first.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const data = await checkLocalization(mode, paths)
      if (mode === 'hardcoded') {
        setHardcodedResult(data)
        setStep(1)
      } else if (mode === 'full') {
        setFullResult(data)
        setStep(2)
      } else {
        setSuggestionsResult(data)
        setStep(3)
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const runAll = async () => {
    if (!isFlutter) {
      setError('Select a Flutter project on the Project tab first.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const [h, f, s] = await Promise.all([
        checkLocalization('hardcoded', paths),
        checkLocalization('full', paths),
        checkLocalization('suggestions', paths),
      ])
      setHardcodedResult(h)
      setFullResult(f)
      setSuggestionsResult(s)
      setStep(1)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const applyAll = async () => {
    if (!isFlutter) {
      setError('Select a Flutter project on the Project tab first.')
      return
    }
    setBusy(true)
    setError('')
    try {
      const data = await applyLocalization(paths)
      setApplyResult(data)
      setSuggestionsResult(data)
      setFullResult(data)
      setStep(4)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const hardcoded = hardcodedResult?.hardcoded ?? []
  const hardIssues = fullResult?.hard_issues ?? []
  const missing = fullResult?.missing_keys ?? []
  const suggestions = suggestionsResult?.suggestions ?? []
  const applied = applyResult?.apply_result
  const genL10n = applyResult?.l10n_result
  const analysis = applyResult?.analysis_result

  return (
    <div className="l10n-panel">
      <section className="panel l10n-hero">
        <div>
          <h2>Localization check</h2>
          <p className="dim">
            Find hardcoded UI copy, verify ARB parity across locales, then get
            fix suggestions. Works with any Flutter <code>gen-l10n</code> layout
            (reads <code>l10n.yaml</code>, finds <code>*.arb</code> files, or
            scaffolds <code>lib/l10n</code> when none exist).
          </p>
          <p className="meta" title={projectDir}>
            Project: {projectDir || '—'}
          </p>
        </div>
        <div className="l10n-hero-actions">
          <button type="button" onClick={onChangeProject}>
            Change project
          </button>
          <button
            type="button"
            className="primary"
            disabled={busy || !isFlutter}
            onClick={() => void runAll()}
          >
            {busy ? 'Running…' : 'Run all 4 steps'}
          </button>
        </div>
      </section>

      <section className="panel l10n-filters">
        <label className="l10n-filter">
          <span>Optional path filter (under lib/, comma-separated)</span>
          <input
            value={pathFilter}
            onChange={(e) => setPathFilter(e.target.value)}
            placeholder="features/home-view-feature/…"
            disabled={busy}
          />
        </label>
      </section>

      {error ? <p className="error">{error}</p> : null}

      <nav className="l10n-steps-nav" aria-label="Localization steps">
        {([1, 2, 3, 4] as Step[]).map((n) => (
          <button
            key={n}
            type="button"
            className={step === n ? 'l10n-step active' : 'l10n-step'}
            onClick={() => setStep(n)}
          >
            <span className="l10n-step-num">{n}</span>
            <span className="l10n-step-label">
              {n === 1
                ? 'Hardcoded strings'
                : n === 2
                  ? 'Full project check'
                  : n === 3
                    ? 'Fix suggestions'
                    : 'Apply + verify'}
            </span>
          </button>
        ))}
      </nav>

      {step === 1 ? (
        <section className="panel">
          <div className="l10n-section-head">
            <div>
              <h3>Step 1 · Hardcoded UI strings</h3>
              <p className="dim">
                Baseline before you change copy — Text / Tab / TextViewWidget /
                label / title / hint strings.
              </p>
            </div>
            <button
              type="button"
              className="primary"
              disabled={busy || !isFlutter}
              onClick={() => void run('hardcoded')}
            >
              {busy ? 'Scanning…' : 'Scan hardcoded'}
            </button>
          </div>
          {!hardcodedResult ? (
            <p className="dim">Run a scan to list hardcoded values.</p>
          ) : hardcoded.length === 0 ? (
            <p className="ok">No likely hardcoded UI strings found.</p>
          ) : (
            <>
              <p className="meta">{hardcoded.length} finding(s)</p>
              <div className="l10n-table-wrap">
                <table className="l10n-table">
                  <thead>
                    <tr>
                      <th>File</th>
                      <th>Line</th>
                      <th>String</th>
                      <th>Snippet</th>
                    </tr>
                  </thead>
                  <tbody>
                    {hardcoded.map((row) => (
                      <tr key={`${row.relative}:${row.line}:${row.text}`}>
                        <td>
                          <code title={row.file}>{row.relative}</code>
                        </td>
                        <td>{row.line}</td>
                        <td>&quot;{row.text}&quot;</td>
                        <td>
                          <code className="l10n-snippet">{row.snippet}</code>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </section>
      ) : null}

      {step === 2 ? (
        <section className="panel">
          <div className="l10n-section-head">
            <div>
              <h3>Step 2 · Full project check</h3>
              <p className="dim">
                ARB key parity (en/es/fr), empty values, and{' '}
                <code>l10n.*</code> usages missing from the template ARB —
                plus hardcoded leftovers.
              </p>
            </div>
            <button
              type="button"
              className="primary"
              disabled={busy || !isFlutter}
              onClick={() => void run('full')}
            >
              {busy ? 'Checking…' : 'Check full project'}
            </button>
          </div>
          {!fullResult ? (
            <p className="dim">Run a full check to see project-wide issues.</p>
          ) : (
            <>
              <div className="l10n-stats">
                <div className="l10n-stat">
                  <strong>{fullResult.template_key_count}</strong>
                  <span>{fullResult.template} keys</span>
                </div>
                <div className="l10n-stat">
                  <strong>{fullResult.hard_issue_count}</strong>
                  <span>hard issues</span>
                </div>
                <div className="l10n-stat">
                  <strong>{fullResult.hardcoded_count}</strong>
                  <span>hardcoded</span>
                </div>
                <div className="l10n-stat">
                  <strong>{missing.length}</strong>
                  <span>missing keys</span>
                </div>
              </div>
              {hardIssues.length === 0 ? (
                <p className="ok">No hard localization issues.</p>
              ) : (
                <ul className="l10n-issue-list">
                  {hardIssues.map((issue) => (
                    <li key={issue}>
                      <code>{issue}</code>
                    </li>
                  ))}
                </ul>
              )}
              {fullResult.soft_issue_count > 0 ? (
                <details className="l10n-soft">
                  <summary>
                    Soft / advisory ({fullResult.soft_issue_count})
                  </summary>
                  <ul className="l10n-issue-list">
                    {fullResult.soft_issues.map((issue) => (
                      <li key={issue}>
                        <code>{issue}</code>
                      </li>
                    ))}
                  </ul>
                </details>
              ) : null}
            </>
          )}
        </section>
      ) : null}

      {step === 3 ? (
        <section className="panel">
          <div className="l10n-section-head">
            <div>
              <h3>Step 3 · Suggested fixes</h3>
              <p className="dim">
                Proposed ARB keys and Dart replacements. Each card lists the
                Flutter gen-l10n workflow: template ARB → other locale ARBs →{' '}
                gen-l10n → Dart (positional <code>l10n.key(...)</code>).
              </p>
            </div>
            <button
              type="button"
              className="primary"
              disabled={busy || !isFlutter}
              onClick={() => void run('suggestions')}
            >
              {busy ? 'Building…' : 'Generate suggestions'}
            </button>
          </div>
          {!suggestionsResult ? (
            <p className="dim">Generate suggestions from the current project.</p>
          ) : suggestions.length === 0 ? (
            <p className="ok">Nothing to fix — no hardcoded strings or missing keys.</p>
          ) : (
            <div className="l10n-suggestions">
              {suggestions.map((item) => (
                <SuggestionCard
                  key={`${item.kind}:${item.relative}:${item.line}:${item.suggestedKey}`}
                  item={item}
                  templateArb={suggestionsResult?.template ?? 'template.arb'}
                />
              ))}
            </div>
          )}
        </section>
      ) : null}

      {step === 4 ? (
        <section className="panel">
          <div className="l10n-section-head">
            <div>
              <h3>Step 4 · Apply + verify</h3>
              <p className="dim">
                Phase 1: add ARB keys (en/es/fr). Phase 2:{' '}
                <code>fvm flutter gen-l10n</code>. Phase 3: safe Dart string
                replacements only after gen-l10n succeeds. Then{' '}
                <code>dart analyze --fatal-warnings</code>. Missing-key fixes
                add ARB only — Dart is never edited for those.
              </p>
            </div>
            <button
              type="button"
              className="primary"
              disabled={busy || !isFlutter}
              onClick={() => void applyAll()}
            >
              {busy ? 'Applying…' : 'Apply safe changes + analyze'}
            </button>
          </div>
          {!applyResult ? (
            <p className="dim">
              Run step 3 first, then apply safe fixes and verify the project.
            </p>
          ) : (
            <>
              {applied ? (
                <div className="l10n-apply-result">
                  <h4>Applied changes</h4>
                  <p className="meta">
                    {applied.applied_files.length} file(s),{' '}
                    {applied.changed_keys.length} key change(s)
                  </p>
                  {applied.applied_files.length > 0 ? (
                    <ul className="l10n-issue-list">
                      {applied.applied_files.map((file) => (
                        <li key={file}>
                          <code>{file}</code>
                        </li>
                      ))}
                    </ul>
                  ) : null}
                  {applied.skipped.length > 0 ? (
                    <details className="l10n-soft">
                      <summary>Skipped ({applied.skipped.length})</summary>
                      <ul className="l10n-issue-list">
                        {applied.skipped.map((item) => (
                          <li key={item}>
                            <code>{item}</code>
                          </li>
                        ))}
                      </ul>
                    </details>
                  ) : null}
                </div>
              ) : null}
              {analysis ? (
                <div className="l10n-apply-result">
                  {genL10n ? (
                    <>
                      <h4>Step 3 — Generate l10n</h4>
                      <p className={genL10n.ok ? 'ok' : 'error'}>
                        {genL10n.ok
                          ? 'gen-l10n completed'
                          : `gen-l10n failed (${genL10n.exit_code})`}
                      </p>
                      <p className="meta">
                        <code>{genL10n.command}</code>
                      </p>
                      {genL10n.output ? (
                        <pre className="l10n-analyze-output">{genL10n.output}</pre>
                      ) : null}
                    </>
                  ) : null}
                  <h4>Step 4 — Analyze</h4>
                  <p className={analysis.ok ? 'ok' : 'error'}>
                    {analysis.ok
                      ? 'Analyze passed'
                      : `Analyze failed (${analysis.exit_code})`}
                  </p>
                  <p className="meta">
                    <code>{analysis.command}</code>
                  </p>
                  {analysis.output ? (
                    <pre className="l10n-analyze-output">{analysis.output}</pre>
                  ) : null}
                </div>
              ) : null}
            </>
          )}
        </section>
      ) : null}
    </div>
  )
}
