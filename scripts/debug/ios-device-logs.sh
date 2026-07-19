#!/usr/bin/env bash
#
# Stream iOS device/simulator logs filtered to this app's bundle identifier.
#
# Usage:
#   ./scripts/ios-device-logs.sh
#   ./scripts/ios-device-logs.sh --release
#   ./scripts/ios-device-logs.sh -d "iPhone 16 Pro"
#   BUNDLE_ID=com.example.myapp ./scripts/ios-device-logs.sh
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

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

DEVICE_NAME=""
DEVICE_UDID=""
BUNDLE_OVERRIDE=""
BUILD_MODE="${BUILD_MODE:-debug}"
CLEAR_LOGS="false"
LOG_ARGS=()

print_usage() {
  cat <<'EOF'
Stream iOS logs for this app's bundle identifier.

Usage:
  ./scripts/ios-device-logs.sh [global options] [options] [-- extra log stream args...]

Global options:
  --project PATH        Flutter project root
  --pick                Choose from nearby Flutter apps
  --select N            Pick project N from the discovery menu
  --list-projects       List discoverable Flutter apps and exit

Options:
  -d, --device NAME     Simulator name or physical device name/UDID
  -b, --bundle-id ID    Override bundle identifier
      --release         Use release bundle id (default: debug)
  -c, --clear           Clear recent logs before streaming (simulator only)
  -h, --help            Show this help

Environment:
  BUNDLE_ID             Same as --bundle-id
  BUILD_MODE            debug|release (default: debug)
  PROJECT_ROOT          Same as --project

Examples:
  ./scripts/ios-device-logs.sh
  ./scripts/ios-device-logs.sh --project ~/StudioProjects/my_app
  ./scripts/ios-device-logs.sh --release
  ./scripts/ios-device-logs.sh -d "iPhone 16 Pro"
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

enter_project
ROOT="$PROJECT_ROOT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      DEVICE_NAME="${2:-}"
      if [[ -z "$DEVICE_NAME" ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    -b|--bundle-id)
      BUNDLE_OVERRIDE="${2:-}"
      if [[ -z "$BUNDLE_OVERRIDE" ]]; then
        echo "Missing value for $1" >&2
        exit 1
      fi
      shift 2
      ;;
    --release)
      BUILD_MODE="release"
      shift
      ;;
    -c|--clear)
      CLEAR_LOGS="true"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      LOG_ARGS+=("$@")
      break
      ;;
    *)
      LOG_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS log streaming requires macOS (log stream / simctl)." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode command line tools." >&2
  exit 1
fi

BUNDLE_ID="$(resolve_ios_bundle_id "$ROOT" "$BUNDLE_OVERRIDE" "$BUILD_MODE")"

resolve_simulator_udid() {
  local query="${1:-}"
  if [[ -z "$query" ]]; then
    xcrun simctl list devices booted -j \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); booted=[u for devs in d.get("devices",{}).values() for u in devs if u.get("state")=="Booted"]; print(booted[0]["udid"] if booted else "")'
    return 0
  fi

  xcrun simctl list devices -j \
    | python3 -c '
import json
import sys

query = sys.argv[1].lower()
data = json.load(sys.stdin)

for runtime_devices in data.get("devices", {}).values():
    for device in runtime_devices:
        name = device.get("name", "")
        udid = device.get("udid", "")
        if query in name.lower() or query == udid:
            print(udid)
            sys.exit(0)
' "$query"
}

resolve_physical_device_udid() {
  local query="${1:-}"
  xcrun xctrace list devices 2>/dev/null \
    | python3 -c '
import sys

query = sys.argv[1].lower() if len(sys.argv) > 1 and sys.argv[1] else ""
for line in sys.stdin:
    line = line.strip()
    if not line or line.startswith("==") or "Simulator" in line:
        continue
    if " (" not in line or not line.endswith(")"):
        continue
    name, rest = line.rsplit(" (", 1)
    udid = rest[:-1]
    if not query or query in name.lower() or query == udid.lower():
        print(udid)
        sys.exit(0)
' "$query"
}

resolve_app_executable() {
  local udid="$1"
  local bundle_id="$2"
  local container=""

  if ! container="$(xcrun simctl get_app_container "$udid" "$bundle_id" 2>/dev/null)"; then
    return 1
  fi

  defaults read "${container}/Info.plist" CFBundleExecutable 2>/dev/null
}

SIM_UDID="$(resolve_simulator_udid "$DEVICE_NAME" || true)"
PHYSICAL_UDID=""
if [[ -z "$SIM_UDID" ]]; then
  PHYSICAL_UDID="$(resolve_physical_device_udid "$DEVICE_NAME" || true)"
fi

if [[ -z "$SIM_UDID" && -z "$PHYSICAL_UDID" ]]; then
  if [[ -n "$DEVICE_NAME" ]]; then
    echo "No matching iOS simulator or device for: $DEVICE_NAME" >&2
  else
    echo "No booted simulator or connected device found." >&2
    echo "Boot a simulator or connect a device, or pass -d <name|udid>." >&2
  fi
  exit 1
fi

PREDICATE="subsystem CONTAINS \"$BUNDLE_ID\" OR eventMessage CONTAINS \"$BUNDLE_ID\""

if [[ -n "$SIM_UDID" ]]; then
  EXECUTABLE="$(resolve_app_executable "$SIM_UDID" "$BUNDLE_ID" || true)"
  if [[ -n "$EXECUTABLE" ]]; then
    PREDICATE="process == \"$EXECUTABLE\" OR $PREDICATE"
  fi

  if [[ "$CLEAR_LOGS" == "true" ]]; then
    echo "Clearing simulator log buffer..."
    xcrun simctl spawn "$SIM_UDID" log erase >/dev/null 2>&1 || true
  fi

  echo "Streaming simulator logs for bundle=$BUNDLE_ID udid=$SIM_UDID"
  if [[ ${#LOG_ARGS[@]} -eq 0 ]]; then
    LOG_ARGS=( --style compact --level debug )
  fi

  exec xcrun simctl spawn "$SIM_UDID" log stream \
    --predicate "$PREDICATE" \
    "${LOG_ARGS[@]}"
fi

DEVICE_UDID="$PHYSICAL_UDID"
echo "Streaming physical device logs for bundle=$BUNDLE_ID udid=$DEVICE_UDID"

# macOS `log stream` has no --device-udid. Prefer libimobiledevice syslog.
if ! command -v idevicesyslog >/dev/null 2>&1; then
  cat >&2 <<EOF
Physical iOS device log streaming needs idevicesyslog (libimobiledevice).

  brew install libimobiledevice

Or boot a simulator and re-run (simulator uses: xcrun simctl spawn … log stream).
Or open Console.app and filter by: $BUNDLE_ID

Device udid: $DEVICE_UDID
EOF
  exit 1
fi

echo "Using idevicesyslog (filter: $BUNDLE_ID)"
# Filter to the app when possible; keep streaming even if no matches yet.
exec idevicesyslog -u "$DEVICE_UDID" 2>&1 | grep -E --line-buffered "$BUNDLE_ID|${BUNDLE_ID##*.}" || true
