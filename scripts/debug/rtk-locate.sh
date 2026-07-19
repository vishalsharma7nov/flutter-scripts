#!/usr/bin/env bash
# Locate flutter-release-toolkit relative to the Flutter project.
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"

if [[ -z "${ROOT:-}" ]]; then
  parse_global_options "$@"
  # shellcheck source=lib/apply_remaining_args.sh
  source "$_REPO_ROOT/lib/apply_remaining_args.sh"
  enter_project
fi
APP_ROOT="$ROOT"

if [[ -n "${FLUTTER_RELEASE_TOOLKIT:-}" && -f "${FLUTTER_RELEASE_TOOLKIT}/scripts/classify-version-bump.sh" ]]; then
  RTK_ROOT="$(cd "$FLUTTER_RELEASE_TOOLKIT" && pwd)"
else
  LOCATE_SH=""
  for candidate in \
    "$APP_ROOT/flutter-release-toolkit/lib/sh/locate-toolkit.sh" \
    "$APP_ROOT/../flutter-release-toolkit/lib/sh/locate-toolkit.sh" \
    "$HOME/StudioProjects/flutter-release-toolkit/lib/sh/locate-toolkit.sh"
  do
    if [[ -f "$candidate" ]]; then
      LOCATE_SH="$candidate"
      break
    fi
  done
  if [[ -z "$LOCATE_SH" ]]; then
    echo "flutter-release-toolkit not found." >&2
    echo "Set FLUTTER_RELEASE_TOOLKIT or add flutter-release-toolkit beside the project." >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$LOCATE_SH"
  _rtk_locate_toolkit "$APP_ROOT"
fi
