import type { GuideStep } from './types'

export type { GuideStep } from './types'

export type GitIssue = {
  id: string
  title: string
  why: string
  keywords: string[]
  diagnose: GuideStep[]
  fix: GuideStep[]
}

export const gitIssues: GitIssue[] = [
  {
    id: 'remote-gone',
    title: 'Remote branch deleted / upstream [gone]',
    why: 'The branch was deleted on GitHub, but your local repo still tracks the old origin/BRANCH ref.',
    keywords: ['gone', 'deleted', '[deleted]', 'fetch --prune'],
    diagnose: [
      {
        title: 'See deleted remotes and [gone] upstreams',
        commands: [
          {
            cmd: 'git fetch --prune --dry-run',
            what: 'Preview stale remote-tracking branches that fetch --prune would remove.',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Refresh remotes and drop origin/* refs for branches deleted on GitHub.',
          },
          {
            cmd: 'git branch -vv',
            what: 'List local branches with upstreams — look for [gone].',
          },
          {
            cmd: 'git ls-remote --heads origin BRANCH_NAME',
            what: 'Ask GitHub if BRANCH_NAME still exists (empty output = gone).',
          },
        ],
        note: 'Empty `ls-remote` output means the remote branch does not exist.',
      },
    ],
    fix: [
      {
        title: 'If you still need the work: push a new remote branch',
        commands: [
          {
            cmd: 'git push -u origin HEAD',
            what: 'Recreate the remote branch from your current HEAD and set upstream.',
          },
        ],
      },
      {
        title: 'If the branch is finished: delete local branch',
        commands: [
          {
            cmd: 'git switch main',
            what: 'Move off the finished branch onto your default base branch.',
          },
          {
            cmd: 'git branch -D BRANCH_NAME',
            what: 'Force-delete the local branch that no longer has a remote.',
          },
        ],
        note: 'Replace `main` with your default base branch if different.',
      },
    ],
  },
  {
    id: 'ahead-of-gone',
    title: 'Local ahead of a deleted remote',
    why: 'You have local commits, but the remote tracking branch was removed (often after a PR merge + branch delete).',
    keywords: ['ahead', 'gone', 'has no upstream'],
    diagnose: [
      {
        title: 'Confirm ahead + gone',
        commands: [
          {
            cmd: 'git status -sb',
            what: 'Short status — shows ahead counts and missing upstream.',
          },
          {
            cmd: 'git branch -vv',
            what: 'Confirm the upstream is marked [gone].',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Sync remote-tracking refs so status matches GitHub.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Keep commits: recreate remote branch',
        commands: [
          {
            cmd: 'git push -u origin HEAD',
            what: 'Publish your local commits under a (new) remote branch name.',
          },
        ],
      },
      {
        title: 'Or move commits onto a new branch',
        commands: [
          {
            cmd: 'git switch -c backup/my-work',
            what: 'Create a backup branch pointing at your current commits.',
          },
          {
            cmd: 'git push -u origin backup/my-work',
            what: 'Push that backup branch to GitHub so the work is saved remotely.',
          },
        ],
      },
    ],
  },
  {
    id: 'stale-refs',
    title: 'Stale remote-tracking refs',
    why: 'Local `origin/*` refs are outdated until you fetch with prune.',
    keywords: ['stale', 'prune', 'remote-tracking'],
    diagnose: [
      {
        title: 'Dry-run prune',
        commands: [
          {
            cmd: 'git fetch --prune --dry-run',
            what: 'List which stale origin/* refs would be deleted.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Prune and refresh',
        commands: [
          {
            cmd: 'git fetch --prune',
            what: 'Fetch updates and remove deleted remote-tracking branches.',
          },
          {
            cmd: 'git remote prune origin',
            what: 'Extra cleanup of stale refs for origin if any remain.',
          },
        ],
      },
    ],
  },
  {
    id: 'push-rejected',
    title: 'Push rejected (non-fast-forward)',
    why: 'Remote has commits you do not have locally. A plain push would overwrite history.',
    keywords: ['rejected', 'non-fast-forward', 'fetch first', 'failed to push'],
    diagnose: [
      {
        title: 'Compare local vs remote',
        commands: [
          {
            cmd: 'git fetch origin',
            what: 'Download remote commits so you can compare histories.',
          },
          {
            cmd: 'git status -sb',
            what: 'See whether you are behind, ahead, or diverged.',
          },
          {
            cmd: 'git log --oneline HEAD..@{u}',
            what: 'Commits on upstream that you are missing.',
          },
          {
            cmd: 'git log --oneline @{u}..HEAD',
            what: 'Your local commits not yet on upstream.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Integrate remote then push',
        commands: [
          {
            cmd: 'git pull --rebase origin HEAD',
            what: 'Replay your commits on top of the remote tip.',
          },
          {
            cmd: 'git push',
            what: 'Upload the rebased history now that it is fast-forwardable.',
          },
        ],
        note: 'Prefer rebase for linear history; use `git pull` (merge) if that is team policy.',
      },
      {
        title: 'Only if you intentionally rewrote a personal branch',
        commands: [
          {
            cmd: 'git push --force-with-lease',
            what: 'Overwrite the remote branch safely if nobody else pushed meanwhile.',
          },
        ],
        warning: 'Never force-push to main/master or other protected shared branches.',
      },
    ],
  },
  {
    id: 'merge-conflicts',
    title: 'Merge or rebase conflicts',
    why: 'The same lines were changed on both sides and Git cannot auto-merge them.',
    keywords: ['conflict', 'CONFLICT', 'merge failed', 'fix conflicts', 'unmerged paths'],
    diagnose: [
      {
        title: 'List conflicted files',
        commands: [
          {
            cmd: 'git status',
            what: 'Shows unmerged paths that still need manual resolution.',
          },
          {
            cmd: 'git diff --name-only --diff-filter=U',
            what: 'Print only conflicted file paths.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Resolve, stage, continue',
        commands: [
          {
            cmd: '# edit files and remove conflict markers',
            what: 'Open each file and pick the correct combined content.',
          },
          {
            cmd: 'git add -A',
            what: 'Mark conflicts resolved by staging the fixed files.',
          },
          {
            cmd: '# merge:',
            what: 'If you were merging, finish with a commit next.',
          },
          {
            cmd: 'git commit',
            what: 'Completes the merge after conflicts are resolved.',
          },
          {
            cmd: '# rebase:',
            what: 'If you were rebasing, continue replaying commits.',
          },
          {
            cmd: 'git rebase --continue',
            what: 'Resumes the rebase after staged resolutions.',
          },
        ],
      },
      {
        title: 'Abort if needed',
        commands: [
          {
            cmd: 'git merge --abort',
            what: 'Cancel an in-progress merge and restore pre-merge state.',
          },
          {
            cmd: '# or',
            what: 'Use the rebase abort if that is the operation in progress.',
          },
          {
            cmd: 'git rebase --abort',
            what: 'Cancel an in-progress rebase and restore pre-rebase state.',
          },
        ],
      },
    ],
  },
  {
    id: 'detached-head',
    title: 'Detached HEAD',
    why: 'You checked out a commit/tag directly, so new commits are not on a branch.',
    keywords: ['detached HEAD', "You are in 'detached HEAD' state"],
    diagnose: [
      {
        title: 'Confirm state',
        commands: [
          {
            cmd: 'git status',
            what: 'Status line will say you are in a detached HEAD state.',
          },
          {
            cmd: 'git branch -vv',
            what: 'See which named branches exist to switch back to.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Keep work on a new branch',
        commands: [
          {
            cmd: 'git switch -c recovery/my-work',
            what: 'Create a branch at the detached commit so new work is saved.',
          },
        ],
      },
      {
        title: 'Or return to a branch without keeping detached commits',
        commands: [
          {
            cmd: 'git switch main',
            what: 'Leave detached HEAD and return to main (replace if needed).',
          },
        ],
      },
    ],
  },
  {
    id: 'auth-failed',
    title: 'Authentication / HTTPS / SSH failure',
    why: 'GitHub rejected credentials or your SSH key is not loaded / linked.',
    keywords: [
      'authentication failed',
      'Permission denied',
      'could not read Username',
      'publickey',
      '403',
    ],
    diagnose: [
      {
        title: 'Check remote and auth',
        commands: [
          {
            cmd: 'git remote -v',
            what: 'See whether origin uses HTTPS or SSH and which host/org/repo.',
          },
          {
            cmd: 'gh auth status',
            what: 'Show whether GitHub CLI is logged in and which account.',
          },
          {
            cmd: 'ssh -T git@github.com',
            what: 'Test SSH authentication to GitHub.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'HTTPS via GitHub CLI',
        commands: [
          {
            cmd: 'gh auth login',
            what: 'Log GitHub CLI into an account (HTTPS or SSH flow).',
          },
          {
            cmd: 'gh auth setup-git',
            what: 'Point git HTTPS remotes at GitHub CLI credentials.',
          },
        ],
      },
      {
        title: 'SSH',
        commands: [
          {
            cmd: 'ssh-add --apple-use-keychain ~/.ssh/id_ed25519',
            what: 'Load your SSH key into the agent and store it in macOS keychain.',
          },
          {
            cmd: 'ssh -T git@github.com',
            what: 'Confirm GitHub accepts the loaded key.',
          },
        ],
        note: 'Ensure the public key is added in GitHub → Settings → SSH keys.',
      },
    ],
  },
  {
    id: 'checkout-blocked',
    title: 'Uncommitted changes blocking checkout',
    why: 'Switching branches would overwrite local modifications.',
    keywords: ['Please commit your changes', 'would be overwritten', 'local changes'],
    diagnose: [
      {
        title: 'See blocking changes',
        commands: [
          {
            cmd: 'git status',
            what: 'Lists modified/untracked files blocking the switch.',
          },
          {
            cmd: 'git diff',
            what: 'Shows the unstaged content that would be overwritten.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Save work then switch',
        commands: [
          {
            cmd: 'git stash push -u -m "wip"',
            what: 'Shelve tracked + untracked changes so the tree is clean.',
          },
          {
            cmd: 'git switch OTHER_BRANCH',
            what: 'Switch branches now that nothing blocks checkout.',
          },
          {
            cmd: 'git stash pop',
            what: 'Restore the shelved work on the new branch.',
          },
        ],
      },
      {
        title: 'Or commit first',
        commands: [
          {
            cmd: 'git add -A',
            what: 'Stage everything you want to keep.',
          },
          {
            cmd: 'git commit -m "WIP"',
            what: 'Create a WIP commit so checkout can proceed.',
          },
          {
            cmd: 'git switch OTHER_BRANCH',
            what: 'Switch after committing.',
          },
        ],
      },
    ],
  },
  {
    id: 'diverged',
    title: 'Diverged branches after pull',
    why: 'Local and remote each have unique commits; histories forked.',
    keywords: ['diverged', 'have diverged', 'respectively'],
    diagnose: [
      {
        title: 'Inspect divergence',
        commands: [
          {
            cmd: 'git status -sb',
            what: 'Shows ahead/behind counts when histories diverged.',
          },
          {
            cmd: 'git log --oneline --left-right HEAD...@{u}',
            what: 'List commits unique to each side (< remote, > local).',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Rebase local onto remote',
        commands: [
          {
            cmd: 'git pull --rebase',
            what: 'Replay your commits on top of the remote branch.',
          },
        ],
      },
      {
        title: 'Or merge remote into local',
        commands: [
          {
            cmd: 'git pull --no-rebase',
            what: 'Create a merge commit combining both histories.',
          },
        ],
      },
    ],
  },
  {
    id: 'wrong-branch-commit',
    title: 'Accidental commit on wrong branch',
    why: 'Commits landed on main/dev (or another branch) by mistake.',
    keywords: ['wrong branch', 'committed to main'],
    diagnose: [
      {
        title: 'Confirm where you are',
        commands: [
          {
            cmd: 'git branch --show-current',
            what: 'Print the branch that currently contains your commits.',
          },
          {
            cmd: 'git log --oneline -5',
            what: 'Inspect the last few commits you may need to move.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Move last commit(s) to a new branch',
        commands: [
          {
            cmd: 'git switch -c feature/correct-branch',
            what: 'Create the intended feature branch at the mistaken commit(s).',
          },
          {
            cmd: 'git switch main',
            what: 'Return to the branch that should not keep those commits.',
          },
          {
            cmd: 'git reset --keep HEAD~1',
            what: 'Drop the last commit from main while keeping file changes when safe.',
          },
          {
            cmd: 'git switch feature/correct-branch',
            what: 'Continue working on the correct branch.',
          },
        ],
        warning:
          'Only reset main if those commits were not pushed, or coordinate with the team.',
      },
    ],
  },
  {
    id: 'hook-rejected',
    title: 'Hook or large file rejected push',
    why: 'A pre-push / pre-receive hook blocked the push (secrets, large files, lint).',
    keywords: ['hook declined', 'pre-receive', 'GH001', 'large files', 'file is too large'],
    diagnose: [
      {
        title: 'Read the hook message and recent commits',
        commands: [
          {
            cmd: 'git status',
            what: 'Confirm clean/dirty state before rewriting history.',
          },
          {
            cmd: 'git log --oneline -5',
            what: 'Find which recent commit likely introduced the blocked file.',
          },
          {
            cmd: 'git rev-list --objects --all | git cat-file --batch-check',
            what: 'Advanced size inspection of objects (useful for large-file hunts).',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Remove the offending file from history (simplified)',
        commands: [
          {
            cmd: '# Prefer fixing the latest commit if not pushed widely:',
            what: 'Safer when the bad file is only in the tip commit.',
          },
          {
            cmd: 'git rm --cached path/to/large-or-secret-file',
            what: 'Stop tracking the file while leaving it on disk.',
          },
          {
            cmd: 'git commit --amend',
            what: 'Rewrite the tip commit without the blocked file.',
          },
          {
            cmd: 'git push',
            what: 'Retry the push after the fix.',
          },
        ],
        warning:
          'Rewriting older history needs a careful filter-repo / BFG workflow and team coordination.',
      },
    ],
  },
  {
    id: 'gh-pr-failed',
    title: 'gh PR create failed',
    why: 'GitHub CLI is not authenticated, or the branch has no upstream / remote.',
    keywords: [
      'gh pr create',
      'not logged into',
      'no pull requests found',
      'must be pushed',
    ],
    diagnose: [
      {
        title: 'Check gh + upstream',
        commands: [
          {
            cmd: 'gh auth status',
            what: 'Confirm gh is logged in to the right GitHub account.',
          },
          {
            cmd: 'git status -sb',
            what: 'See whether the branch has an upstream set.',
          },
          {
            cmd: 'git remote -v',
            what: 'Confirm origin points at the intended GitHub repo.',
          },
        ],
      },
    ],
    fix: [
      {
        title: 'Auth, push, create',
        commands: [
          {
            cmd: 'gh auth login',
            what: 'Authenticate GitHub CLI if needed.',
          },
          {
            cmd: 'git push -u origin HEAD',
            what: 'Publish the branch so a PR can target it.',
          },
          {
            cmd: 'gh pr create',
            what: 'Open the pull request interactively (or with flags).',
          },
        ],
      },
    ],
  },
]

export function findIssueById(id: string): GitIssue | undefined {
  return gitIssues.find((issue) => issue.id === id)
}
