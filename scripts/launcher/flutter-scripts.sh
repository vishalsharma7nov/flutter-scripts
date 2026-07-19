#!/usr/bin/env bash
#
# Interactive launcher for shell scripts in this directory.
# Bare invocation opens the React + Go GUI; use --cli for the terminal menu.
#
# Usage:
#   flutter-scripts
#   flutter-scripts --cli
#   flutter-scripts --list
#   flutter-scripts --select 3
#   flutter-scripts build_android.sh --aab
#   flutter-scripts 5 -- --env prod apk
#
# Environment:
#   SCRIPTS_DIR          Script tree (default: directory containing this file)
#   SCRIPT_SELECT        Same as --select (non-interactive)
#   PROJECT_ROOT         Flutter project cwd for GUI script runs

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/script_catalog.sh"

SCRIPTS_HOME="${SCRIPTS_DIR:-$_REPO_ROOT}"
export FLUTTER_SCRIPTS_LAUNCHER="$(basename "${BASH_SOURCE[0]}")"
LIST_SCRIPTS="false"
USE_CLI="false"
FORCE_GUI="false"
SCRIPT_ARGS=()

print_usage() {
  cat <<'EOF'
Interactive launcher for shell scripts.

Usage:
  flutter-scripts                          Open the web GUI (default)
  flutter-scripts --cli                    Terminal menu (classic)
  flutter-scripts --gui                    Force open the web GUI
  flutter-scripts --list                   List scripts and exit
  flutter-scripts --select N [args...]     Run script number N
  flutter-scripts <script.sh> [args...]    Run a script by name
  flutter-scripts N [args...]              Run script number N with args

Options:
  --list, --list-scripts   Print numbered script catalog and exit
  --select N               Pick script by number (non-interactive)
  --cli                    Use the interactive terminal menu
  --gui                    Open the web GUI
  -h, --help               Show launcher help (script --help: pass after --select)

Scripts are discovered automatically from SCRIPTS_DIR under scripts/<category>/*.sh.

Examples:
  flutter-scripts
  flutter-scripts --cli
  flutter-scripts --select 1 --aab
  flutter-scripts build_ios.sh --skip-checks
  flutter-scripts device-logs.sh android --clear
EOF
}

_resolve_gui_project() {
  local candidate="${PROJECT_ROOT:-}"
  if [[ -n "$candidate" && -d "$candidate" ]]; then
    (cd "$candidate" && pwd)
    return 0
  fi
  candidate="$PWD"
  while [[ "$candidate" != "/" ]]; do
    if [[ -f "$candidate/pubspec.yaml" ]]; then
      (cd "$candidate" && pwd)
      return 0
    fi
    candidate="$(dirname "$candidate")"
  done
  pwd
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && [[ $# -eq 1 ]]; then
  print_usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list|--list-scripts)
      LIST_SCRIPTS="true"
      shift
      ;;
    --cli)
      USE_CLI="true"
      shift
      ;;
    --gui)
      FORCE_GUI="true"
      shift
      ;;
    --select)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --select" >&2
        exit 1
      fi
      SCRIPT_SELECT="$2"
      shift 2
      ;;
    --)
      shift
      SCRIPT_ARGS+=("$@")
      break
      ;;
    *)
      if [[ -z "${SCRIPT_SELECT:-}" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        SCRIPT_SELECT="$1"
        shift
        continue
      fi
      if [[ -z "${SCRIPT_SELECT:-}" ]] && [[ "$1" == *.sh ]]; then
        SCRIPT_SELECT="$1"
        shift
        continue
      fi
      SCRIPT_ARGS+=("$1")
      shift
      ;;
  esac
done

_load_script_catalog "$SCRIPTS_HOME"

if [[ "$LIST_SCRIPTS" == "true" ]]; then
  _list_scripts_and_exit
fi

# Interactive with no explicit selection → GUI (unless --cli).
if [[ "$FORCE_GUI" == "true" ]] || { [[ -z "${SCRIPT_SELECT:-}" ]] && [[ "$USE_CLI" != "true" ]]; }; then
  gui_launcher="$_REPO_ROOT/scripts/launcher/open-flutter-scripts-gui.sh"
  if [[ ! -x "$gui_launcher" ]]; then
    chmod +x "$gui_launcher" 2>/dev/null || true
  fi
  if [[ ! -f "$gui_launcher" ]]; then
    echo "GUI launcher missing: $gui_launcher (falling back to --cli)" >&2
  else
    project="$(_resolve_gui_project)"
    export PROJECT_ROOT="$project"
    export SCRIPTS_DIR="$SCRIPTS_HOME"
    exec "$gui_launcher" --project "$project" --scripts-dir "$SCRIPTS_HOME"
  fi
fi

selected="$(select_script_cli "$SCRIPTS_HOME")"
selected="${selected##*$'\n'}"  # stdout must be filename only; take last line if leaked
selected="$(printf '%s' "$selected" | tr -d '\r')"

if [[ -z "$selected" ]]; then
  exit 1
fi

target="$SCRIPTS_HOME/$selected"
if [[ ! -f "$target" ]]; then
  echo "Script not found: $target" >&2
  exit 1
fi

if [[ ! -x "$target" ]]; then
  chmod +x "$target"
fi

echo ""
if ((${#SCRIPT_ARGS[@]} > 0)); then
  exec "$target" "${SCRIPT_ARGS[@]}"
else
  exec "$target"
fi
