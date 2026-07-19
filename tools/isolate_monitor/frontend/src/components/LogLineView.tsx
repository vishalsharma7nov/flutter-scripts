import { useMemo } from 'react'
import {
  ERROR_LEVELS,
  FILE_REF_PATTERN,
  classifyLogLine,
  escapeHtml,
  extractFirstFileRef,
  formatFileOpenerLabel,
  levelTagLabel,
} from '../lib/logUtils'

interface LogLineProps {
  line: string
  lineIndex: number
  query: string
  caseSensitive: boolean
  canOpenFiles: boolean
  fileOpenerName: string
  onOpenFile: (reference: string) => void
  onErrorTagTap: (lineIndex: number) => void
}

function highlightMatches(
  text: string,
  query: string,
  caseSensitive: boolean,
): string {
  const safe = escapeHtml(text)
  const trimmed = query.trim()
  if (!trimmed) return safe
  const terms = trimmed
    .split('|')
    .map((t) => t.trim())
    .filter(Boolean)
  if (terms.length === 0) return safe
  const flags = caseSensitive ? 'g' : 'gi'
  const pattern = terms
    .map((t) => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('|')
  return safe.replace(
    new RegExp(pattern, flags),
    (match) => `<mark>${match}</mark>`,
  )
}

function buildBodyHtml(
  line: string,
  query: string,
  caseSensitive: boolean,
  fileOpenerName: string,
): string {
  const parts: { type: 'text' | 'link'; value: string; ref?: string }[] = []
  let lastIndex = 0
  const pattern = new RegExp(FILE_REF_PATTERN.source, FILE_REF_PATTERN.flags)
  let match: RegExpExecArray | null
  while ((match = pattern.exec(line)) !== null) {
    if (match.index > lastIndex) {
      parts.push({ type: 'text', value: line.slice(lastIndex, match.index) })
    }
    const column = match[3] || '1'
    const ref = `${match[1]}:${match[2]}:${column}`
    parts.push({ type: 'link', value: match[0], ref })
    lastIndex = pattern.lastIndex
  }
  if (lastIndex < line.length) {
    parts.push({ type: 'text', value: line.slice(lastIndex) })
  }
  if (parts.length === 0) {
    parts.push({ type: 'text', value: line })
  }

  return parts
    .map((part) => {
      if (part.type === 'link' && part.ref) {
        const opener = formatFileOpenerLabel(fileOpenerName)
        return `<button type="button" class="log-file-link" data-ref="${escapeHtml(part.ref)}" title="Open ${escapeHtml(part.ref)} in ${escapeHtml(opener)}">${escapeHtml(part.value)}</button>`
      }
      return highlightMatches(part.value, query, caseSensitive)
    })
    .join('')
}

export function LogLineView({
  line,
  lineIndex,
  query,
  caseSensitive,
  canOpenFiles,
  fileOpenerName,
  onOpenFile,
  onErrorTagTap,
}: LogLineProps) {
  const level = useMemo(() => classifyLogLine(line), [line])
  const fileRef = useMemo(() => extractFirstFileRef(line), [line])
  const isErrorLevel = ERROR_LEVELS.has(level)
  const bodyHtml = useMemo(
    () => buildBodyHtml(line, query, caseSensitive, fileOpenerName),
    [line, query, caseSensitive, fileOpenerName],
  )

  const className = [
    'log-line',
    `log-${level}`,
    fileRef ? 'log-openable' : '',
    isErrorLevel ? 'log-error-tappable' : '',
  ]
    .filter(Boolean)
    .join(' ')

  const title = fileRef
    ? canOpenFiles
      ? `Open ${fileRef} in ${formatFileOpenerLabel(fileOpenerName)}`
      : `File reference: ${fileRef}`
    : undefined

  const tagTitle = isErrorLevel
    ? canOpenFiles
      ? `Open source file in ${formatFileOpenerLabel(fileOpenerName)}`
      : 'Tap to find and open the source file (start monitor with project path)'
    : undefined

  return (
    <div
      className={className}
      data-line-index={lineIndex}
      data-file-ref={fileRef || undefined}
      title={title}
      onClick={(event) => {
        const target = event.target as HTMLElement
        const fileLink = target.closest('.log-file-link') as HTMLElement | null
        if (fileLink?.dataset.ref) {
          event.preventDefault()
          onOpenFile(fileLink.dataset.ref)
          return
        }
        if (target.closest('.log-level-tag') && isErrorLevel) {
          event.preventDefault()
          onErrorTagTap(lineIndex)
          return
        }
        if (fileRef && (event.target as HTMLElement).closest('.log-line-body')) {
          onOpenFile(fileRef)
        }
      }}
    >
      {isErrorLevel ? (
        <button
          type="button"
          className={`log-level-tag log-level-${level}`}
          title={tagTitle}
        >
          {levelTagLabel(level)}
        </button>
      ) : (
        <span className={`log-level-tag log-level-${level}`}>{levelTagLabel(level)}</span>
      )}
      <span
        className="log-line-body"
        dangerouslySetInnerHTML={{ __html: bodyHtml }}
      />
    </div>
  )
}
