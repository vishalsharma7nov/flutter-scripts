import { useState } from 'react'
import type { CommandLine, GuideStep } from '../data/types'
import { normalizeCommands } from '../data/types'
import { explainCommand } from '../lib/commandExplain'

type Props = {
  commands: Array<string | CommandLine>
}

function CopyButton({ text, label = 'Copy' }: { text: string; label?: string }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(true)
      window.setTimeout(() => setCopied(false), 1500)
    } catch {
      setCopied(false)
    }
  }

  return (
    <button type="button" className="btn btn-small" onClick={() => void copy()}>
      {copied ? 'Copied' : label}
    </button>
  )
}

export function CommandBlock({ commands }: Props) {
  const lines = normalizeCommands(commands).map((line) => ({
    ...line,
    what: line.what ?? explainCommand(line.cmd),
  }))
  const allText = lines.map((l) => l.cmd).join('\n')
  const copyable = lines.filter((l) => l.cmd.trim() && !l.cmd.trim().startsWith('#'))

  return (
    <div className="command-block">
      <ul className="command-lines">
        {lines.map((line, i) => {
          const canCopy = line.cmd.trim() && !line.cmd.trim().startsWith('#')
          return (
            <li key={`${i}-${line.cmd}`} className="command-line">
              <div className="command-line-top">
                <pre>
                  <code>{line.cmd}</code>
                </pre>
                {canCopy ? <CopyButton text={line.cmd} label="Copy" /> : null}
              </div>
              {line.what ? <p className="command-what">{line.what}</p> : null}
            </li>
          )
        })}
      </ul>
      {copyable.length > 1 ? (
        <div className="command-block-footer">
          <CopyButton text={allText} label="Copy all" />
        </div>
      ) : null}
    </div>
  )
}

export function StepsList({ steps }: { steps: GuideStep[] }) {
  return (
    <ol className="steps">
      {steps.map((step) => (
        <li key={step.title}>
          <h4>{step.title}</h4>
          {step.note ? <p className="note">{step.note}</p> : null}
          {step.warning ? <p className="warning">{step.warning}</p> : null}
          <CommandBlock commands={step.commands} />
        </li>
      ))}
    </ol>
  )
}
