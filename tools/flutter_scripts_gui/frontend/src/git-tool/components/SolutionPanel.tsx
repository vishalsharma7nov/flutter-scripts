import { useState } from 'react';
import type { GitIssue } from '../data/issues';
import { StepsList } from './CommandBlock';

type Props = {
  issue: GitIssue;
};

export function SolutionPanel({ issue }: Props) {
  const [showFix, setShowFix] = useState(false);

  return (
    <article className="detail-panel">
      <header>
        <p className="eyebrow">Troubleshoot</p>
        <h2>{issue.title}</h2>
        <p className="summary">
          <strong>Why: </strong>
          {issue.why}
        </p>
      </header>

      <section>
        <div className="row between">
          <h3>1. Diagnose</h3>
          <button type="button" className="btn" onClick={() => setShowFix(true)}>
            Show solution
          </button>
        </div>
        <p className="summary">Run these first to confirm the problem.</p>
        <StepsList steps={issue.diagnose} />
      </section>

      {showFix ? (
        <section>
          <h3>2. Solution</h3>
          <StepsList steps={issue.fix} />
        </section>
      ) : (
        <p className="hint">Tap Show solution after you have run the diagnose commands.</p>
      )}
    </article>
  );
}
