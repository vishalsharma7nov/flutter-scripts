export type CommandLine = {
  /** Shell command to copy */
  cmd: string
  /** Plain-English: what this command does */
  what?: string
}

export type GuideStep = {
  title: string
  /** Prefer `{ cmd, what }` so the UI can explain each command. */
  commands: Array<string | CommandLine>
  note?: string
  warning?: string
}

/** Accept legacy string[] or explained CommandLine[]. */
export function normalizeCommands(
  commands: Array<string | CommandLine>,
): CommandLine[] {
  return commands.map((c) =>
    typeof c === 'string' ? { cmd: c } : c,
  )
}
