import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  analyzeGitError,
  fetchStatus,
  setProject,
  type GitAnalyzeResponse,
  type GitRepoStatus,
  type GuiStatus,
  type OllamaStatus,
} from '../api/client'
import { StepsList } from './components/CommandBlock'
import { howToTopics } from './data/howToTopics'
import { findIssueById, gitIssues, type GitIssue } from './data/issues'
import { matchErrorToIssue } from './lib/matchError'
import './git-llm.css'

type View = 'home' | 'fix' | 'howto' | 'status'

export type GitDeepLinkTarget = {
  tab: 'howto' | 'troubleshoot'
  id: string
}

type Props = {
  deepLink?: GitDeepLinkTarget | null
  onDeepLinkConsumed?: () => void
  projectDir?: string
  onProjectChanged?: () => void
}

const STARTER_IDS = [
  'clone',
  'branch-create',
  'commit',
  'push',
  'pr-create',
  'merge',
] as const

const SAMPLE_PUSH = `To github.com:acme/app.git
 ! [rejected]        main -> main (non-fast-forward)
error: failed to push some refs to 'github.com:acme/app.git'
hint: Updates were rejected because the tip of your current branch is behind
hint: its remote counterpart. Integrate the remote changes (e.g.
hint: 'git pull ...') before pushing again.`

function toast(msg: string) {
  const el = document.getElementById('git-llm-toast')
  if (!el) return
  el.textContent = msg
  el.classList.add('show')
  window.setTimeout(() => el.classList.remove('show'), 1400)
}

export function GitToolPanel({
  deepLink,
  onDeepLinkConsumed,
  projectDir,
  onProjectChanged,
}: Props) {
  const [view, setView] = useState<View>('home')
  const [git, setGit] = useState<GitRepoStatus | null>(null)
  const [ollama, setOllama] = useState<OllamaStatus | null>(null)
  const [repoPath, setRepoPath] = useState(projectDir ?? '')
  const [errorText, setErrorText] = useState('')
  const [issue, setIssue] = useState<GitIssue | null>(null)
  const [analysis, setAnalysis] = useState<GitAnalyzeResponse | null>(null)
  const [analyzing, setAnalyzing] = useState(false)
  const [showFix, setShowFix] = useState(false)
  const [done, setDone] = useState(false)
  const [issueSearch, setIssueSearch] = useState('')
  const [howToId, setHowToId] = useState(
    howToTopics.find((t) => t.id === 'commit')?.id ?? howToTopics[0]?.id ?? '',
  )
  const [howToSearch, setHowToSearch] = useState('')
  const [useLLM, setUseLLM] = useState(true)

  const refresh = useCallback(async () => {
    try {
      const st: GuiStatus = await fetchStatus()
      setGit(st.git ?? null)
      setOllama(st.ollama ?? null)
      setRepoPath(st.projectDir)
    } catch {
      // parent app already shows connection errors
    }
  }, [])

  useEffect(() => {
    void refresh()
    const id = window.setInterval(() => void refresh(), 8000)
    return () => window.clearInterval(id)
  }, [refresh, projectDir])

  useEffect(() => {
    if (!deepLink) return
    if (deepLink.tab === 'howto') {
      setView('howto')
      setHowToId(deepLink.id)
      setHowToSearch('')
    } else {
      setView('fix')
      const found = findIssueById(deepLink.id)
      if (found) {
        setIssue(found)
        setAnalysis({
          source: 'catalog',
          summary: found.title,
          why: found.why,
        })
        setShowFix(false)
        setDone(false)
      }
    }
    onDeepLinkConsumed?.()
  }, [deepLink, onDeepLinkConsumed])

  const howTo = useMemo(
    () => howToTopics.find((t) => t.id === howToId) ?? null,
    [howToId],
  )

  const starters = useMemo(
    () =>
      STARTER_IDS.map((id) => howToTopics.find((t) => t.id === id)).filter(
        (t): t is NonNullable<typeof t> => !!t,
      ),
    [],
  )

  const filteredIssues = useMemo(() => {
    const q = issueSearch.trim().toLowerCase()
    if (!q) return gitIssues
    return gitIssues.filter(
      (i) =>
        i.title.toLowerCase().includes(q) ||
        i.keywords.some((k) => k.toLowerCase().includes(q)),
    )
  }, [issueSearch])

  const filteredHowTos = useMemo(() => {
    const q = howToSearch.trim().toLowerCase()
    if (!q) return howToTopics
    return howToTopics.filter(
      (t) =>
        t.title.toLowerCase().includes(q) ||
        t.summary.toLowerCase().includes(q) ||
        t.category.toLowerCase().includes(q),
    )
  }, [howToSearch])

  const ollamaOk = ollama?.available ?? false

  async function onAnalyze(raw?: string) {
    const text = (raw ?? errorText).trim()
    if (!text) {
      toast('Paste an error first')
      return
    }
    setErrorText(text)
    setAnalyzing(true)
    setShowFix(false)
    setDone(false)
    const matched = matchErrorToIssue(text)
    setIssue(matched)
    try {
      const res = await analyzeGitError({
        error: text,
        matchedIssueId: matched?.id,
        matchedTitle: matched?.title,
        matchedWhy: matched?.why,
        useLLM: useLLM && ollamaOk,
      })
      setAnalysis(res)
      toast(res.source === 'llm' ? 'LLM diagnosis ready' : 'Catalog match ready')
    } catch (e) {
      setAnalysis({
        source: matched ? 'catalog' : 'fallback',
        summary: matched?.title ?? 'Could not analyze',
        why: matched?.why ?? (e instanceof Error ? e.message : 'Analyze failed'),
      })
    } finally {
      setAnalyzing(false)
    }
  }

  async function onSetRepo() {
    try {
      await setProject(repoPath)
      await refresh()
      onProjectChanged?.()
      toast('Project / repo updated')
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Invalid path')
    }
  }

  function selectIssue(id: string) {
    const found = findIssueById(id)
    if (!found) return
    setIssue(found)
    setAnalysis({
      source: 'catalog',
      summary: found.title,
      why: found.why,
    })
    setShowFix(false)
    setDone(false)
  }

  return (
    <div className="git-llm">
      <div className="shell" style={{ maxWidth: 'none', padding: 0, minHeight: 0 }}>
        <header className="topbar">
          <div className="brand">
            <h1>Git LLM</h1>
            <p>See the problem → understand why → apply a safe fix</p>
          </div>
          <div
            className={ollamaOk ? 'status-pill' : 'status-pill warn'}
            title={ollama?.error ?? ollama?.baseURL}
          >
            <span className="status-dot" aria-hidden />
            {ollamaOk
              ? `Local LLM · ${ollama?.model ?? 'ready'}`
              : 'Catalog mode · Ollama offline'}
          </div>
        </header>

        {view === 'home' ? (
          <section className="view" aria-label="Home">
            <div className="home-hero">
              <h2>What do you need right now?</h2>
              <p>
                Same app as Scripts — Fix errors with optional local LLM, browse
                workflows, or inspect the current project repo.
              </p>
            </div>

            <div className="path-grid">
              <button
                type="button"
                className="path primary"
                onClick={() => setView('fix')}
              >
                <span className="path-num">01</span>
                <h3>Fix an error</h3>
                <p>
                  Paste a commit, push, pull, or merge failure. Get diagnosis and
                  step-by-step commands.
                </p>
                <span className="path-cta">Paste error →</span>
              </button>
              <button
                type="button"
                className="path"
                onClick={() => setView('howto')}
              >
                <span className="path-num">02</span>
                <h3>Daily workflows</h3>
                <p>
                  Clone, branch, commit, push, open a PR — each step explained.
                </p>
                <span className="path-cta">Browse how-to →</span>
              </button>
              <button
                type="button"
                className="path"
                onClick={() => setView('status')}
              >
                <span className="path-num">03</span>
                <h3>Repo status</h3>
                <p>
                  Live branch, remote, ahead/behind — grounded in the selected
                  project.
                </p>
                <span className="path-cta">Inspect repo →</span>
              </button>
            </div>

            <div className="feature-rail">
              <span>Also covers</span>
              <div className="feature-chips">
                <button
                  type="button"
                  className="chip"
                  onClick={() => {
                    setView('fix')
                    setErrorText(SAMPLE_PUSH)
                  }}
                >
                  Push rejected
                </button>
                <button
                  type="button"
                  className="chip"
                  onClick={() => {
                    setView('fix')
                    selectIssue('merge-conflicts')
                  }}
                >
                  Merge conflict
                </button>
                <button
                  type="button"
                  className="chip"
                  onClick={() => {
                    setView('fix')
                    selectIssue('auth-failed')
                  }}
                >
                  Auth / SSH
                </button>
                <button
                  type="button"
                  className="chip"
                  onClick={() => {
                    setHowToId('pr-create')
                    setView('howto')
                  }}
                >
                  Pull request
                </button>
              </div>
            </div>
          </section>
        ) : null}

        {view === 'fix' ? (
          <section className="view" aria-label="Fix an error">
            <button
              type="button"
              className="btn btn-ghost back"
              onClick={() => setView('home')}
            >
              ← All paths
            </button>
            <RepoStrip git={git} ollama={ollama} projectDir={projectDir} />
            <div className="fix-layout">
              <aside className="panel paste-box">
                <h3>Paste the error</h3>
                <p>
                  Terminal output works best.{' '}
                  <button
                    type="button"
                    className="sample-link"
                    onClick={() => setErrorText(SAMPLE_PUSH)}
                  >
                    Load sample push rejection
                  </button>
                </p>
                <textarea
                  value={errorText}
                  onChange={(e) => setErrorText(e.target.value)}
                  placeholder="! [rejected] main -> main (non-fast-forward)…"
                />
                <label className="row" style={{ marginBottom: '0.65rem' }}>
                  <input
                    type="checkbox"
                    checked={useLLM}
                    onChange={(e) => setUseLLM(e.target.checked)}
                    disabled={!ollamaOk}
                  />
                  <span className="muted" style={{ margin: 0 }}>
                    Use local LLM when available
                  </span>
                </label>
                <div className="row">
                  <button
                    type="button"
                    className="btn btn-accent"
                    disabled={analyzing}
                    onClick={() => void onAnalyze()}
                  >
                    {analyzing ? 'Analyzing…' : 'Analyze'}
                  </button>
                  <button
                    type="button"
                    className="btn"
                    onClick={() => {
                      setErrorText('')
                      setIssue(null)
                      setAnalysis(null)
                      setShowFix(false)
                      setDone(false)
                    }}
                  >
                    Clear
                  </button>
                </div>
                <input
                  className="git-search"
                  placeholder="Or search known issues…"
                  value={issueSearch}
                  onChange={(e) => setIssueSearch(e.target.value)}
                  style={{ marginTop: '0.85rem' }}
                />
                <ul className="issue-list">
                  {filteredIssues.slice(0, 40).map((i) => (
                    <li key={i.id}>
                      <button
                        type="button"
                        className={issue?.id === i.id ? 'active' : undefined}
                        onClick={() => selectIssue(i.id)}
                      >
                        {i.title}
                      </button>
                    </li>
                  ))}
                </ul>
              </aside>

              <main className="panel">
                {!analysis ? (
                  <>
                    <p className="eyebrow">Diagnosis</p>
                    <h2 className="detail-title">Waiting for an error</h2>
                    <p className="why">
                      After Analyze: what broke, why, risk, diagnose commands,
                      then the fix.
                    </p>
                  </>
                ) : (
                  <>
                    <div className="diag-head">
                      <p className="eyebrow">
                        {analysis.source === 'llm'
                          ? `LLM · ${analysis.model ?? 'local'}`
                          : analysis.source === 'catalog'
                            ? 'Catalog match'
                            : 'Fallback'}
                        {issue ? ` · ${issue.id}` : ''}
                      </p>
                      <h2 className="detail-title">{analysis.summary}</h2>
                      <p className="why">
                        <strong>Why: </strong>
                        {analysis.why}
                      </p>
                      <div className="badge-row">
                        {issue ? (
                          <span className="badge safe">Safe fix available</span>
                        ) : (
                          <span className="badge warn">Manual review</span>
                        )}
                        {analysis.warning ? (
                          <span className="badge warn">{analysis.warning}</span>
                        ) : (
                          <span className="badge warn">
                            Avoid force-push on main
                          </span>
                        )}
                      </div>
                      {analysis.llmError ? (
                        <p className="llm-hint">LLM note: {analysis.llmError}</p>
                      ) : null}
                    </div>

                    <div className="flow-steps">
                      <div className="flow-step active">
                        <span className="n">STEP 1</span>
                        <span className="t">Confirm with diagnose</span>
                      </div>
                      <div className={`flow-step ${showFix ? 'active' : ''}`}>
                        <span className="n">STEP 2</span>
                        <span className="t">Apply the fix</span>
                      </div>
                      <div className={`flow-step ${done ? 'active' : ''}`}>
                        <span className="n">STEP 3</span>
                        <span className="t">Verify it worked</span>
                      </div>
                    </div>

                    {issue ? (
                      <>
                        <h3 className="section-title">1. Diagnose first</h3>
                        <StepsList steps={issue.diagnose} />
                        <div className="actions-bar">
                          <button
                            type="button"
                            className="btn btn-accent"
                            onClick={() => setShowFix(true)}
                          >
                            Show solution
                          </button>
                        </div>
                        {showFix ? (
                          <div style={{ marginTop: '1.25rem' }}>
                            <h3 className="section-title">2. Solution</h3>
                            <StepsList steps={issue.fix} />
                            <div className="actions-bar">
                              <button
                                type="button"
                                className="btn btn-accent"
                                onClick={() => {
                                  setDone(true)
                                  toast('Verify with git status / push')
                                }}
                              >
                                Mark as fixed
                              </button>
                            </div>
                          </div>
                        ) : (
                          <p className="muted" style={{ marginTop: '0.75rem' }}>
                            Tap Show solution after diagnose commands.
                          </p>
                        )}
                      </>
                    ) : (
                      <p className="muted">
                        No catalog steps — use the summary above or pick an
                        issue.
                      </p>
                    )}
                  </>
                )}
              </main>
            </div>
          </section>
        ) : null}

        {view === 'howto' ? (
          <section className="view" aria-label="Daily workflows">
            <button
              type="button"
              className="btn btn-ghost back"
              onClick={() => setView('home')}
            >
              ← All paths
            </button>
            <div className="howto-layout">
              <aside className="panel">
                <p className="eyebrow">Typical day</p>
                <ul className="day-list" style={{ marginBottom: '0.75rem' }}>
                  {starters.map((t, i) => (
                    <li key={t.id}>
                      <button
                        type="button"
                        className={howToId === t.id ? 'active' : undefined}
                        onClick={() => setHowToId(t.id)}
                      >
                        <span className="day-num">{i + 1}</span>
                        {t.title}
                      </button>
                    </li>
                  ))}
                </ul>
                <input
                  className="git-search"
                  placeholder="Search all workflows…"
                  value={howToSearch}
                  onChange={(e) => setHowToSearch(e.target.value)}
                />
                {howToSearch ? (
                  <ul className="day-list">
                    {filteredHowTos.map((t) => (
                      <li key={t.id}>
                        <button
                          type="button"
                          className={howToId === t.id ? 'active' : undefined}
                          onClick={() => setHowToId(t.id)}
                        >
                          <span className="day-num">·</span>
                          {t.title}
                        </button>
                      </li>
                    ))}
                  </ul>
                ) : null}
              </aside>
              <article className="panel">
                {howTo ? (
                  <>
                    <p className="eyebrow">{howTo.category}</p>
                    <h2 className="detail-title">{howTo.title}</h2>
                    <p className="why" style={{ marginBottom: '1rem' }}>
                      {howTo.summary}
                    </p>
                    <StepsList steps={howTo.steps} />
                  </>
                ) : null}
              </article>
            </div>
          </section>
        ) : null}

        {view === 'status' ? (
          <section className="view" aria-label="Repo status">
            <button
              type="button"
              className="btn btn-ghost back"
              onClick={() => setView('home')}
            >
              ← All paths
            </button>
            <div className="panel">
              <p className="eyebrow">Project path (shared with Scripts)</p>
              <div className="row">
                <input
                  className="repo-input"
                  style={{ flex: 1, marginBottom: 0 }}
                  value={repoPath}
                  onChange={(e) => setRepoPath(e.target.value)}
                  placeholder="/path/to/project"
                />
                <button
                  type="button"
                  className="btn btn-accent"
                  onClick={() => void onSetRepo()}
                >
                  Use path
                </button>
                <button
                  type="button"
                  className="btn"
                  onClick={() => void refresh()}
                >
                  Refresh
                </button>
              </div>
            </div>
            <div className="status-grid">
              <div className="panel">
                <p className="eyebrow">Live snapshot</p>
                <h2 className="detail-title">Repo at a glance</h2>
                {!git?.isRepo ? (
                  <p className="why">{git?.error ?? 'Not a git repository'}</p>
                ) : (
                  <>
                    <div
                      className="status-grid"
                      style={{ marginBottom: '0.85rem' }}
                    >
                      <div className="metric">
                        <p className="lbl">Branch</p>
                        <p className="val">
                          {git.headDetached ? 'DETACHED' : git.branch || '—'}
                        </p>
                      </div>
                      <div className="metric">
                        <p className="lbl">Tracking</p>
                        <p className="val">{git.upstream || '—'}</p>
                      </div>
                      <div className="metric">
                        <p className="lbl">Ahead / behind</p>
                        <p className="val">
                          +{git.ahead} / −{git.behind}
                        </p>
                      </div>
                      <div className="metric">
                        <p className="lbl">Working tree</p>
                        <p className="val">
                          {git.dirtyCount === 0
                            ? 'clean'
                            : `${git.dirtyCount} changed`}
                        </p>
                      </div>
                    </div>
                    <div className="row">
                      <button
                        type="button"
                        className="btn btn-accent"
                        onClick={() => setView('fix')}
                      >
                        Something looks wrong → Fix
                      </button>
                      <button
                        type="button"
                        className="btn"
                        onClick={() => setView('howto')}
                      >
                        Continue a workflow
                      </button>
                    </div>
                  </>
                )}
              </div>
              <div className="panel">
                <p className="eyebrow">Raw output</p>
                <h3 className="section-title">git status -sb</h3>
                <pre className="outbox">{git?.statusShort || '(no status)'}</pre>
              </div>
            </div>
          </section>
        ) : null}

        <div className="toast" id="git-llm-toast" role="status" />
      </div>
    </div>
  )
}

function RepoStrip({
  git,
  ollama,
  projectDir,
}: {
  git: GitRepoStatus | null
  ollama: OllamaStatus | null
  projectDir?: string
}) {
  return (
    <div className="repo-strip" aria-label="Repo context">
      <span>
        <span className="k">Project </span>
        <span className="v">{git?.repoRoot || projectDir || '—'}</span>
      </span>
      <span className="sep" aria-hidden />
      <span>
        <span className="k">Branch </span>
        <span className="v">
          {git?.isRepo
            ? git.headDetached
              ? 'DETACHED'
              : git.branch
            : 'n/a'}
        </span>
      </span>
      <span className="sep" aria-hidden />
      <span>
        <span className="k">vs upstream </span>
        <span className="v">
          {git?.isRepo ? `+${git.ahead}/−${git.behind}` : '—'}
        </span>
      </span>
      <span className="sep" aria-hidden />
      <span>
        <span className="k">Model </span>
        <span className="v">
          {ollama?.available ? ollama.model : 'catalog only'}
        </span>
      </span>
    </div>
  )
}
