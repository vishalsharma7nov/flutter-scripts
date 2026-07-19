#!/usr/bin/env bash
# Resolve FLUTTER_SCRIPTS_HOME (repo root that contains lib/).
# Usage from any script under the tree:
#   _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=scripts_home.sh
#   source "$(_d="$_SCRIPT_DIR"; while [[ "$_d" != / && ! -f "$_d/lib/scripts_home.sh" ]]; do _d="$(dirname "$_d")"; done; echo "$_d/lib/scripts_home.sh")"
#   _REPO_ROOT="$(flutter_scripts_home "$_SCRIPT_DIR")"

flutter_scripts_home() {
  local start="${1:-}"
  if [[ -n "${FLUTTER_SCRIPTS_HOME:-}" && -d "${FLUTTER_SCRIPTS_HOME}/lib" ]]; then
    printf '%s\n' "$(cd "$FLUTTER_SCRIPTS_HOME" && pwd)"
    return 0
  fi
  if [[ -n "${SCRIPTS_DIR:-}" && -d "${SCRIPTS_DIR}/lib" ]]; then
    printf '%s\n' "$(cd "$SCRIPTS_DIR" && pwd)"
    return 0
  fi
  local d="${start:-}"
  if [[ -z "$d" ]]; then
    d="$(pwd)"
  fi
  d="$(cd "$d" && pwd)"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/lib" && -f "$d/lib/script_catalog.sh" ]]; then
      printf '%s\n' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  echo "flutter_scripts_home: could not locate repo root (lib/script_catalog.sh)" >&2
  return 1
}
