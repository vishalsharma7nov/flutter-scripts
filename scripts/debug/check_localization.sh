#!/usr/bin/env bash
#
# Check Flutter app localization:
#   - ARB key parity across locales (app_en / app_es / app_fr …)
#   - Empty ARB values
#   - l10n.<key> used in Dart but missing from template ARB
#   - Likely hardcoded UI strings (advisory)
#
# Usage:
#   ./scripts/debug/check_localization.sh
#   ./scripts/debug/check_localization.sh --project ~/StudioProjects/my_app
#   ./scripts/debug/check_localization.sh --path features/home-view-feature
#   ./scripts/debug/check_localization.sh --mode hardcoded
#   ./scripts/debug/check_localization.sh --mode full --json
#   ./scripts/debug/check_localization.sh --mode suggestions --json
#   ./scripts/debug/check_localization.sh --unused --json
#   ./scripts/debug/check_localization.sh --mode suggestions --apply --analyze
#   ./scripts/debug/check_localization.sh --warn-only
#
# Requires: Go (builds/uses flutter_scripts_gui localization-check)
#
# Options (plus standard --project / --pick / --select):
#   --mode <m>         hardcoded | full | suggestions
#   --path <rel>       Limit Dart scan under lib/ (repeatable)
#   --no-hardcoded     Skip hardcoded UI string heuristics
#   --no-parity        Skip ARB key parity checks
#   --unused           Also report unused ARB keys
#   --apply            Apply generated localization edits to the project
#   --analyze          Run analyze after apply
#   --warn-only        Always exit 0
#   --json             Machine-readable summary
#   --help             Show this help

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"

# shellcheck source=../../lib/flutter_project.sh
source "$_REPO_ROOT/lib/flutter_project.sh"

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
}

parse_global_options "$@"
# shellcheck source=../../lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

PY_ARGS=()
SHOW_HELP=false

while ((${#remaining_args[@]} > 0)); do
  arg="${remaining_args[0]}"
  remaining_args=("${remaining_args[@]:1}")
  case "$arg" in
    -h|--help)
      SHOW_HELP=true
      ;;
    --path)
      if ((${#remaining_args[@]} == 0)); then
        echo "--path requires a value" >&2
        exit 2
      fi
      PY_ARGS+=(--path "${remaining_args[0]}")
      remaining_args=("${remaining_args[@]:1}")
      ;;
    --mode)
      if ((${#remaining_args[@]} == 0)); then
        echo "--mode requires hardcoded|full|suggestions" >&2
        exit 2
      fi
      PY_ARGS+=(--mode "${remaining_args[0]}")
      remaining_args=("${remaining_args[@]:1}")
      ;;
    --no-hardcoded|--no-parity|--unused|--warn-only|--json|--apply|--analyze)
      PY_ARGS+=("$arg")
      ;;
    --)
      PY_ARGS+=("${remaining_args[@]}")
      remaining_args=()
      ;;
    -*)
      echo "Unknown option: $arg (try --help)" >&2
      exit 2
      ;;
    *)
      # Positional project path fallback
      export PROJECT_ROOT="$arg"
      ;;
  esac
done

if [[ "$SHOW_HELP" == true ]]; then
  usage
  exit 0
fi

enter_project

TOOL_DIR="$_REPO_ROOT/tools/flutter_scripts_gui"
GO_DIR="$TOOL_DIR/server/go"
BIN_DIR="$TOOL_DIR/bin"
BIN="$BIN_DIR/flutter_scripts_gui"

ensure_binary() {
  mkdir -p "$BIN_DIR"
  local need_build="false"
  if [[ ! -x "$BIN" ]]; then
    need_build="true"
  elif [[ -d "$GO_DIR" ]]; then
    if [[ -n "$(find "$GO_DIR" -type f \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' \) -newer "$BIN" 2>/dev/null | head -1)" ]]; then
      need_build="true"
    fi
  fi
  if [[ "$need_build" != "true" ]]; then
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Go is required to build flutter_scripts_gui (go not found on PATH)." >&2
    exit 2
  fi
  echo "Building flutter_scripts_gui..." >&2
  (cd "$GO_DIR" && go build -o "$BIN" ./cmd/flutter_scripts_gui)
}

ensure_binary

exec "$BIN" localization-check --project "$ROOT" "${PY_ARGS[@]}"
