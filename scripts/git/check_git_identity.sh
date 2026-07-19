#!/usr/bin/env bash
#
# Show which Git identity will be stamped on commits in this repo, and which
# GitHub account gh / git remote operations are likely to use.
#
# Usage:
#   ./scripts/check_git_identity.sh
#   ./scripts/check_git_identity.sh /path/to/other/repo
#
# Commit author vs GitHub login:
#   - Commits use git user.name + user.email (see below).
#   - Push / PR / gh commands use the authenticated GitHub account (gh auth).
#   These can differ; this script prints both so you can verify before committing.

set -euo pipefail

REPO="${1:-$PWD}"

if [[ ! -d "$REPO/.git" ]]; then
  echo "Not a git repository: $REPO" >&2
  exit 1
fi

print_config() {
  local key="$1"
  local label="$2"
  local value origin

  value="$(git -C "$REPO" config --get "$key" 2>/dev/null || true)"
  origin="$(git -C "$REPO" config --show-origin --get "$key" 2>/dev/null | awk '{print $1}' || true)"

  if [[ -z "$value" ]]; then
    echo "  $label: (not set)"
    return
  fi

  if [[ -n "$origin" ]]; then
    echo "  $label: $value"
    echo "           source: $origin"
  else
    echo "  $label: $value"
  fi
}

section() {
  echo
  echo "== $1 =="
}

section "Repository"
echo "  path:   $REPO"
branch="$(git -C "$REPO" branch --show-current 2>/dev/null || true)"
echo "  branch: ${branch:-(detached or unknown)}"
remote_url="$(git -C "$REPO" config --get remote.origin.url 2>/dev/null || true)"
echo "  origin: ${remote_url:-(no origin remote)}"

section "Commit identity (author on git log)"
print_config user.name "user.name"
print_config user.email "user.email"

signing_key="$(git -C "$REPO" config --get user.signingkey 2>/dev/null || true)"
if [[ -n "$signing_key" ]]; then
  print_config user.signingkey "user.signingkey"
  gpg_format="$(git -C "$REPO" config --get gpg.format 2>/dev/null || echo "openpgp")"
  echo "  gpg.format: $gpg_format"
fi

commit_gpgsign="$(git -C "$REPO" config --get commit.gpgsign 2>/dev/null || true)"
if [[ "$commit_gpgsign" == "true" ]]; then
  echo "  commit.gpgsign: true (commits will be signed)"
fi

# What git would use for a new commit in this repo (respects conditional includes).
section "Effective committer (git var)"
committer_ident="$(git -C "$REPO" var GIT_COMMITTER_IDENT 2>/dev/null || true)"
author_ident="$(git -C "$REPO" var GIT_AUTHOR_IDENT 2>/dev/null || true)"
if [[ -n "$committer_ident" ]]; then
  echo "  committer: $committer_ident"
fi
if [[ -n "$author_ident" && "$author_ident" != "$committer_ident" ]]; then
  echo "  author:    $author_ident"
fi

section "GitHub CLI (gh auth)"
if command -v gh >/dev/null 2>&1; then
  if gh auth status -h github.com 2>&1; then
  :
  else
    echo "  (gh auth status failed — run: gh auth login)"
  fi
else
  echo "  gh not installed; skip GitHub CLI account check."
fi

section "Tips"
cat <<'EOF'
  Add a second GitHub account:  gh auth login
  Switch active gh account:    gh auth switch
  Refresh expired token:        gh auth refresh -h github.com

  Per-repo commit identity (without changing global ~/.gitconfig):
    git config user.name "Your Name"
    git config user.email "you@example.com"

  Multiple accounts by folder (in ~/.gitconfig):
    [includeIf "gitdir:~/work/"]
      path = ~/.gitconfig-work
EOF
