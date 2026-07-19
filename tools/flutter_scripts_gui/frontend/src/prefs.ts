/** UI preferences persisted in localStorage. */

const RECENT_KEY = 'flutter-scripts.recentScripts'
const DENSITY_KEY = 'flutter-scripts.density'
const MAX_RECENT = 8

export type Density = 'comfortable' | 'compact'

export function readRecentScripts(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw) as unknown
    if (!Array.isArray(parsed)) return []
    return parsed.filter((x): x is string => typeof x === 'string')
  } catch {
    return []
  }
}

export function pushRecentScript(file: string): string[] {
  const next = [file, ...readRecentScripts().filter((f) => f !== file)].slice(
    0,
    MAX_RECENT,
  )
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify(next))
  } catch {
    // ignore
  }
  return next
}

export function readDensity(): Density {
  try {
    const v = localStorage.getItem(DENSITY_KEY)
    return v === 'compact' ? 'compact' : 'comfortable'
  } catch {
    return 'comfortable'
  }
}

export function writeDensity(d: Density): void {
  try {
    localStorage.setItem(DENSITY_KEY, d)
  } catch {
    // ignore
  }
}
