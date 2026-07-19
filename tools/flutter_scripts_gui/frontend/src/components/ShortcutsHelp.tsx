type Props = {
  open: boolean
  onClose: () => void
}

export function ShortcutsHelp({ open, onClose }: Props) {
  if (!open) return null
  return (
    <div className="modal-backdrop" role="presentation" onClick={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-labelledby="shortcuts-title"
        onClick={(e) => e.stopPropagation()}
      >
        <header className="modal-header">
          <h2 id="shortcuts-title">Keyboard shortcuts</h2>
          <button type="button" onClick={onClose} aria-label="Close">
            Close
          </button>
        </header>
        <dl className="shortcut-list">
          <div>
            <dt>↑ / ↓</dt>
            <dd>Move script selection in the filtered list</dd>
          </div>
          <div>
            <dt>Enter</dt>
            <dd>Run the selected script (from the filter box)</dd>
          </div>
          <div>
            <dt>?</dt>
            <dd>Toggle this shortcuts sheet</dd>
          </div>
          <div>
            <dt>Esc</dt>
            <dd>Stop a running script (when the Scripts page is active)</dd>
          </div>
        </dl>
      </div>
    </div>
  )
}
