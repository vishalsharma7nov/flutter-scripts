import { fetchStatus, postJson, type MonitorStatus } from '../api/client'

export type BackendLang = 'dart' | 'go' | 'typescript'

const LABELS: Record<BackendLang, string> = {
  dart: 'Dart',
  go: 'Go',
  typescript: 'TypeScript',
}

interface BackendSwitchProps {
  status: MonitorStatus | null
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
  onChanged: () => void
}

async function waitForMonitorRestart(timeoutMs = 20000): Promise<boolean> {
  const started = Date.now()
  await new Promise((r) => window.setTimeout(r, 400))
  while (Date.now() - started < timeoutMs) {
    try {
      const status = await fetchStatus()
      if (status && typeof status === 'object') {
        return true
      }
    } catch {
      // still down
    }
    await new Promise((r) => window.setTimeout(r, 400))
  }
  return false
}

export function BackendSwitch({ status, onFeedback, onChanged }: BackendSwitchProps) {
  const live = (status?.backend || 'dart') as BackendLang
  const preferred = (status?.preferredBackend || live) as BackendLang
  const available = (status?.availableBackends || [
    'dart',
    'go',
    'typescript',
  ]) as BackendLang[]
  const usingFallback = preferred !== live

  return (
    <div className="backend-switch-wrap">
      <div className="backend-switch" role="group" aria-label="Monitor server backend language">
        <span className="backend-switch-label">Server</span>
        {available.map((lang) => {
          const isPreferred = preferred === lang
          const isLive = live === lang
          let suffix = ''
          if (isPreferred && isLive) {
            suffix = ' · selected'
          } else if (isPreferred) {
            suffix = ' · selected'
          } else if (isLive && usingFallback) {
            suffix = ' · live fallback'
          } else if (isLive) {
            suffix = ' · live'
          }

          return (
            <button
              key={lang}
              type="button"
              className={[
                'backend-switch-btn',
                isPreferred ? 'is-selected' : '',
                isLive && !isPreferred ? 'is-fallback' : '',
                isLive && isPreferred ? 'is-running' : '',
              ]
                .filter(Boolean)
                .join(' ')}
              title={
                lang === 'dart' && isLive && usingFallback
                  ? `${LABELS[preferred]} is selected, but only Dart is implemented — Dart is running as fallback`
                  : isPreferred
                    ? `${LABELS[lang]} is your selected server track`
                    : `Select ${LABELS[lang]} and restart monitor`
              }
              onClick={async () => {
                if (isPreferred && !usingFallback) {
                  onFeedback(`${LABELS[lang]} is already selected and live.`, { isOk: true })
                  return
                }
                onFeedback(`Selecting ${LABELS[lang]} — restarting monitor…`)
                try {
                  const payload = await postJson<{
                    ok?: boolean
                    error?: string
                    message?: string
                    preferredBackend?: string
                    directory?: string
                    runnable?: boolean
                    restarting?: boolean
                  }>('/api/backend', { backend: lang, restart: true })
                  if (!payload.ok) {
                    onFeedback(payload.error || 'Could not set backend', { isError: true })
                    return
                  }
                  if (payload.restarting) {
                    onFeedback(
                      payload.message || `Restarting monitor for ${LABELS[lang]}…`,
                    )
                    const up = await waitForMonitorRestart()
                    if (!up) {
                      onFeedback(
                        'Monitor did not come back. Keep open-isolate-monitor.sh running for auto-restart.',
                        { isError: true },
                      )
                      return
                    }
                    onFeedback(
                      payload.runnable
                        ? `Selected ${LABELS[lang]} — now live.`
                        : `Selected ${LABELS[lang]}. Dart/Go stay available; TypeScript is not implemented yet (${payload.directory || `server/${lang}`}).`,
                      { isOk: true },
                    )
                    onChanged()
                    return
                  }
                  onFeedback(payload.message || `Preferred backend: ${lang}`, {
                    isOk: payload.runnable === true,
                    isError: payload.runnable !== true,
                  })
                  onChanged()
                } catch (error) {
                  const message =
                    error instanceof Error
                      ? error.message
                      : `Backend switch failed: ${error}`
                  if (/missing|restart the isolate monitor/i.test(message)) {
                    onFeedback(
                      'Backend API missing — stop and re-run open-isolate-monitor.sh once.',
                      { isError: true },
                    )
                    return
                  }
                  onFeedback(message, { isError: true })
                }
              }}
            >
              {LABELS[lang]}
              {suffix}
            </button>
          )
        })}
      </div>
      {usingFallback ? (
        <p className="backend-switch-note">
          Selected <strong>{LABELS[preferred]}</strong> — running{' '}
          <strong>{LABELS[live]}</strong> (fallback; {LABELS[preferred]} server not
          implemented yet under{' '}
          <code>{status?.backendHint || `server/${preferred}`}</code>).
        </p>
      ) : null}
    </div>
  )
}
