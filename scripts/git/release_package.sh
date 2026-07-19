#!/usr/bin/env bash
# Config-driven release for any Flutter git package.
#
# Usage:
#   release-package --list
#   release-package --package my_package --dry-run
#   release-package my_package -y --title "Fix map recenter"
#
# Each package has <scripts_dir>/<package_id>/release.config.sh
# See release.config.template.sh and docs/PACKAGE_RELEASE.md

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


# shellcheck source=lib/package_release_catalog.sh
source "$_REPO_ROOT/lib/package_release_catalog.sh"
# shellcheck source=lib/package_release_lib.sh
source "$_REPO_ROOT/lib/package_release_lib.sh"

PACKAGE_ID=""
LIST_ONLY=false
PR_BUMP="patch"
PR_TITLE=""
PR_CODE_MESSAGE=""
PR_NOTES=""
PR_NOTES_FILE=""
PR_REMOTE="origin"
PR_BRANCH=""
PR_DRY_RUN=false
PR_NO_PUSH=false
PR_SKIP_CHECKS=false
PR_AUTO_COMMIT_CODE=true
PR_ASSUME_YES=false

usage() {
  cat <<'EOF'
Release a Flutter git package: commit → checks → version bump → tag → push.

Usage:
  release-package [--package ID] [patch|minor|major] [options]
  release-package --list

Pipeline (per package release.config.sh):
  1. Preflight (git repo, identity, remote, branch)
  2. Auto-commit uncommitted code (unless --no-auto-commit)
  3. Quality checks (analyze, channel contract, flutter test, optional Android)
  4. Bump pubspec + extra version files + CHANGELOG
  5. Release commit + annotated tag vX.Y.Z
  6. git push branch + tag

Options:
  --package ID          Package id (e.g. my_package); interactive picker if omitted
  --list                List configured packages and exit
  patch|minor|major     Semver bump (default: patch)
  --title TEXT          Release subject / default code commit subject
  --code-message TEXT   Message for pre-release code commit
  --notes "a;b;c"       Changelog bullets (semicolon-separated)
  --notes-file PATH     One changelog bullet per line
  --remote NAME         Git remote (default: origin)
  --branch NAME         Branch to push (default: current)
  --no-auto-commit      Fail if dirty instead of committing code first
  --skip-checks         Skip analyze / tests / channel contract
  --dry-run             Show plan only; no commits, no push
  --no-push             Commit and tag locally; do not push
  -y, --yes             Skip confirmation prompts
  -h, --help            Show this help

Environment:
  REPO_ROOT             Override package checkout path
  <PACKAGE>_REPO        Per-package override (see release.config.sh)

Examples:
  release-package --list
  release-package --package my_package --dry-run
  release-package my_package -y --title "Fix map recenter"
EOF
  exit "${1:-0}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --package)
        PACKAGE_ID="${2:-}"
        shift 2
        ;;
      --list)
        LIST_ONLY=true
        shift
        ;;
      patch|minor|major)
        PR_BUMP="$1"
        shift
        ;;
      --title)
        PR_TITLE="${2:-}"
        shift 2
        ;;
      --code-message)
        PR_CODE_MESSAGE="${2:-}"
        shift 2
        ;;
      --notes)
        PR_NOTES="${2:-}"
        shift 2
        ;;
      --notes-file)
        PR_NOTES_FILE="${2:-}"
        shift 2
        ;;
      --branch)
        PR_BRANCH="${2:-}"
        shift 2
        ;;
      --remote)
        PR_REMOTE="${2:-}"
        shift 2
        ;;
      --no-auto-commit)
        PR_AUTO_COMMIT_CODE=false
        shift
        ;;
      --skip-checks)
        PR_SKIP_CHECKS=true
        shift
        ;;
      --dry-run)
        PR_DRY_RUN=true
        shift
        ;;
      --no-push)
        PR_NO_PUSH=true
        shift
        ;;
      -y|--yes)
        PR_ASSUME_YES=true
        shift
        ;;
      -h|--help)
        usage 0
        ;;
      -*)
        echo "Unknown option: $1" >&2
        usage 1
        ;;
      *)
        if [[ -z "$PACKAGE_ID" ]]; then
          PACKAGE_ID="$1"
          shift
        else
          echo "Unknown argument: $1" >&2
          usage 1
        fi
        ;;
    esac
  done
}

resolve_repo_root() {
  if [[ -n "${REPO_ROOT:-}" ]]; then
    PR_REPO_ROOT="$REPO_ROOT"
    return
  fi
  if [[ -n "${PR_REPO_ENV_VAR:-}" ]]; then
    local env_val
  env_val="$(printenv "${PR_REPO_ENV_VAR}" 2>/dev/null || true)"
    if [[ -n "$env_val" ]]; then
      PR_REPO_ROOT="$env_val"
      return
    fi
  fi
  PR_REPO_ROOT="${PR_DEFAULT_REPO:?PR_DEFAULT_REPO not set in release.config.sh}"
}

load_package_config() {
  local config_file="$1"
  # shellcheck disable=SC1090
  source "$config_file"
  resolve_repo_root
}

main() {
  parse_args "$@"

  if $LIST_ONLY; then
    discover_release_packages "$SCRIPT_DIR"
    list_release_packages_and_exit
  fi

  RELEASE_PACKAGE_ID="$PACKAGE_ID"
  local config_file
  config_file="$(select_release_package "$SCRIPT_DIR")" || exit 1

  load_package_config "$config_file"
  pr_run_release_pipeline
}

main "$@"
