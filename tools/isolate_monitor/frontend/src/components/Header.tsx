import type { MonitorStatus } from '../api/client'
import { modeLabelText, reinstallButtonLabel } from '../lib/logUtils'
import { BackendSwitch } from './BackendSwitch'

interface HeaderProps {
  status: MonitorStatus | null
  statusText: string
  statusClass: 'waiting' | 'connected'
  flutterStatus: string
  flutterStatusError: boolean
  uiAction: { message: string; isError: boolean; isOk: boolean; busy: boolean }
  busy: {
    refresh: boolean
    reloadGui: boolean
    reinstall: boolean
    hotReload: boolean
    hotRestart: boolean
    stop: boolean
  }
  onFeedback: (message: string, opts?: { isError?: boolean; isOk?: boolean }) => void
  onBackendChanged: () => void
  onRefresh: () => void
  onReloadGui: () => void
  onReinstall: () => void
  onHotReload: () => void
  onHotRestart: () => void
  onStop: () => void
}

export function Header({
  status,
  statusText,
  statusClass,
  flutterStatus,
  flutterStatusError,
  uiAction,
  busy,
  onFeedback,
  onBackendChanged,
  onRefresh,
  onReloadGui,
  onReinstall,
  onHotReload,
  onHotRestart,
  onStop,
}: HeaderProps) {
  const mode = status?.mode
  const debugMode = mode === 'debug'
  const profileMode = mode === 'profile'
  const hotReloadCapable = debugMode || profileMode
  const showFlutterControls =
    hotReloadCapable ||
    status?.flutterRunActive === true ||
    status?.canStopFlutter === true ||
    status?.deviceLogsEnabled === true

  return (
    <header className="app-header">
      <div className="header-top">
        <div className="app-brand">
          <h1>Isolate Monitor</h1>
          <code>{modeLabelText(mode)}</code>
          <BackendSwitch
            status={status}
            onFeedback={onFeedback}
            onChanged={onBackendChanged}
          />
        </div>
        <div className={`status ${statusClass}`}>{statusText}</div>
        <div className="header-actions">
          {showFlutterControls ? (
            <div className="flutter-controls">
              <button
                type="button"
                className={`button${busy.hotReload ? ' is-busy' : ''}`}
                disabled={
                  !hotReloadCapable || status?.canHotReload !== true || busy.hotReload
                }
                onClick={onHotReload}
                title={
                  profileMode
                    ? 'Hot reload via flutter run --profile (r)'
                    : 'Hot reload (r)'
                }
              >
                {busy.hotReload ? 'Reloading…' : 'Hot reload'}
              </button>
              <button
                type="button"
                className={`button secondary${busy.hotRestart ? ' is-busy' : ''}`}
                disabled={
                  !hotReloadCapable || status?.canHotRestart !== true || busy.hotRestart
                }
                onClick={onHotRestart}
                title={
                  profileMode
                    ? 'Hot restart via flutter run --profile (R)'
                    : 'Hot restart (R)'
                }
              >
                {busy.hotRestart ? 'Restarting…' : 'Hot restart'}
              </button>
              <button
                type="button"
                className={`button danger${busy.stop ? ' is-busy' : ''}`}
                disabled={status?.canStopFlutter !== true || busy.stop}
                onClick={onStop}
              >
                {busy.stop ? 'Stopping…' : 'Stop'}
              </button>
            </div>
          ) : null}
          <button
            type="button"
            className={`button secondary${busy.refresh ? ' is-busy' : ''}`}
            disabled={busy.refresh}
            onClick={onRefresh}
          >
            {busy.refresh ? 'Refreshing…' : 'Refresh UI'}
          </button>
          <button
            type="button"
            className={`button secondary${busy.reloadGui ? ' is-busy' : ''}`}
            title="Hard-reload this page after monitor UI changes"
            disabled={busy.reloadGui}
            onClick={onReloadGui}
          >
            {busy.reloadGui ? 'Reloading…' : 'Reload GUI'}
          </button>
          {status?.canReinstall ? (
            <button
              type="button"
              className={`button danger${busy.reinstall ? ' is-busy' : ''}`}
              disabled={status.reinstallRunning === true || busy.reinstall}
              onClick={onReinstall}
            >
              {busy.reinstall ? 'Reinstalling…' : reinstallButtonLabel(mode)}
            </button>
          ) : null}
        </div>
      </div>
      <div className="header-urls">
        <span>
          <strong>GUI:</strong> <code>{window.location.href}</code>
        </span>
        {status?.lanUrl ? (
          <span>
            <strong>LAN:</strong> <code>{status.lanUrl}</code>
          </span>
        ) : null}
        {status?.preferredBackend && status.preferredBackend !== status.backend ? (
          <span>
            <strong>Preferred server:</strong>{' '}
            <code>
              {status.preferredBackend} →{' '}
              {status.backendHint || `server/${status.preferredBackend}`}
            </code>
          </span>
        ) : null}
        {flutterStatus ? (
          <p className={`flutter-status${flutterStatusError ? ' error' : ''}`}>
            {flutterStatus}
          </p>
        ) : null}
        {uiAction.message ? (
          <p
            className={[
              'ui-action-status',
              uiAction.isError ? 'error' : '',
              uiAction.isOk ? 'ok' : '',
              uiAction.busy ? 'busy' : '',
            ]
              .filter(Boolean)
              .join(' ')}
            aria-live="polite"
          >
            {uiAction.message}
          </p>
        ) : null}
      </div>
    </header>
  )
}
