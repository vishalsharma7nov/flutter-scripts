import { gitIssues, type GitIssue } from '../data/issues';

/** Match pasted terminal output to the best issue (highest keyword hits). */
export function matchErrorToIssue(raw: string): GitIssue | null {
  const text = raw.trim().toLowerCase();
  if (!text) return null;

  let best: { issue: GitIssue; score: number } | null = null;

  for (const issue of gitIssues) {
    let score = 0;
    for (const keyword of issue.keywords) {
      if (text.includes(keyword.toLowerCase())) {
        score += keyword.length > 8 ? 2 : 1;
      }
    }
    if (score > 0 && (!best || score > best.score)) {
      best = { issue, score };
    }
  }

  return best?.issue ?? null;
}
