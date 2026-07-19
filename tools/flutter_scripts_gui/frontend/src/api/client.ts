export interface ScriptItem {
  index: number
  file: string
  label: string
  description: string
}

export interface GuiStatus {
  port: number
  scriptsDir: string
  projectDir: string
  isFlutter?: boolean
  isFlutterApp?: boolean
  running: boolean
  runningFile: string
  git?: GitRepoStatus
  ollama?: OllamaStatus
}

export interface GitRepoStatus {
  repoRoot: string
  isRepo: boolean
  branch: string
  upstream: string
  ahead: number
  behind: number
  dirtyCount: number
  statusShort: string
  remoteURL: string
  headDetached: boolean
  error?: string
}

export interface OllamaStatus {
  available: boolean
  baseURL: string
  model: string
  models: string[]
  error?: string
}

export interface GitAnalyzeResponse {
  source: 'llm' | 'catalog' | 'fallback'
  summary: string
  why: string
  warning?: string
  llmRaw?: string
  model?: string
  llmError?: string
}

export interface LogEvent {
  type: 'log' | 'started' | 'exited' | 'error'
  line?: string
  file?: string
  code?: number
  ts: number
}

export interface ReleasePackage {
  id: string
  title: string
  description: string
}

async function parseError(res: Response): Promise<string> {
  const text = await res.text()
  return text.trim() || res.statusText
}

export async function fetchStatus(): Promise<GuiStatus> {
  const res = await fetch('/api/status')
  if (!res.ok) throw new Error(await parseError(res))
  return res.json()
}

export async function fetchScripts(): Promise<ScriptItem[]> {
  const res = await fetch('/api/scripts')
  if (!res.ok) throw new Error(await parseError(res))
  const data = await res.json()
  return data.scripts ?? []
}

export async function fetchReleasePackages(): Promise<ReleasePackage[]> {
  const res = await fetch('/api/release-packages')
  if (!res.ok) throw new Error(await parseError(res))
  const data = await res.json()
  return data.packages ?? []
}

export interface NearbyProject {
  path: string
  name: string
  isFlutterApp: boolean
  isCurrent?: boolean
}

export async function fetchProjects(): Promise<{
  projects: NearbyProject[]
  current: string
  isFlutter: boolean
  isFlutterApp: boolean
}> {
  const res = await fetch('/api/projects')
  if (!res.ok) throw new Error(await parseError(res))
  const data = await res.json()
  return {
    projects: data.projects ?? [],
    current: data.current ?? '',
    isFlutter: !!data.isFlutter,
    isFlutterApp: !!data.isFlutterApp,
  }
}

export async function runScript(file: string, args: string[]): Promise<void> {
  const res = await fetch('/api/run', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ file, args }),
  })
  if (!res.ok) throw new Error(await parseError(res))
}

export async function stopScript(): Promise<void> {
  const res = await fetch('/api/stop', { method: 'POST' })
  if (!res.ok) throw new Error(await parseError(res))
}

export async function setProject(source: string): Promise<{
  projectDir: string
  isFlutter: boolean
  isFlutterApp: boolean
  kind: string
}> {
  const res = await fetch('/api/project', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ source }),
  })
  if (!res.ok) throw new Error(await parseError(res))
  return res.json()
}

export function openLogStream(onEvent: (ev: LogEvent) => void): EventSource {
  const es = new EventSource('/api/logs')
  es.onmessage = (msg) => {
    try {
      onEvent(JSON.parse(msg.data) as LogEvent)
    } catch {
      // ignore malformed
    }
  }
  return es
}

export async function fetchGitRepo(): Promise<GitRepoStatus> {
  const res = await fetch('/api/git/repo')
  if (!res.ok) throw new Error(await parseError(res))
  return res.json()
}

export async function analyzeGitError(payload: {
  error: string
  matchedIssueId?: string
  matchedTitle?: string
  matchedWhy?: string
  useLLM: boolean
}): Promise<GitAnalyzeResponse> {
  const res = await fetch('/api/git/analyze', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (!res.ok) throw new Error(await parseError(res))
  return res.json()
}

export type LocalizationMode = 'hardcoded' | 'full' | 'suggestions'

export interface LocalizationHardcodedItem {
  file: string
  relative: string
  line: number
  text: string
  snippet?: string
}

export interface LocalizationMissingKey {
  key: string
  refs: string[]
  file?: string
  relative?: string
  line?: number | null
}

export interface LocalizationSuggestion {
  kind: 'hardcoded' | 'missing-key'
  file: string
  relative: string
  line?: number | null
  text: string
  suggestedKey: string
  arbEn: string
  arbEs: string
  arbFr: string
  dartBefore: string
  dartAfter: string
  steps: string[]
  apply?: {
    key: string
    arbValue: string
    placeholders: { name: string; expr: string }[]
    dartBefore?: string
    dartAfter?: string
  }
}

export interface LocalizationCheckResult {
  project: string
  mode: LocalizationMode
  arb_files: string[]
  template: string
  template_key_count: number
  hardcoded: LocalizationHardcodedItem[]
  hardcoded_count: number
  parity_issues: string[]
  missing_keys: LocalizationMissingKey[]
  hard_issues: string[]
  soft_issues: string[]
  hard_issue_count: number
  soft_issue_count: number
  suggestions: LocalizationSuggestion[]
  suggestion_count: number
  apply_result?: {
    applied: boolean
    applied_files: string[]
    changed_keys: string[]
    skipped: string[]
  } | null
  l10n_result?: {
    command: string
    exit_code: number
    ok: boolean
    output: string
  } | null
  analysis_result?: {
    command: string
    exit_code: number
    ok: boolean
    output: string
  } | null
}

function normalizeLocalizationResult(
  data: Partial<LocalizationCheckResult>,
): LocalizationCheckResult {
  return {
    project: data.project ?? '',
    mode: (data.mode ?? 'full') as LocalizationMode,
    arb_files: data.arb_files ?? [],
    template: data.template ?? '',
    template_key_count: data.template_key_count ?? 0,
    hardcoded: data.hardcoded ?? [],
    hardcoded_count: data.hardcoded_count ?? 0,
    parity_issues: data.parity_issues ?? [],
    missing_keys: data.missing_keys ?? [],
    hard_issues: data.hard_issues ?? [],
    soft_issues: data.soft_issues ?? [],
    hard_issue_count: data.hard_issue_count ?? 0,
    soft_issue_count: data.soft_issue_count ?? 0,
    suggestions: (data.suggestions ?? []).map((item) => ({
      ...item,
      steps: item.steps ?? [],
      apply: item.apply
        ? {
            ...item.apply,
            placeholders: item.apply.placeholders ?? [],
          }
        : undefined,
    })),
    suggestion_count: data.suggestion_count ?? 0,
    apply_result: data.apply_result
      ? {
          applied: !!data.apply_result.applied,
          applied_files: data.apply_result.applied_files ?? [],
          changed_keys: data.apply_result.changed_keys ?? [],
          skipped: data.apply_result.skipped ?? [],
        }
      : null,
    l10n_result: data.l10n_result ?? null,
    analysis_result: data.analysis_result ?? null,
  }
}

export async function checkLocalization(
  mode: LocalizationMode,
  path?: string[],
): Promise<LocalizationCheckResult> {
  const res = await fetch('/api/localization/check', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode, path: path?.filter(Boolean) ?? [] }),
  })
  if (!res.ok) {
    const body = await parseError(res)
    if (res.status === 404) {
      throw new Error(
        'Localization API not found — quit and reopen Flutter Scripts (or run open-flutter-scripts-gui.sh) so the GUI server reloads.',
      )
    }
    throw new Error(body)
  }
  return normalizeLocalizationResult(await res.json())
}

export async function applyLocalization(path?: string[]): Promise<LocalizationCheckResult> {
  const res = await fetch('/api/localization/apply', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: path?.filter(Boolean) ?? [] }),
  })
  if (!res.ok) throw new Error(await parseError(res))
  return normalizeLocalizationResult(await res.json())
}

