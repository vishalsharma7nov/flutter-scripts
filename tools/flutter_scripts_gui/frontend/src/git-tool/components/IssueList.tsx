import { useMemo } from 'react'
import type { GitIssue } from '../data/issues'
import { normalizeCommands } from '../data/types'

type Props = {
  issues: GitIssue[]
  selectedId: string | null
  onSelect: (id: string) => void
  search: string
  onSearchChange: (v: string) => void
}

function issueMatches(issue: GitIssue, q: string): boolean {
  if (!q) return true
  const cmds = [...issue.diagnose, ...issue.fix].flatMap((s) =>
    normalizeCommands(s.commands).map((c) => c.cmd),
  )
  const hay = [issue.title, issue.why, ...issue.keywords, ...cmds]
    .join(' ')
    .toLowerCase()
  return hay.includes(q)
}

export function IssueList({
  issues,
  selectedId,
  onSelect,
  search,
  onSearchChange,
}: Props) {
  const q = search.trim().toLowerCase()
  const filtered = useMemo(
    () => issues.filter((i) => issueMatches(i, q)),
    [issues, q],
  )

  return (
    <div className="list-panel">
      <input
        className="git-search"
        placeholder="Search issues / commands…"
        value={search}
        onChange={(e) => onSearchChange(e.target.value)}
        aria-label="Search troubleshoot issues"
      />
      <h3 className="list-group-title">Common issues</h3>
      {filtered.length === 0 ? (
        <p className="hint">No issues match.</p>
      ) : (
        <ul>
          {filtered.map((issue) => (
            <li key={issue.id}>
              <button
                type="button"
                className={
                  selectedId === issue.id ? 'list-item active' : 'list-item'
                }
                onClick={() => onSelect(issue.id)}
              >
                {issue.title}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
