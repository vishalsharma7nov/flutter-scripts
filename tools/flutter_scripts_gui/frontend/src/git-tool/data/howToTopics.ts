import type { GuideStep } from './types'

export type { GuideStep, CommandLine } from './types'

export type HowToTopic = {
  id: string
  category: string
  title: string
  summary: string
  steps: GuideStep[]
}

export const howToTopics: HowToTopic[] = [
  {
    id: 'clone',
    category: 'Start',
    title: 'Clone a repository',
    summary: 'Download a GitHub repo to your machine for the first time.',
    steps: [
      {
        title: 'Clone with HTTPS',
        commands: [
          {
            cmd: 'git clone https://github.com/ORG/REPO.git',
            what: 'Copies the remote repository into a new local folder named REPO.',
          },
          {
            cmd: 'cd REPO',
            what: 'Enters the cloned project so later git commands apply there.',
          },
        ],
      },
      {
        title: 'Clone with SSH (if keys are set up)',
        commands: [
          {
            cmd: 'git clone git@github.com:ORG/REPO.git',
            what: 'Same as HTTPS clone, but authenticates with your SSH key.',
          },
          {
            cmd: 'cd REPO',
            what: 'Move into the new local repo.',
          },
        ],
      },
    ],
  },
  {
    id: 'init-remote',
    category: 'Start',
    title: 'Init repo and add first remote',
    summary: 'Turn a local folder into a git repo and connect it to GitHub.',
    steps: [
      {
        title: 'Initialize and commit',
        commands: [
          {
            cmd: 'git init',
            what: 'Creates a new .git directory — this folder becomes a repository.',
          },
          {
            cmd: 'git add .',
            what: 'Stages all current files for the first commit.',
          },
          {
            cmd: 'git commit -m "Initial commit"',
            what: 'Records the staged files as the first snapshot in history.',
          },
        ],
      },
      {
        title: 'Add origin and push',
        commands: [
          {
            cmd: 'git remote add origin https://github.com/ORG/REPO.git',
            what: 'Registers GitHub as the remote named origin (where you push/pull).',
          },
          {
            cmd: 'git branch -M main',
            what: 'Renames the current branch to main (common default).',
          },
          {
            cmd: 'git push -u origin main',
            what: 'Uploads main to GitHub and sets upstream tracking for future git push/pull.',
          },
        ],
      },
    ],
  },
  {
    id: 'config-user',
    category: 'Start',
    title: 'Configure user.name / user.email',
    summary: 'Set the identity used on your commits.',
    steps: [
      {
        title: 'Set for this repo only',
        commands: [
          {
            cmd: 'git config user.name "Your Name"',
            what: 'Sets the author name for commits in this repository only.',
          },
          {
            cmd: 'git config user.email "you@example.com"',
            what: 'Sets the author email for commits in this repository only.',
          },
        ],
      },
      {
        title: 'Set globally (all repos)',
        commands: [
          {
            cmd: 'git config --global user.name "Your Name"',
            what: 'Default author name for every repo on this machine (unless overridden locally).',
          },
          {
            cmd: 'git config --global user.email "you@example.com"',
            what: 'Default author email for every repo on this machine.',
          },
        ],
      },
    ],
  },
  {
    id: 'status',
    category: 'Daily',
    title: 'Check status',
    summary: 'See what is modified, staged, or untracked.',
    steps: [
      {
        title: 'Working tree status',
        commands: [
          {
            cmd: 'git status',
            what: 'Shows modified, staged, and untracked files in a detailed view.',
          },
          {
            cmd: 'git status -sb',
            what: 'Short one-line-per-file status plus branch ahead/behind info.',
          },
        ],
      },
    ],
  },
  {
    id: 'commit',
    category: 'Daily',
    title: 'Add and commit',
    summary: 'Stage changes and create a commit.',
    steps: [
      {
        title: 'Stage and commit',
        commands: [
          {
            cmd: 'git add -A',
            what: 'Stages all changes in the repo (new, modified, and deleted files).',
          },
          {
            cmd: 'git commit -m "Describe why this change exists."',
            what: 'Creates a new commit from the staged snapshot with your message.',
          },
        ],
      },
      {
        title: 'Stage specific files',
        commands: [
          {
            cmd: 'git add path/to/file.dart',
            what: 'Stages only the listed file(s) for the next commit.',
          },
          {
            cmd: 'git commit -m "Describe why this change exists."',
            what: 'Commits just what you staged.',
          },
        ],
      },
    ],
  },
  {
    id: 'amend',
    category: 'Daily',
    title: 'Amend last commit (safe rules)',
    summary:
      'Fix the last commit message or add forgotten files — only if not pushed, or if you own the branch.',
    steps: [
      {
        title: 'Amend message or staged files',
        commands: [
          {
            cmd: 'git add -A',
            what: 'Stage any forgotten fixes you want included in the last commit.',
          },
          {
            cmd: 'git commit --amend',
            what: 'Rewrites the latest commit (message and/or tree) instead of creating a new one.',
          },
        ],
        warning:
          'Do not amend commits already pushed to a shared branch like main/dev unless the team agrees.',
      },
    ],
  },
  {
    id: 'stash',
    category: 'Daily',
    title: 'Stash and restore WIP',
    summary: 'Temporarily shelve uncommitted work to switch branches cleanly.',
    steps: [
      {
        title: 'Stash including untracked',
        commands: [
          {
            cmd: 'git stash push -u -m "wip"',
            what: 'Saves tracked + untracked changes onto a stash stack and cleans the working tree.',
          },
          {
            cmd: 'git stash list',
            what: 'Lists stashes so you can see what you saved.',
          },
        ],
      },
      {
        title: 'Restore latest stash',
        commands: [
          {
            cmd: 'git stash pop',
            what: 'Applies the newest stash and removes it from the stash list.',
          },
        ],
        note: 'Use `git stash apply` if you want to keep the stash entry.',
      },
    ],
  },
  {
    id: 'discard',
    category: 'Daily',
    title: 'Discard local changes',
    summary: 'Throw away uncommitted edits (destructive).',
    steps: [
      {
        title: 'Discard tracked file changes',
        commands: [
          {
            cmd: 'git restore path/to/file',
            what: 'Reverts that file’s uncommitted edits back to the last commit.',
          },
          {
            cmd: 'git restore .',
            what: 'Reverts all tracked files in the current directory tree to HEAD.',
          },
        ],
        warning: 'This permanently discards uncommitted work on tracked files.',
      },
      {
        title: 'Remove untracked files (careful)',
        commands: [
          {
            cmd: 'git clean -nd',
            what: 'Dry-run: lists untracked files/folders that would be deleted (safe preview).',
          },
          {
            cmd: 'git clean -fd',
            what: 'Deletes untracked files and directories. Irreversible.',
          },
        ],
        warning:
          '`git clean -fd` deletes untracked files/folders. Preview with `-n` first.',
      },
    ],
  },
  {
    id: 'fetch',
    category: 'Sync',
    title: 'Fetch remote updates',
    summary: 'Download remote commits without changing your working tree.',
    steps: [
      {
        title: 'Fetch and prune deleted remotes',
        commands: [
          {
            cmd: 'git fetch origin',
            what: 'Downloads new commits/branches from origin into remote-tracking refs (no merge).',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Fetches and removes local origin/* refs for branches deleted on GitHub.',
          },
        ],
      },
    ],
  },
  {
    id: 'pull-merge',
    category: 'Sync',
    title: 'Pull (merge)',
    summary: 'Update your branch by merging remote changes.',
    steps: [
      {
        title: 'Pull with merge',
        commands: [
          {
            cmd: 'git pull origin HEAD',
            what: 'Fetches the remote branch and merges it into your current branch.',
          },
        ],
        note: 'Or `git pull` if upstream is set.',
      },
    ],
  },
  {
    id: 'pull-rebase',
    category: 'Sync',
    title: 'Pull with rebase',
    summary: 'Replay your local commits on top of the remote branch.',
    steps: [
      {
        title: 'Pull --rebase',
        commands: [
          {
            cmd: 'git pull --rebase origin HEAD',
            what: 'Fetches remote commits, then replays your local commits on top (linear history).',
          },
        ],
      },
      {
        title: 'If conflicts appear',
        commands: [
          {
            cmd: 'git status',
            what: 'Shows which files still have conflicts to resolve.',
          },
          {
            cmd: '# fix files, then:',
            what: 'Edit conflict markers in those files, then continue.',
          },
          {
            cmd: 'git add -A',
            what: 'Marks conflicts as resolved by staging the fixed files.',
          },
          {
            cmd: 'git rebase --continue',
            what: 'Continues the rebase after you resolved conflicts.',
          },
        ],
        note: 'Abort with `git rebase --abort`.',
      },
    ],
  },
  {
    id: 'push',
    category: 'Sync',
    title: 'Push commits',
    summary: 'Publish local commits to GitHub.',
    steps: [
      {
        title: 'Push current branch',
        commands: [
          {
            cmd: 'git push',
            what: 'Uploads your local commits to the tracked remote branch.',
          },
        ],
      },
      {
        title: 'First push (set upstream)',
        commands: [
          {
            cmd: 'git push -u origin HEAD',
            what: 'Creates/updates the remote branch and remembers it as upstream for later pushes.',
          },
        ],
      },
    ],
  },
  {
    id: 'set-upstream',
    category: 'Sync',
    title: 'Set upstream tracking',
    summary: 'Link your local branch to a remote branch.',
    steps: [
      {
        title: 'Track origin branch',
        commands: [
          {
            cmd: 'git branch -u origin/BRANCH_NAME',
            what: 'Sets which remote branch `git pull` / `git push` / status ahead-behind use.',
          },
          {
            cmd: 'git status -sb',
            what: 'Confirms the branch now shows its upstream and ahead/behind counts.',
          },
        ],
      },
    ],
  },
  {
    id: 'branch-create',
    category: 'Branches',
    title: 'Create a branch',
    summary: 'Start new work on a feature/bugfix branch.',
    steps: [
      {
        title: 'Create and switch',
        commands: [
          {
            cmd: 'git switch -c feature/my-change',
            what: 'Creates a new branch from HEAD and checks it out immediately.',
          },
        ],
        note: 'Older equivalent: `git checkout -b feature/my-change`.',
      },
    ],
  },
  {
    id: 'branch-switch',
    category: 'Branches',
    title: 'Switch branches',
    summary: 'Move between existing branches.',
    steps: [
      {
        title: 'Switch',
        commands: [
          {
            cmd: 'git switch BRANCH_NAME',
            what: 'Checks out an existing branch and updates your working tree to match.',
          },
          {
            cmd: 'git switch -',
            what: 'Jumps back to the branch you were on previously.',
          },
        ],
        note: '`git switch -` returns to the previous branch.',
      },
    ],
  },
  {
    id: 'branch-list',
    category: 'Branches',
    title: 'List local and remote branches',
    summary: 'See what exists locally and on origin.',
    steps: [
      {
        title: 'List',
        commands: [
          {
            cmd: 'git branch -vv',
            what: 'Lists local branches with upstream tracking and last commit.',
          },
          {
            cmd: 'git branch -r',
            what: 'Lists remote-tracking branches (origin/…).',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Refreshes remotes and drops refs for deleted remote branches.',
          },
        ],
      },
    ],
  },
  {
    id: 'branch-rename',
    category: 'Branches',
    title: 'Rename a branch',
    summary: 'Rename the current or another local branch.',
    steps: [
      {
        title: 'Rename current branch',
        commands: [
          {
            cmd: 'git branch -m new-name',
            what: 'Renames the branch you are currently on.',
          },
        ],
      },
      {
        title: 'If already pushed, update remote',
        commands: [
          {
            cmd: 'git push -u origin new-name',
            what: 'Publishes the new branch name and sets it as upstream.',
          },
          {
            cmd: 'git push origin --delete old-name',
            what: 'Removes the old branch name from GitHub.',
          },
        ],
        warning: 'Coordinate with teammates before deleting the old remote name.',
      },
    ],
  },
  {
    id: 'branch-delete-local',
    category: 'Branches',
    title: 'Delete local branch',
    summary: 'Remove a finished local branch.',
    steps: [
      {
        title: 'Delete merged branch',
        commands: [
          {
            cmd: 'git branch -d BRANCH_NAME',
            what: 'Deletes a local branch only if it is fully merged (safe).',
          },
        ],
      },
      {
        title: 'Force delete unmerged',
        commands: [
          {
            cmd: 'git branch -D BRANCH_NAME',
            what: 'Force-deletes the local branch even if commits would be lost.',
          },
        ],
        warning: '`-D` drops unmerged commits on that branch.',
      },
    ],
  },
  {
    id: 'branch-delete-remote',
    category: 'Branches',
    title: 'Delete remote branch',
    summary: 'Remove a branch from GitHub.',
    steps: [
      {
        title: 'Delete on origin',
        commands: [
          {
            cmd: 'git push origin --delete BRANCH_NAME',
            what: 'Deletes the branch on GitHub (not your local branch).',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Cleans up the leftover origin/BRANCH_NAME tracking ref locally.',
          },
        ],
      },
    ],
  },
  {
    id: 'merge',
    category: 'Integrate',
    title: 'Merge a branch into current',
    summary: 'Combine another branch into the branch you are on.',
    steps: [
      {
        title: 'Update and merge',
        commands: [
          {
            cmd: 'git fetch origin',
            what: 'Updates remote-tracking refs before you merge.',
          },
          {
            cmd: 'git merge OTHER_BRANCH',
            what: 'Brings OTHER_BRANCH’s commits into your current branch (may create a merge commit).',
          },
        ],
      },
      {
        title: 'Abort an in-progress merge',
        commands: [
          {
            cmd: 'git merge --abort',
            what: 'Cancels a merge with conflicts and restores the pre-merge state.',
          },
        ],
      },
    ],
  },
  {
    id: 'rebase',
    category: 'Integrate',
    title: 'Rebase onto main/dev',
    summary: 'Replay your commits on top of an updated base branch.',
    steps: [
      {
        title: 'Rebase onto updated base',
        commands: [
          {
            cmd: 'git fetch origin',
            what: 'Gets the latest base branch commits from GitHub.',
          },
          {
            cmd: 'git rebase origin/dev',
            what: 'Replays your branch commits onto origin/dev one by one.',
          },
        ],
        note: 'Replace `dev` with your base branch (`main`, etc.).',
      },
      {
        title: 'Abort rebase',
        commands: [
          {
            cmd: 'git rebase --abort',
            what: 'Cancels the rebase and returns the branch to how it was before.',
          },
        ],
      },
      {
        title: 'After rebase of a published branch',
        commands: [
          {
            cmd: 'git push --force-with-lease',
            what: 'Updates the remote branch after rewrite — refuses if someone else pushed newer commits.',
          },
        ],
        warning: 'Never force-push to main/master/shared protected branches.',
      },
    ],
  },
  {
    id: 'resolve-conflicts',
    category: 'Integrate',
    title: 'Resolve merge/rebase conflicts',
    summary: 'Fix conflicted files, then continue the operation.',
    steps: [
      {
        title: 'Find and fix conflicts',
        commands: [
          {
            cmd: 'git status',
            what: 'Lists unmerged (conflicted) paths that still need edits.',
          },
          {
            cmd: '# edit conflicted files, remove <<<<<<<< markers',
            what: 'Manually choose the correct combined content in each conflicted file.',
          },
          {
            cmd: 'git add -A',
            what: 'Stages resolved files so git knows conflicts are done.',
          },
        ],
      },
      {
        title: 'Continue',
        commands: [
          {
            cmd: '# if merging:',
            what: 'For a merge, finish with a merge commit next.',
          },
          {
            cmd: 'git commit',
            what: 'Completes the merge after conflicts are resolved.',
          },
          {
            cmd: '# if rebasing:',
            what: 'For a rebase, continue replaying remaining commits.',
          },
          {
            cmd: 'git rebase --continue',
            what: 'Resumes the rebase after you staged conflict resolutions.',
          },
        ],
      },
    ],
  },
  {
    id: 'pr-create',
    category: 'GitHub',
    title: 'Create a pull request',
    summary: 'Open a PR with GitHub CLI after pushing your branch.',
    steps: [
      {
        title: 'Push and create PR',
        commands: [
          {
            cmd: 'git push -u origin HEAD',
            what: 'Publishes your branch so GitHub can open a PR against it.',
          },
          {
            cmd: 'gh pr create --title "Short title" --body "$(cat <<\'EOF\'\n## Summary\n- \n\n## Test plan\n- [ ] \nEOF\n)"',
            what: 'Opens a pull request on GitHub with title and markdown body.',
          },
        ],
        note: 'Requires `gh auth login` once.',
      },
    ],
  },
  {
    id: 'pr-status',
    category: 'GitHub',
    title: 'Check PR status',
    summary: 'Inspect the PR for the current branch.',
    steps: [
      {
        title: 'View PR',
        commands: [
          {
            cmd: 'gh pr status',
            what: 'Shows PR state, checks, and review status for your current branch.',
          },
          {
            cmd: 'gh pr view --web',
            what: 'Opens the PR page in the browser.',
          },
        ],
      },
    ],
  },
  {
    id: 'pr-checkout',
    category: 'GitHub',
    title: 'Check out a PR branch',
    summary: 'Locally review someone else’s PR.',
    steps: [
      {
        title: 'Checkout by PR number',
        commands: [
          {
            cmd: 'gh pr checkout 123',
            what: 'Fetches the PR branch and switches your local repo onto it.',
          },
        ],
      },
    ],
  },
  {
    id: 'sync-fork',
    category: 'GitHub',
    title: 'Sync a fork',
    summary: 'Update your fork from the upstream repository.',
    steps: [
      {
        title: 'Add upstream and merge',
        commands: [
          {
            cmd: 'git remote add upstream https://github.com/UPSTREAM_ORG/REPO.git',
            what: 'Adds the original repo as a second remote named upstream.',
          },
          {
            cmd: 'git fetch upstream',
            what: 'Downloads the latest commits from the upstream remote.',
          },
          {
            cmd: 'git switch main',
            what: 'Checks out your fork’s main branch locally.',
          },
          {
            cmd: 'git merge upstream/main',
            what: 'Merges upstream’s main into your local main.',
          },
          {
            cmd: 'git push origin main',
            what: 'Updates your GitHub fork so it matches upstream.',
          },
        ],
        note: 'Skip `remote add` if upstream already exists (`git remote -v`).',
      },
    ],
  },
  {
    id: 'remotes',
    category: 'Remotes',
    title: 'List and change remotes',
    summary: 'Inspect or update the GitHub remote URL.',
    steps: [
      {
        title: 'List remotes',
        commands: [
          {
            cmd: 'git remote -v',
            what: 'Shows remote names and their fetch/push URLs.',
          },
        ],
      },
      {
        title: 'Change origin URL',
        commands: [
          {
            cmd: 'git remote set-url origin https://github.com/ORG/REPO.git',
            what: 'Points origin at a different GitHub URL (HTTPS or SSH).',
          },
          {
            cmd: 'git remote -v',
            what: 'Verifies the URL change took effect.',
          },
        ],
      },
    ],
  },
  {
    id: 'prune-remotes',
    category: 'Remotes',
    title: 'Prune deleted remote branches',
    summary: 'Clean stale origin/* refs after branches were deleted on GitHub.',
    steps: [
      {
        title: 'Dry-run then prune',
        commands: [
          {
            cmd: 'git fetch --prune --dry-run',
            what: 'Preview which stale remote-tracking branches would be removed.',
          },
          {
            cmd: 'git fetch --prune',
            what: 'Actually deletes those stale origin/* refs locally.',
          },
          {
            cmd: 'git branch -vv',
            what: 'Confirm local branches no longer track deleted remotes (or show [gone]).',
          },
        ],
      },
    ],
  },
  {
    id: 'tags',
    category: 'Tags / release',
    title: 'Create and push tags',
    summary: 'Mark a release commit with an annotated tag.',
    steps: [
      {
        title: 'Create and push',
        commands: [
          {
            cmd: 'git tag -a v1.2.3 -m "Release v1.2.3"',
            what: 'Creates an annotated tag on the current commit (preferred for releases).',
          },
          {
            cmd: 'git push origin v1.2.3',
            what: 'Publishes that single tag to GitHub.',
          },
          {
            cmd: 'git push origin --tags',
            what: 'Pushes all local tags that are missing on the remote.',
          },
        ],
      },
      {
        title: 'Delete tag',
        commands: [
          {
            cmd: 'git tag -d v1.2.3',
            what: 'Deletes the tag from your local repo only.',
          },
          {
            cmd: 'git push origin --delete v1.2.3',
            what: 'Deletes the same tag from GitHub.',
          },
        ],
      },
    ],
  },
  {
    id: 'history',
    category: 'History',
    title: 'Inspect history',
    summary: 'Read-only views of commits and authorship.',
    steps: [
      {
        title: 'Log and show',
        commands: [
          {
            cmd: 'git log --oneline --graph --decorate -20',
            what: 'Shows the last 20 commits as a compact commit graph.',
          },
          {
            cmd: 'git show HEAD',
            what: 'Displays the latest commit’s message and full diff.',
          },
          {
            cmd: 'git blame path/to/file',
            what: 'Shows which commit/author last touched each line of a file.',
          },
        ],
      },
    ],
  },
  {
    id: 'reset',
    category: 'History',
    title: 'Reset commits (careful)',
    summary: 'Move HEAD backward. Prefer soft/mixed for local-only commits.',
    steps: [
      {
        title: 'Undo commit, keep changes staged',
        commands: [
          {
            cmd: 'git reset --soft HEAD~1',
            what: 'Removes the last commit but leaves its changes staged — ready to recommit.',
          },
        ],
      },
      {
        title: 'Undo commit, keep changes unstaged',
        commands: [
          {
            cmd: 'git reset --mixed HEAD~1',
            what: 'Removes the last commit and unstages its changes (files stay on disk).',
          },
        ],
        warning:
          'Never reset shared history on main/master. Avoid `git reset --hard` unless you intend to discard work.',
      },
    ],
  },
]

export function howToCategories(topics: HowToTopic[] = howToTopics): string[] {
  return [...new Set(topics.map((t) => t.category))]
}
