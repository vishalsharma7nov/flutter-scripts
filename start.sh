#!/usr/bin/env bash
#
# One-step start for any user / machine:
#   1) Setup + install PATH wrappers for this clone
#   2) Open the GUI (pick/switch Flutter project inside the UI)
#
# Usage:
#   ./start.sh
#   ./start.sh /path/to/flutter/app
#   ./start.sh --project ~/StudioProjects/my_app
#   ./start.sh --list-projects
#   ./start.sh --pick
#   ./start.sh --add-profile
#   ./start.sh --no-open
#   ./start.sh --cli
#
set -euo pipefail

CLONE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export FLUTTER_SCRIPTS_HOME="$CLONE"
export SCRIPTS_DIR="$CLONE"

# shellcheck source=lib/flutter_project.sh
source "$CLONE/lib/flutter_project.sh"

PROJECT=""
ADD_PROFILE="false"
ASK_PROFILE="false"
NO_OPEN="false"
USE_CLI="false"
FORCE_PICK="false"
LIST_ONLY="false"
SEARCH_ROOT=""

print_usage() {
  cat <<'EOF'
Flutter Scripts — one-step start (any user / any machine).

Usage:
  ./start.sh                         Setup + open GUI (choose project in the UI)
  ./start.sh /path/to/app            Setup + open GUI with this project
  ./start.sh --project PATH
  ./start.sh --pick                  Terminal project menu, then open GUI
  ./start.sh --list-projects         Only list discovered apps
  ./start.sh --search-root PATH      Where to scan (with --pick / --list-projects)
  ./start.sh --add-profile           Append shell snippet to ~/.zshrc or ~/.bashrc
  ./start.sh --no-open               Setup only (do not open GUI)
  ./start.sh --cli                   Terminal menu instead of GUI

Portable notes:
  - This script uses the folder it lives in (no hardcoded username/path).
  - Wrappers are installed under ~/.local/bin for the current user.
  - Optional: brew install ollama && ollama serve  (for Git LLM)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      print_usage
      exit 0
      ;;
    --project)
      PROJECT="${2:-}"
      [[ -n "$PROJECT" ]] || { echo "Missing value for --project" >&2; exit 1; }
      shift 2
      ;;
    --search-root)
      SEARCH_ROOT="${2:-}"
      [[ -n "$SEARCH_ROOT" ]] || { echo "Missing value for --search-root" >&2; exit 1; }
      shift 2
      ;;
    --pick)
      FORCE_PICK="true"
      shift
      ;;
    --list-projects)
      LIST_ONLY="true"
      shift
      ;;
    --add-profile)
      ADD_PROFILE="true"
      ASK_PROFILE="false"
      shift
      ;;
    --no-profile)
      ADD_PROFILE="false"
      ASK_PROFILE="false"
      shift
      ;;
    --no-open)
      NO_OPEN="true"
      shift
      ;;
    --cli)
      USE_CLI="true"
      shift
      ;;
    --*)
      echo "Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
    *)
      if [[ -n "$PROJECT" ]]; then
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      PROJECT="$1"
      shift
      ;;
  esac
done

if [[ -n "$SEARCH_ROOT" ]]; then
  export FLUTTER_PROJECT_SEARCH_ROOT="$(cd "$SEARCH_ROOT" && pwd)"
fi

_ensure_prereqs() {
  if ! command -v bash >/dev/null 2>&1; then
    echo "bash is required." >&2
    exit 1
  fi
  mkdir -p "${FLUTTER_BIN_DIR:-$HOME/.local/bin}"
  if ! command -v flutter >/dev/null 2>&1 && ! command -v fvm >/dev/null 2>&1; then
    echo "note: flutter/fvm not on PATH yet — GUI still opens; install Flutter for builds." >&2
  fi
}

_validate_project() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "Not a directory: $dir" >&2
    return 1
  fi
  dir="$(cd "$dir" && pwd)"
  if ! _is_flutter_app "$dir" && ! _is_flutter_project "$dir"; then
    echo "Not a Flutter project (need pubspec.yaml with flutter: and lib/): $dir" >&2
    return 1
  fi
  printf '%s\n' "$dir"
}

_pick_project_interactive() {
  # UI goes to stderr so callers can capture only the project path on stdout.
  local -a projects=()
  local line choice path
  local index=1

  echo "" >&2
  echo "==> Scanning for Flutter projects…" >&2
  echo "    (cwd, StudioProjects, Documents, Developer, Projects, …)" >&2
  echo "    Override scan root: --search-root PATH" >&2
  echo "" >&2

  FORCE_PROJECT_PICK=true
  while IFS= read -r line; do
    [[ -n "$line" ]] && projects+=("$line")
  done < <(_collect_discovered_projects)

  # Also include cwd if it's a Flutter project and somehow missed.
  if _is_flutter_project "$PWD"; then
    local cwd_abs
    cwd_abs="$(cd "$PWD" && pwd)"
    local found="false"
    for line in "${projects[@]+"${projects[@]}"}"; do
      [[ "$line" == "$cwd_abs" ]] && found="true"
    done
    if [[ "$found" != "true" ]]; then
      projects=("$cwd_abs" "${projects[@]+"${projects[@]}"}")
    fi
  fi

  if ((${#projects[@]} == 0)); then
    echo "No Flutter apps found nearby." >&2
    echo "" >&2
    if [[ -t 0 ]]; then
      printf 'Paste a Flutter project path (or Enter to continue without one): ' >&2
      read -r path || true
      path="${path/#\~/$HOME}"
      if [[ -n "$path" ]]; then
        _validate_project "$path"
        return 0
      fi
    fi
    return 1
  fi

  if ((${#projects[@]} == 1)) && [[ "$FORCE_PICK" != "true" ]]; then
    echo "Found 1 project: ${projects[0]}" >&2
    if [[ -t 0 ]]; then
      printf 'Use this project? [Y/n/p=path]: ' >&2
      read -r choice || choice="Y"
      case "${choice:-Y}" in
        n|N|q|Q) return 1 ;;
        p|P)
          printf 'Path: ' >&2
          read -r path
          path="${path/#\~/$HOME}"
          _validate_project "$path"
          return 0
          ;;
        *)
          printf '%s\n' "${projects[0]}"
          return 0
          ;;
      esac
    else
      printf '%s\n' "${projects[0]}"
      return 0
    fi
  fi

  echo "Available Flutter projects:" >&2
  index=1
  for line in "${projects[@]}"; do
    printf '  %2d) %-28s  %s\n' "$index" "$(basename "$line")" "$line" >&2
    index=$((index + 1))
  done
  echo "   p) Enter a path manually" >&2
  echo "   s) Skip (open GUI without a default project)" >&2
  echo "   q) Quit" >&2
  echo "" >&2

  if [[ ! -t 0 ]]; then
    echo "Non-interactive shell: pass --project PATH or --list-projects." >&2
    return 1
  fi

  printf 'Select project [1-%d]: ' "${#projects[@]}" >&2
  read -r choice
  case "$choice" in
    q|Q|"")
      echo "Cancelled." >&2
      exit 1
      ;;
    s|S)
      return 1
      ;;
    p|P)
      printf 'Path: ' >&2
      read -r path
      path="${path/#\~/$HOME}"
      _validate_project "$path"
      return 0
      ;;
  esac

  if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#projects[@]})); then
    printf '%s\n' "${projects[$((choice - 1))]}"
    return 0
  fi

  echo "Invalid selection: $choice" >&2
  return 1
}

_maybe_add_profile() {
  local profile="" do_add="$ADD_PROFILE" answer=""

  if [[ "$ASK_PROFILE" == "true" && -t 0 ]]; then
    printf 'Add flutter-scripts to your shell startup (~/.zshrc or ~/.bashrc)? [Y/n]: '
    read -r answer || answer="Y"
    case "${answer:-Y}" in
      n|N) do_add="false" ;;
      *) do_add="true" ;;
    esac
  fi

  [[ "$do_add" == "true" ]] || return 0

  if [[ "$(basename "${SHELL:-zsh}")" == "bash" ]]; then
    profile="$HOME/.bashrc"
  else
    profile="$HOME/.zshrc"
  fi
  touch "$profile"
  if grep -Fq "$CLONE/shell-profile.snippet" "$profile" 2>/dev/null; then
    echo "    shell profile already wired ($profile)"
    return 0
  fi
  {
    echo ""
    echo "# flutter-scripts (added by ./start.sh — portable per-user)"
    echo "source \"$CLONE/shell-profile.snippet\""
  } >>"$profile"
  echo "    appended to $profile"
}

# --- main ---

_ensure_prereqs

echo "==> Flutter Scripts — one step (portable)"
echo "    clone (this machine): $CLONE"
echo "    user:                 $(whoami)"
echo ""

if [[ "$LIST_ONLY" == "true" ]]; then
  echo "Discovered Flutter projects:"
  FORCE_PROJECT_PICK=true
  found="false"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    found="true"
    printf '  - %s  (%s)\n' "$(basename "$line")" "$line"
  done < <(_collect_discovered_projects)
  if [[ "$found" != "true" ]]; then
    echo "  (none found — try --search-root PATH)"
    exit 1
  fi
  exit 0
fi

# Resolve project without blocking the GUI (unless --pick).
if [[ -n "$PROJECT" ]]; then
  PROJECT="$( _validate_project "${PROJECT/#\~/$HOME}" )"
elif [[ "$FORCE_PICK" == "true" ]]; then
  if selected="$(_pick_project_interactive)"; then
    PROJECT="$selected"
  else
    PROJECT=""
  fi
elif [[ -n "${PROJECT_ROOT:-}" ]] && _is_flutter_project "${PROJECT_ROOT/#\~/$HOME}"; then
  PROJECT="$(cd "${PROJECT_ROOT/#\~/$HOME}" && pwd)"
elif _is_flutter_project "$PWD"; then
  PROJECT="$(cd "$PWD" && pwd)"
fi

echo ""
if [[ -n "$PROJECT" ]]; then
  echo "    project: $PROJECT"
else
  echo "    project: (choose in the GUI → Project tab)"
fi
echo ""

# Ensure scripts executable
find "$CLONE" \( -path "$CLONE/scripts/*.sh" -o -path "$CLONE/scripts/*/*.sh" -o -path "$CLONE/*.sh" \) \
  -type f -print0 2>/dev/null | xargs -0 chmod +x 2>/dev/null || true

echo "==> 1/3 Setup + install commands for this user (~/.local/bin)"
if [[ -n "$PROJECT" ]]; then
  "$CLONE/scripts/setup/setup.sh" --project "$PROJECT"
else
  "$CLONE/scripts/setup/setup.sh"
fi

echo ""
echo "==> 2/3 Load PATH for this session"
# shellcheck source=/dev/null
source "$CLONE/setup.env" 2>/dev/null || true
export FLUTTER_SCRIPTS_HOME="$CLONE"
export SCRIPTS_DIR="$CLONE"
if [[ -n "$PROJECT" ]]; then
  export PROJECT_ROOT="$PROJECT"
fi
# shellcheck source=/dev/null
source "$CLONE/shell-profile.snippet"
_maybe_add_profile

if command -v ollama >/dev/null 2>&1; then
  if curl -sf --max-time 1 "http://127.0.0.1:11434/api/tags" >/dev/null 2>&1; then
    echo "    Ollama: online (Git LLM ready)"
  else
    echo "    Ollama: installed — start with: ollama serve"
  fi
else
  echo "    Ollama: optional for Git LLM — brew install ollama && ollama serve"
fi

echo ""
if [[ "$USE_CLI" == "true" ]]; then
  echo "==> 3/3 Opening terminal menu"
  exec "$CLONE/scripts/launcher/flutter-scripts.sh" --cli
fi

if [[ "$NO_OPEN" == "true" ]]; then
  echo "==> 3/3 Setup complete (--no-open)"
  echo ""
  echo "Open the GUI anytime:"
  echo "  ./start.sh"
  echo "  ./start.sh --project /path/to/app"
  exit 0
fi

echo "==> 3/3 Opening GUI…"
GUI_ARGS=(--scripts-dir "$CLONE")
if [[ -n "$PROJECT" ]]; then
  GUI_ARGS+=(--project "$PROJECT")
else
  # Prefer clone root over a random cwd so the UI still boots cleanly.
  GUI_ARGS+=(--project "$CLONE")
fi
exec "$CLONE/scripts/launcher/open-flutter-scripts-gui.sh" "${GUI_ARGS[@]}"
