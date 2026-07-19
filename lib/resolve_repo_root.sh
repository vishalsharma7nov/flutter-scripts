#!/usr/bin/env bash
#
# Resolve a Flutter app repo root (deprecated — use lib/flutter_project.sh).
# Kept for scripts that only need a path string; new scripts should call
# parse_global_options + enter_project / enter_project_for_build instead.

resolve_real_path() {
  local source="$1"
  while [[ -L "$source" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    source="$(readlink "$source")"
    [[ "$source" != /* ]] && source="$dir/$source"
  done
  printf '%s\n' "$(cd -P "$(dirname "$source")" && pwd)/$(basename "$source")"
}

resolve_flutter_repo_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! declare -f enter_project_for_build >/dev/null 2>&1; then
    # shellcheck source=flutter_project.sh
    source "$lib_dir/flutter_project.sh"
  fi

  if [[ $# -gt 0 ]]; then
    parse_global_options "$@"
    # shellcheck source=apply_remaining_args.sh
    source "$lib_dir/apply_remaining_args.sh"
  fi

  enter_project
  printf '%s\n' "$ROOT"
}
