#!/usr/bin/env bash
#
# Clear Dart/Flutter pub cache.
#
# Usage:
#   flutter-clear-pub-cache --git-pattern 'my_org*'
#   flutter-clear-pub-cache --full --yes
#   flutter-clear-pub-cache --repair
#   flutter-clear-pub-cache --help
#
# Modes (pick one):
#   --git-pattern <glob>  Remove matching packages from ~/.pub-cache/git/
#   --full                Run flutter pub cache clean (entire global cache)
#   --repair              Run flutter pub cache repair
#
# Options:
#   --project, --pick, --select, --list-projects
#                       Flutter project selection (see flutter-build-android --help)
#   --clean-artifacts     Remove project .dart_tool/, build/, plugin lock files
#   --ios-pods            Run pod install in ios/ after pub get
#   --no-get              Skip flutter pub get at the end
#   --yes, -y             Skip confirmation prompts
#
# Environment variables:
#   PUB_CACHE             Override pub cache location (default: ~/.pub-cache)
#   SKIP_CONFIRM          Same as --yes when set to true

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

MODE=""
GIT_PATTERN=""
CLEAR_PROJECT="false"
RUN_PUB_GET="true"
RUN_IOS_PODS="false"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"
NEEDS_PROJECT="false"

PUB_CACHE_DIR="${PUB_CACHE:-"$HOME/.pub-cache"}"

print_usage() {
  sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    print_usage
    exit 0
  fi
done

confirm() {
  local prompt="$1"
  if [[ "$SKIP_CONFIRM" == "true" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell — pass --yes to confirm." >&2
    return 1
  fi
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

clear_git_pattern_cache() {
  local pattern="$1"
  local git_dir="$PUB_CACHE_DIR/git"
  if [[ ! -d "$git_dir" ]]; then
    echo "No Git pub cache at: $git_dir"
    return 0
  fi

  local matches=()
  while IFS= read -r -d '' path; do
    matches+=("$path")
  done < <(find "$git_dir" -maxdepth 1 -name "$pattern" -print0 2>/dev/null)

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "No Git packages matching '$pattern' under $git_dir"
    return 0
  fi

  echo "Removing ${#matches[@]} Git package(s) matching '$pattern' from $git_dir:"
  for path in "${matches[@]}"; do
    echo "  - $(basename "$path")"
    rm -rf "$path"
  done
}

clear_project_artifacts() {
  echo "Removing project pub/build artifacts..."
  rm -rf \
    "$ROOT/.dart_tool" \
    "$ROOT/build" \
    "$ROOT/.flutter-plugins" \
    "$ROOT/.flutter-plugins-dependencies"
}

run_pub_get() {
  echo "Running pub get..."
  flutter_cmd pub get
}

run_ios_pods() {
  if [[ ! -d "$ROOT/ios" ]]; then
    echo "Skipping pod install — ios/ not found"
    return 0
  fi
  echo "Running pod install in ios/..."
  (cd "$ROOT/ios" && pod install)
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-pattern)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --git-pattern" >&2
        exit 1
      fi
      MODE="git-pattern"
      GIT_PATTERN="$2"
      NEEDS_PROJECT="true"
      shift 2
      ;;
    --full)
      MODE="full"
      shift
      ;;
    --repair)
      MODE="repair"
      shift
      ;;
    --clean-artifacts)
      CLEAR_PROJECT="true"
      NEEDS_PROJECT="true"
      shift
      ;;
    --ios-pods)
      RUN_IOS_PODS="true"
      NEEDS_PROJECT="true"
      shift
      ;;
    --no-get)
      RUN_PUB_GET="false"
      shift
      ;;
    --yes|-y)
      SKIP_CONFIRM="true"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  echo "Pick one mode: --git-pattern, --full, or --repair" >&2
  print_usage
  exit 1
fi

if [[ "$NEEDS_PROJECT" == "true" || "$RUN_PUB_GET" == "true" || "$RUN_IOS_PODS" == "true" || "$CLEAR_PROJECT" == "true" ]]; then
  if [[ "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
    enter_project
  fi
  enter_project
fi

echo "Pub cache directory: $PUB_CACHE_DIR"
echo "Mode: $MODE"

case "$MODE" in
  git-pattern)
    if confirm "Remove Git packages matching '$GIT_PATTERN' and refresh dependencies?"; then
      clear_git_pattern_cache "$GIT_PATTERN"
      if [[ "$CLEAR_PROJECT" == "true" ]]; then
        clear_project_artifacts
      fi
      if [[ "$RUN_PUB_GET" == "true" ]]; then
        run_pub_get
      fi
      if [[ "$RUN_IOS_PODS" == "true" ]]; then
        run_ios_pods
      fi
    else
      echo "Cancelled."
      exit 0
    fi
    ;;
  full)
    if confirm "This deletes the entire pub cache at $PUB_CACHE_DIR. Continue?"; then
      echo "Running flutter pub cache clean..."
      if [[ -n "${ROOT:-}" ]]; then
        flutter_cmd pub cache clean
      elif command -v fvm >/dev/null 2>&1; then
        fvm flutter pub cache clean
      else
        flutter pub cache clean
      fi
      if [[ "$CLEAR_PROJECT" == "true" && -n "${ROOT:-}" ]]; then
        clear_project_artifacts
      fi
      if [[ "$RUN_PUB_GET" == "true" && -n "${ROOT:-}" ]]; then
        run_pub_get
      fi
      if [[ "$RUN_IOS_PODS" == "true" && -n "${ROOT:-}" ]]; then
        run_ios_pods
      fi
    else
      echo "Cancelled."
      exit 0
    fi
    ;;
  repair)
    echo "Running flutter pub cache repair..."
    if [[ -n "${ROOT:-}" ]]; then
      flutter_cmd pub cache repair
    elif command -v fvm >/dev/null 2>&1; then
      fvm flutter pub cache repair
    else
      flutter pub cache repair
    fi
    if [[ "$CLEAR_PROJECT" == "true" && -n "${ROOT:-}" ]]; then
      clear_project_artifacts
    fi
    if [[ "$RUN_PUB_GET" == "true" && -n "${ROOT:-}" ]]; then
      run_pub_get
    fi
    if [[ "$RUN_IOS_PODS" == "true" && -n "${ROOT:-}" ]]; then
      run_ios_pods
    fi
    ;;
esac

echo "Done."
