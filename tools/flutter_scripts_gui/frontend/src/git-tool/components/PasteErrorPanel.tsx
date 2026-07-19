import { useState } from 'react';

type Props = {
  onAnalyze: (raw: string) => void;
};

export function PasteErrorPanel({ onAnalyze }: Props) {
  const [raw, setRaw] = useState('');

  return (
    <div className="paste-panel">
      <h3>Paste a git / gh error</h3>
      <p className="summary">Paste terminal output, then Analyze to match a known issue.</p>
      <textarea
        value={raw}
        onChange={(e) => setRaw(e.target.value)}
        placeholder="Paste git status, push error, CONFLICT output, [gone], etc."
        rows={8}
      />
      <div className="row">
        <button type="button" className="btn" onClick={() => onAnalyze(raw)} disabled={!raw.trim()}>
          Analyze
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setRaw('')}>
          Clear
        </button>
      </div>
    </div>
  );
}
