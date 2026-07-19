#!/usr/bin/env bash
# Shared helpers for Flutter shell scripts (repo-local or ~/Documents install).

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bash_compat.sh
source "$_lib_dir/bash_compat.sh"
unset _lib_dir

declare -a remaining_args=()
declare -a DISCOVERED_PROJECTS=()
ROOT=""

_warn_deprecated_once() {
  local key="$1"
  local message="$2"
  if [[ "${_DEPRECATION_WARNED:-}" != *"|${key}|"* ]]; then
    _DEPRECATION_WARNED="${_DEPRECATION_WARNED:-}|${key}|"
    echo "warning: $message" >&2
  fi
}

_migrate_deprecated_env() {
  if [[ -n "${LEGACY_PROJECT_ROOT:-}" && -z "${PROJECT_ROOT:-}" ]]; then
    _warn_deprecated_once LEGACY_PROJECT_ROOT \
      "LEGACY_PROJECT_ROOT is deprecated; use PROJECT_ROOT"
    PROJECT_ROOT="$LEGACY_PROJECT_ROOT"
  fi
  if [[ -n "${PROJECT_SELECT:-}" ]]; then
    FLUTTER_BUILD_CLI_SELECT="true"
  fi
}

scripts_dir() {
  if [[ -n "${SCRIPTS_DIR:-}" ]]; then
    echo "$SCRIPTS_DIR"
    return 0
  fi
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "$(cd "$lib_dir/.." && pwd)"
}

_is_flutter_project() {
  local dir="$1"
  [[ -f "$dir/pubspec.yaml" ]] &&
    [[ -d "$dir/lib" ]] &&
    grep -qE '^[[:space:]]*flutter:' "$dir/pubspec.yaml"
}

# App roots suitable for build scripts (excludes plugin-only packages).
_is_flutter_app() {
  local dir="$1"
  _is_flutter_project "$dir" &&
    { [[ -d "$dir/android" ]] || [[ -d "$dir/ios" ]]; }
}

_discovery_search_root() {
  local root="${FLUTTER_PROJECT_SEARCH_ROOT:-$PWD}"
  if [[ -z "${FLUTTER_PROJECT_SEARCH_ROOT:-}" ]]; then
    if [[ "${FORCE_PROJECT_PICK:-}" == "true" || "${FLUTTER_BUILD_CLI_SELECT:-}" == "true" ]]; then
      if _is_flutter_app "$root"; then
        root="$(dirname "$root")"
      fi
    fi
  fi
  echo "$root"
}

_load_discovered_projects() {
  DISCOVERED_PROJECTS=()
  local line=""
  while IFS= read -r line; do
    [[ -n "$line" ]] && DISCOVERED_PROJECTS+=("$line")
  done < <(_collect_discovered_projects)
}

_print_project_menu() {
  local index=1
  local project=""

  echo "" >&2
  echo "Available Flutter projects:" >&2
  if array_not_empty DISCOVERED_PROJECTS; then
    for project in "${DISCOVERED_PROJECTS[@]}"; do
      printf '  %2d) %s  (%s)\n' "$index" "$(basename "$project")" "$project" >&2
      index=$((index + 1))
    done
  fi
  echo "  q) Quit" >&2
  echo "" >&2
}

# Shows the menu, resolves selection, prints choice. Sets DISCOVERED_PROJECTS.
select_flutter_project_cli() {
  local choice=""
  local selected=""

  _load_discovered_projects
  if ((${#DISCOVERED_PROJECTS[@]} == 0)); then
    return 1
  fi
  if ((${#DISCOVERED_PROJECTS[@]} == 1)) &&
    [[ "${FORCE_PROJECT_PICK:-}" != "true" ]] &&
    [[ -z "${PROJECT_SELECT:-}" ]]; then
    echo "${DISCOVERED_PROJECTS[0]}"
    return 0
  fi

  _print_project_menu

  choice="${PROJECT_SELECT:-}"
  if [[ -z "$choice" ]]; then
    if [[ ! -t 0 ]]; then
      echo "Multiple Flutter projects found. Pass --select N or --project PATH." >&2
      return 1
    fi
    printf 'Select project to build [1-%d]: ' "${#DISCOVERED_PROJECTS[@]}" >&2
    if ! read -r choice; then
      echo "No project selected." >&2
      return 1
    fi
  fi

  if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
    echo "Cancelled." >&2
    return 1
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]] ||
    ((choice < 1 || choice > ${#DISCOVERED_PROJECTS[@]})); then
    echo "Invalid selection: $choice (choose 1-${#DISCOVERED_PROJECTS[@]})." >&2
    return 1
  fi

  selected="${DISCOVERED_PROJECTS[$((choice - 1))]}"
  echo "Selected: $(basename "$selected") ($selected)" >&2
  echo "$selected"
}

maybe_enable_build_project_menu() {
  if [[ -n "${PROJECT_ROOT:-}" || -n "${PROJECT_SELECT:-}" ]]; then
    return 0
  fi
  if [[ "${FORCE_PROJECT_PICK:-}" == "true" || "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 0
  fi

  _load_discovered_projects
  if ((${#DISCOVERED_PROJECTS[@]} == 0)); then
    return 0
  fi

  FLUTTER_BUILD_CLI_SELECT="true"
  if ((${#DISCOVERED_PROJECTS[@]} > 1)); then
    FORCE_PROJECT_PICK="true"
  fi
}

enter_project_for_build() {
  local candidate=""

  if [[ "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
    _list_discovered_projects_and_exit
  fi

  _migrate_deprecated_env

  if [[ -n "${PROJECT_ROOT:-}" ]]; then
    candidate="$(cd "$PROJECT_ROOT" && pwd)"
    if ! _is_flutter_project "$candidate"; then
      echo "PROJECT_ROOT is not a Flutter project: $PROJECT_ROOT" >&2
      exit 1
    fi
    ROOT="$candidate"
    export PROJECT_ROOT="$ROOT"
    cd "$ROOT"
    return 0
  fi

  if [[ "${FORCE_PROJECT_PICK:-}" != "true" && -z "${PROJECT_SELECT:-}" ]]; then
    candidate="$PWD"
    if _is_flutter_project "$candidate"; then
      ROOT="$(cd "$candidate" && pwd)"
      export PROJECT_ROOT="$ROOT"
      cd "$ROOT"
      return 0
    fi

    candidate="$(dirname "$PWD")"
    while [[ "$candidate" != "/" ]]; do
      if _is_flutter_project "$candidate"; then
        ROOT="$(cd "$candidate" && pwd)"
        export PROJECT_ROOT="$ROOT"
        cd "$ROOT"
        return 0
      fi
      candidate="$(dirname "$candidate")"
    done
  fi

  if [[ -n "${PROJECT_SELECT:-}" || "${FORCE_PROJECT_PICK:-}" == "true" || -t 0 ]]; then
    FLUTTER_BUILD_CLI_SELECT="true"
    candidate="$(select_flutter_project_cli || true)"
    if [[ -n "$candidate" ]]; then
      ROOT="$candidate"
      export PROJECT_ROOT="$ROOT"
      cd "$ROOT"
      return 0
    fi
  fi

  echo "Could not find a Flutter project root." >&2
  echo "Run from inside the project, set PROJECT_ROOT, pass --project PATH," >&2
  echo "or use --select N / --list-projects." >&2
  exit 1
}

# Prints absolute paths (one per line), sorted uniquely.
discover_flutter_projects() {
  local search_root="$1"
  local max_depth="${2:-${FLUTTER_PROJECT_SEARCH_DEPTH:-2}}"
  local pubspec_dir=""

  [[ -d "$search_root" ]] || return 0

  while IFS= read -r pubspec; do
    pubspec_dir="$(cd "$(dirname "$pubspec")" && pwd)"
    if _is_flutter_app "$pubspec_dir"; then
      echo "$pubspec_dir"
    fi
  done < <(
    find "$search_root" -mindepth 1 -maxdepth "$max_depth" -name pubspec.yaml -type f 2>/dev/null
  ) | sort -u
}

_collect_discovered_projects() {
  local -a projects=()
  local -a roots=()
  local line=""
  local root=""
  local depth=""
  local search_root=""
  local dup="false"
  local existing=""

  search_root="$(_discovery_search_root)"

  if _is_flutter_app "$search_root"; then
    roots+=("$search_root")
  else
    if [[ "$search_root" != "$HOME" ]]; then
      roots+=("$search_root")
    fi
    for root in \
      "$HOME/StudioProjects" \
      "$HOME/Documents/StudioProjects" \
      "$HOME/Documents" \
      "$HOME/Developer" \
      "$HOME/Projects" \
      "$HOME/dev" \
      "$HOME/code" \
      "$HOME/flutter" \
      "$HOME/src"
    do
      if [[ -d "$root" ]]; then
        dup="false"
        if ((${#roots[@]} > 0)); then
          for existing in "${roots[@]}"; do
            if [[ "$existing" == "$root" ]]; then
              dup="true"
              break
            fi
          done
        fi
        [[ "$dup" != "true" ]] && roots+=("$root")
      fi
    done
  fi

  if ((${#roots[@]} == 0)); then
    return 0
  fi

  for root in "${roots[@]}"; do
    depth="${FLUTTER_PROJECT_SEARCH_DEPTH:-2}"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      dup="false"
      if ((${#projects[@]} > 0)); then
        for existing in "${projects[@]}"; do
          if [[ "$existing" == "$line" ]]; then
            dup="true"
            break
          fi
        done
      fi
      [[ "$dup" != "true" ]] && projects+=("$line")
    done < <(discover_flutter_projects "$root" "$depth")
  done

  if ((${#projects[@]} > 0)); then
    array_print_lines projects | LC_ALL=C sort -u
  fi
}

_list_discovered_projects_and_exit() {
  local line=""
  local found="false"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    found="true"
    echo "$line"
  done < <(_collect_discovered_projects)
  if [[ "$found" != "true" ]]; then
    echo "No Flutter app projects found under $(_discovery_search_root)." >&2
    exit 1
  fi
  exit 0
}

# Deprecated: prints project root without cd. Prefer enter_project / enter_project_for_build.
resolve_project_root() {
  local saved_pwd="$PWD"
  enter_project
  echo "$ROOT"
  cd "$saved_pwd"
}

parse_global_options() {
  remaining_args=()
  _migrate_deprecated_env
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-C)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          exit 1
        fi
        PROJECT_ROOT="$2"
        shift 2
        ;;
      --pick)
        FORCE_PROJECT_PICK="true"
        FLUTTER_BUILD_CLI_SELECT="true"
        shift
        ;;
      --select)
        if [[ $# -lt 2 ]]; then
          echo "Missing value for $1" >&2
          exit 1
        fi
        PROJECT_SELECT="$2"
        FLUTTER_BUILD_CLI_SELECT="true"
        shift 2
        ;;
      --list-projects)
        LIST_FLUTTER_PROJECTS="true"
        shift
        ;;
      *)
        remaining_args+=("$1")
        shift
        ;;
    esac
  done
}

# Deprecated: use `source lib/apply_remaining_args.sh` at script scope instead.
apply_remaining_args() {
  echo "apply_remaining_args: source lib/apply_remaining_args.sh at script scope" >&2
  exit 1
}

enter_project() {
  maybe_enable_build_project_menu
  enter_project_for_build
}

flutter_cmd() {
  if command -v fvm >/dev/null 2>&1; then
    (cd "$ROOT" && fvm flutter "$@")
  else
    (cd "$ROOT" && flutter "$@")
  fi
}

dart_cmd() {
  if command -v fvm >/dev/null 2>&1; then
    (cd "$ROOT" && fvm dart "$@")
  else
    (cd "$ROOT" && dart "$@")
  fi
}
