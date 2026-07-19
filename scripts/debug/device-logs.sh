#!/usr/bin/env bash
#
# Stream device logs for this Flutter app (Android logcat or iOS log stream).
# Package / bundle id is read from the project unless overridden.
#
# Usage:
#   ./scripts/device-logs.sh android
#   ./scripts/device-logs.sh ios
#   ./scripts/device-logs.sh ios --release
#
# Install globally:
#   ./scripts/install-device-logs-global.sh

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

print_usage() {
  cat <<'EOF'
Stream platform logs filtered by this app's package / bundle identifier.

Usage:
  ./scripts/device-logs.sh [global options] <android|ios> [platform-specific options...]

Global options:
  --project PATH        Flutter project root
  --pick                Choose from nearby Flutter apps
  --select N            Pick project N from the discovery menu
  --list-projects       List discoverable Flutter apps and exit

Examples:
  ./scripts/device-logs.sh android
  ./scripts/device-logs.sh --project ~/StudioProjects/my_app android
  ./scripts/device-logs.sh --select 2 ios --release
  ./scripts/device-logs.sh android -d emulator-5554 --clear
  ./scripts/device-logs.sh ios --release -d "iPhone 16 Pro"

See also:
  ./scripts/android-logcat.sh --help
  ./scripts/ios-device-logs.sh --help
EOF
}

if [[ "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
  enter_project
fi

if [[ $# -eq 0 ]]; then
  print_usage
  exit 1
fi

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    print_usage
    exit 0
  fi
done

enter_project
ROOT="$PROJECT_ROOT"

PLATFORM="$1"
shift

case "$PLATFORM" in
  android|a)
    exec "$SCRIPT_DIR/android-logcat.sh" "$@"
    ;;
  ios|i)
    exec "$SCRIPT_DIR/ios-device-logs.sh" "$@"
    ;;
  -h|--help|help)
    print_usage
    exit 0
    ;;
  *)
    echo "Unknown platform: $PLATFORM (expected android or ios)" >&2
    print_usage
    exit 1
    ;;
esac
