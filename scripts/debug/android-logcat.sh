#!/usr/bin/env bash
#
# Stream Android logcat filtered to this app's package (applicationId).
#
# Usage:
#   ./scripts/android-logcat.sh
#   ./scripts/android-logcat.sh -d emulator-5554
#   ./scripts/android-logcat.sh --clear
#   PACKAGE_NAME=com.example.myapp ./scripts/android-logcat.sh
#
# Install globally:
#   ./scripts/install-device-logs-global.sh

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"
# shellcheck source=lib/app_package_ids.sh
source "$_REPO_ROOT/lib/app_package_ids.sh"
# shellcheck source=lib/adb_devices.sh
source "$_REPO_ROOT/lib/adb_devices.sh"

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

DEVICE_SERIAL=""
CLEAR_LOGS="false"
WAIT_FOR_APP="false"
PACKAGE_OVERRIDE=""
LOGCAT_ARGS=()
SKIP_PROJECT="false"

print_usage() {
  cat <<'EOF'
Stream Android logcat for this app's package name.

Usage:
  ./scripts/android-logcat.sh [global options] [options] [-- extra logcat args...]

Global options:
  --project PATH        Flutter project root
  --pick                Choose from nearby Flutter apps
  --select N            Pick project N from the discovery menu
  --list-projects       List discoverable Flutter apps and exit

Options:
  -d, --device SERIAL   adb device serial (prompts if multiple devices connected)
  -p, --package ID      Override applicationId (default: read from build.gradle)
  -c, --clear           Clear logcat buffer before streaming
  -w, --wait            Wait up to 30s for the app process to appear
  -h, --help            Show this help

Environment:
  PACKAGE_NAME          Same as --package (skips project discovery when set)
  PROJECT_ROOT          Same as --project

Examples:
  ./scripts/android-logcat.sh
  ./scripts/android-logcat.sh --project ~/StudioProjects/my_app
  ./scripts/android-logcat.sh -d emulator-5554 --clear
  ./scripts/android-logcat.sh -- -v time
EOF
}

if [[ "${LIST_FLUTTER_PROJECTS:-}" == "true" ]]; then
  enter_project
fi

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    print_usage
    exit 0
  fi
done

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      DEVICE_SERIAL="${2:-}"
      if [[ -z "$DEVICE_SERIAL" ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    -p|--package)
      PACKAGE_OVERRIDE="${2:-}"
      if [[ -z "$PACKAGE_OVERRIDE" ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      SKIP_PROJECT="true"
      shift 2
      ;;
    -c|--clear)
      CLEAR_LOGS="true"
      shift
      ;;
    -w|--wait)
      WAIT_FOR_APP="true"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      LOGCAT_ARGS+=("$@")
      break
      ;;
    *)
      LOGCAT_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${PACKAGE_NAME:-}" ]]; then
  PACKAGE_OVERRIDE="${PACKAGE_NAME}"
  SKIP_PROJECT="true"
fi

ROOT=""
if [[ "$SKIP_PROJECT" == "true" ]]; then
  ROOT="${PROJECT_ROOT:-$PWD}"
else
  enter_project
  ROOT="$PROJECT_ROOT"
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. Install Android platform-tools and ensure adb is on PATH." >&2
  exit 1
fi

DEVICE_SERIAL="$(pick_adb_device "$DEVICE_SERIAL")"
DEVICE_SERIAL="${DEVICE_SERIAL##*$'\n'}"
DEVICE_SERIAL="$(printf '%s' "$DEVICE_SERIAL" | tr -d '\r')"

ADB=(adb -s "$DEVICE_SERIAL")

PACKAGE_ID="$(resolve_android_package_id "$ROOT" "$PACKAGE_OVERRIDE")"

resolve_android_uid() {
  local package_id="$1"
  "${ADB[@]}" shell dumpsys package "$package_id" 2>/dev/null \
    | awk -F= '/userId=/{gsub(/[^0-9].*/, "", $2); print $2; exit}'
}

resolve_android_pid() {
  local package_id="$1"
  "${ADB[@]}" shell pidof -s "$package_id" 2>/dev/null | tr -d '\r'
}

APP_UID="$(resolve_android_uid "$PACKAGE_ID" || true)"
PID="$(resolve_android_pid "$PACKAGE_ID" || true)"

if [[ "$WAIT_FOR_APP" == "true" && -z "$APP_UID" && -z "$PID" ]]; then
  echo "Waiting for $PACKAGE_ID (install/launch the app on device)..."
  for _ in $(seq 1 30); do
    APP_UID="$(resolve_android_uid "$PACKAGE_ID" || true)"
    PID="$(resolve_android_pid "$PACKAGE_ID" || true)"
    if [[ -n "$APP_UID" || -n "$PID" ]]; then
      break
    fi
    sleep 1
  done
fi

if [[ "$CLEAR_LOGS" == "true" ]]; then
  echo "Clearing logcat on $(adb_device_label "$DEVICE_SERIAL")..."
  "${ADB[@]}" logcat -c
fi

FILTER_ARGS=()
if [[ -n "$APP_UID" ]]; then
  FILTER_ARGS+=( --uid="$APP_UID" )
  echo "Streaming logcat on $(adb_device_label "$DEVICE_SERIAL") for package=$PACKAGE_ID uid=$APP_UID"
elif [[ -n "$PID" ]]; then
  FILTER_ARGS+=( --pid="$PID" )
  echo "Streaming logcat on $(adb_device_label "$DEVICE_SERIAL") for package=$PACKAGE_ID pid=$PID"
else
  echo "Package $PACKAGE_ID is not installed or has no UID yet on $(adb_device_label "$DEVICE_SERIAL")." >&2
  echo "Install the app on this device, launch it, or pass --wait and start the app within 30s." >&2
  echo "Wrong app? Override with -p PACKAGE or set a different Flutter project." >&2
  exit 1
fi

if [[ ${#LOGCAT_ARGS[@]} -eq 0 ]]; then
  LOGCAT_ARGS=( -v brief )
fi

logcat_cmd=("${ADB[@]}" logcat)
array_append_all logcat_cmd FILTER_ARGS
array_append_all logcat_cmd LOGCAT_ARGS
exec "${logcat_cmd[@]}"
