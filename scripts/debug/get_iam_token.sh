#!/usr/bin/env bash
# Run IAM OTP token helper when tool/get_iam_token.dart exists in the project.
#
# Usage:
#   flutter-get-iam-token
#   flutter-get-iam-token --project ~/path/to/app
#   flutter-get-iam-token --pick
#   flutter-get-iam-token --select 2
#   flutter-get-iam-token --list-projects
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

if [[ "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
  enter_project
fi

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
  fi
done

enter_project

if [[ ! -f "$ROOT/tool/get_iam_token.dart" ]]; then
  echo "Missing $ROOT/tool/get_iam_token.dart" >&2
  exit 1
fi

dart_cmd run tool/get_iam_token.dart "$@"
