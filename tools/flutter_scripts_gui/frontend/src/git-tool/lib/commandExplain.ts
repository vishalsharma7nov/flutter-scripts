/**
 * Fallback plain-English blurbs for common git/gh commands.
 * Used when a step does not set `what` on a CommandLine.
 */

const EXPLAIN: Array<{ match: RegExp; what: string }> = [
  {
    match: /^git\s+fetch\s+--prune\s+--dry-run/,
    what: 'Preview which stale remote-tracking branches would be removed — does not change anything.',
  },
  {
    match: /^git\s+fetch\s+--prune/,
    what: 'Download remote updates and delete local origin/* refs for branches already removed on GitHub.',
  },
  {
    match: /^git\s+fetch(\s+origin)?$/,
    what: 'Download new commits and branches from the remote without changing your working tree.',
  },
  {
    match: /^git\s+branch\s+-vv/,
    what: 'List local branches with upstream tracking and last commit (look for [gone]).',
  },
  {
    match: /^git\s+ls-remote/,
    what: 'Ask the remote which heads/tags exist — empty output means the branch is gone.',
  },
  {
    match: /^git\s+push\s+-u\s+origin\s+HEAD/,
    what: 'Push the current branch to origin and set it as the upstream for later push/pull.',
  },
  {
    match: /^git\s+push\s+--force-with-lease/,
    what: 'Force-update the remote branch only if nobody else pushed newer commits since your last fetch.',
  },
  {
    match: /^git\s+push\s+origin\s+--delete/,
    what: 'Delete a branch on the remote (GitHub), not locally.',
  },
  {
    match: /^git\s+push(\s+origin)?$/,
    what: 'Upload your local commits to the tracked remote branch.',
  },
  {
    match: /^git\s+status\s+-sb/,
    what: 'Short status: branch, ahead/behind, and a compact file list.',
  },
  {
    match: /^git\s+status$/,
    what: 'Show modified, staged, untracked files and whether you are mid-merge/rebase.',
  },
  {
    match: /^git\s+switch\s+-c/,
    what: 'Create a new branch from HEAD and check it out.',
  },
  {
    match: /^git\s+switch\s+-/,
    what: 'Switch back to the previous branch.',
  },
  {
    match: /^git\s+switch\b/,
    what: 'Check out another existing branch and update your working tree.',
  },
  {
    match: /^git\s+branch\s+-D/,
    what: 'Force-delete a local branch even if it is not fully merged.',
  },
  {
    match: /^git\s+branch\s+-d/,
    what: 'Delete a local branch if it is already merged (safer).',
  },
  {
    match: /^git\s+branch\s+--show-current/,
    what: 'Print the name of the branch you are on.',
  },
  {
    match: /^git\s+pull\s+--rebase/,
    what: 'Fetch remote commits, then replay your local commits on top.',
  },
  {
    match: /^git\s+pull\s+--no-rebase/,
    what: 'Fetch and merge remote commits into your branch (may create a merge commit).',
  },
  {
    match: /^git\s+pull\b/,
    what: 'Fetch from the remote and integrate into your current branch.',
  },
  {
    match: /^git\s+log\s+--oneline\s+--left-right/,
    what: 'Show commits unique to each side of a divergence (< remote, > local).',
  },
  {
    match: /^git\s+log\s+--oneline/,
    what: 'Compact commit history for quick inspection.',
  },
  {
    match: /^git\s+log\b.*HEAD\.\.@\{u\}/,
    what: 'Commits on the upstream that you do not have locally.',
  },
  {
    match: /^git\s+log\b.*@\{u\}\.\.HEAD/,
    what: 'Your local commits that are not on the upstream yet.',
  },
  {
    match: /^git\s+diff\s+--name-only\s+--diff-filter=U/,
    what: 'List only unmerged (conflicted) file paths.',
  },
  {
    match: /^git\s+diff$/,
    what: 'Show unstaged changes in your working tree.',
  },
  {
    match: /^git\s+add\s+-A/,
    what: 'Stage all new, modified, and deleted files for the next commit.',
  },
  {
    match: /^git\s+commit\s+--amend/,
    what: 'Rewrite the tip commit with new staged changes and/or a new message.',
  },
  {
    match: /^git\s+commit\b/,
    what: 'Create a new commit from what is currently staged.',
  },
  {
    match: /^git\s+rebase\s+--continue/,
    what: 'Continue an in-progress rebase after you resolved conflicts.',
  },
  {
    match: /^git\s+rebase\s+--abort/,
    what: 'Cancel the rebase and restore the branch to its pre-rebase state.',
  },
  {
    match: /^git\s+merge\s+--abort/,
    what: 'Cancel an in-progress merge and restore the pre-merge state.',
  },
  {
    match: /^git\s+stash\s+push/,
    what: 'Shelve your uncommitted changes (optionally including untracked files).',
  },
  {
    match: /^git\s+stash\s+pop/,
    what: 'Apply the newest stash and remove it from the stash list.',
  },
  {
    match: /^git\s+reset\s+--keep/,
    what: 'Move HEAD back while keeping your working-tree changes when safe.',
  },
  {
    match: /^git\s+rm\s+--cached/,
    what: 'Untrack a file from the index but leave it on disk.',
  },
  {
    match: /^git\s+remote\s+prune/,
    what: 'Remove stale remote-tracking branches for that remote.',
  },
  {
    match: /^git\s+remote\s+-v$/,
    what: 'List remotes and their fetch/push URLs.',
  },
  {
    match: /^gh\s+auth\s+status/,
    what: 'Show whether GitHub CLI is logged in and which account it uses.',
  },
  {
    match: /^gh\s+auth\s+login/,
    what: 'Interactively log GitHub CLI into a GitHub account.',
  },
  {
    match: /^gh\s+auth\s+setup-git/,
    what: 'Configure git to use GitHub CLI credentials for HTTPS remotes.',
  },
  {
    match: /^gh\s+pr\s+create/,
    what: 'Open a pull request for the current branch on GitHub.',
  },
  {
    match: /^ssh\s+-T\s+git@github\.com/,
    what: 'Test whether your SSH key authenticates to GitHub.',
  },
  {
    match: /^ssh-add\b/,
    what: 'Load your private SSH key into the agent (macOS keychain option keeps it unlocked).',
  },
]

export function explainCommand(cmd: string): string | undefined {
  const trimmed = cmd.trim()
  if (!trimmed || trimmed.startsWith('#')) return undefined
  for (const entry of EXPLAIN) {
    if (entry.match.test(trimmed)) return entry.what
  }
  return undefined
}
