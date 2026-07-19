#!/usr/bin/env bash
# Source from any file under scripts/<category>/…
# Sets: _SCRIPT_DIR, _REPO_ROOT, and defaults FLUTTER_SCRIPTS_HOME / SCRIPTS_DIR.
#
# Usage:
#   _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../lib/repo_bootstrap.sh
#   source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"

if [[ -z "${_SCRIPT_DIR:-}" ]]; then
  _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
fi

_REPO_ROOT="$(cd "$_SCRIPT_DIR/../.." && pwd)"
if [[ ! -d "$_REPO_ROOT/lib" ]]; then
  # Walk up if nesting ever changes.
  _d="$_SCRIPT_DIR"
  while [[ "$_d" != / && ! -d "$_d/lib" ]]; do
    _d="$(dirname "$_d")"
  done
  _REPO_ROOT="$_d"
fi

if [[ ! -f "$_REPO_ROOT/lib/script_catalog.sh" ]]; then
  echo "repo_bootstrap: cannot find flutter-scripts root from $_SCRIPT_DIR" >&2
  return 1 2>/dev/null || exit 1
fi

export FLUTTER_SCRIPTS_HOME="${FLUTTER_SCRIPTS_HOME:-$_REPO_ROOT}"
export SCRIPTS_DIR="${SCRIPTS_DIR:-$_REPO_ROOT}"

# shellcheck source=scripts_home.sh
source "$_REPO_ROOT/lib/scripts_home.sh"
