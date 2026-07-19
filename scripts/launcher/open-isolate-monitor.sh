#!/usr/bin/env bash
#
# Deploy a Flutter app to a connected device and open the isolate monitor GUI.
# Interactive by default: pick device, debug/release, then build, install, and monitor.
#
# Usage:
#   ./scripts/open-isolate-monitor.sh
#   ./scripts/open-isolate-monitor.sh --no-deploy
#   ./scripts/open-isolate-monitor.sh --release -d RZCY60EWTDB
#   ./scripts/open-isolate-monitor.sh --release-build -d RZCY60EWTDB
#   ./scripts/open-isolate-monitor.sh --uri "ws://127.0.0.1:50251/..."
#
# Install globally:
#   ./install-device-logs-global.sh   # installs flutter-isolate-monitor

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/flutter_project.sh"
# shellcheck source=lib/app_package_ids.sh
source "$_REPO_ROOT/lib/app_package_ids.sh"
# shellcheck source=lib/flutter_devices.sh
source "$_REPO_ROOT/lib/flutter_devices.sh"
# shellcheck source=lib/build_common.sh
source "$_REPO_ROOT/lib/build_common.sh"
# shellcheck source=lib/open_browser_url.sh
source "$_REPO_ROOT/lib/open_browser_url.sh"
# shellcheck source=lib/detect_file_opener.sh
source "$_REPO_ROOT/lib/detect_file_opener.sh"

parse_global_options "$@"
# shellcheck source=lib/apply_remaining_args.sh
source "$_REPO_ROOT/lib/apply_remaining_args.sh"

TOOL_DIR=""
PORT="${MONITOR_PORT:-8765}"
FLUTTER_VM_SERVICE_PORT="${FLUTTER_VM_SERVICE_PORT:-58888}"
BUNDLE_OVERRIDE=""
BUILD_MODE="${BUILD_MODE:-}"
BACKEND_LANG="${ISOLATE_MONITOR_BACKEND:-${BACKEND_LANG:-}}"
BACKEND_FROM_CLI="false"
PACKAGE_OVERRIDE=""
FLUTTER_DEVICE_ID=""
VM_URI=""
AUTO_OPEN="true"
DEPLOY_APP="auto"
NO_DEPLOY="false"
EXTRA_ARGS=()
MONITOR_PID=""

export FLUTTER_VM_SERVICE_PORT

monitor_mode_from_build_mode() {
  case "$1" in
    release-build) echo "release" ;;
    release) echo "profile" ;;
    *) echo "debug" ;;
  esac
}

bundle_build_mode_from_build_mode() {
  case "$1" in
    debug) echo "debug" ;;
    *) echo "release" ;;
  esac
}

print_usage() {
  cat <<'EOF'
Deploy to a connected device and open the Dart isolate monitor web GUI.

Usage:
  ./scripts/open-isolate-monitor.sh [global options] [options] [-- extra dart args...]

Global options:
  --project PATH        Flutter project root
  --pick                Choose from nearby Flutter apps
  --select N            Pick project N from the discovery menu
  --list-projects       List discoverable Flutter apps and exit

Options:
  -p, --port PORT       Web GUI port (default: 8765)
  --package ID          Android applicationId override
  --bundle-id ID        iOS bundle identifier override
  -d, --device ID       Flutter device id (see: flutter devices)
  --debug               Debug build (default when deploying)
  --profile             Profile build (near release, isolates via VM service)
  --release             Same as --profile (legacy alias)
  --release-build       Store release build (--release, device logs only)
  --backend LANG        Monitor server language: dart|go|typescript (default: dart)
  --deploy              Build and run on a connected device (default when interactive)
  --no-deploy           Start monitor only; do not run flutter on a device
  --uri VM_URI          Existing Dart VM service URI (skips deploy)
  --no-auto-open        Start server only; do not open browser
  -h, --help            Show this help

Interactive flow (default in a terminal):
  1. Choose monitor server (dart / go / typescript) — always asked before start
  2. Pick a connected Flutter device
  3. Pick debug, profile, or release build
  4. Start isolate monitor, then flutter run/install on the device
  5. Open browser when VM service is available (debug/profile), or stream device logs

Environment:
  FLUTTER_VM_SERVICE_PORT  Fixed Flutter VM port (default: 58888)
  ENV_FILE / APP_ENV       Optional dart-defines for configured apps
  PROJECT_ROOT             Same as --project
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
setup_flutter

resolve_isolate_monitor_dir() {
  local project_root="$1"
  local scripts_root="$2"

  if [[ -n "${ISOLATE_MONITOR_DIR:-}" && -d "${ISOLATE_MONITOR_DIR}" ]]; then
    echo "${ISOLATE_MONITOR_DIR}"
    return 0
  fi
  if [[ -d "$scripts_root/tools/isolate_monitor" ]]; then
    echo "$scripts_root/tools/isolate_monitor"
    return 0
  fi
  if [[ -d "$project_root/tool/isolate_monitor" ]]; then
    echo "$project_root/tool/isolate_monitor"
    return 0
  fi
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--port)
      PORT="${2:-}"
      shift 2
      ;;
    --package)
      PACKAGE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_OVERRIDE="${2:-}"
      shift 2
      ;;
    --release)
      BUILD_MODE="release"
      shift
      ;;
    --profile)
      BUILD_MODE="release"
      shift
      ;;
    --release-build)
      BUILD_MODE="release-build"
      shift
      ;;
    --backend)
      BACKEND_LANG="${2:-}"
      BACKEND_FROM_CLI="true"
      shift 2
      ;;
    --debug)
      BUILD_MODE="debug"
      shift
      ;;
    -d|--device)
      FLUTTER_DEVICE_ID="${2:-}"
      shift 2
      ;;
    --deploy)
      DEPLOY_APP="true"
      shift
      ;;
    --no-deploy)
      NO_DEPLOY="true"
      DEPLOY_APP="false"
      shift
      ;;
    --uri)
      VM_URI="${2:-}"
      DEPLOY_APP="false"
      shift 2
      ;;
    --no-auto-open|--no-browser)
      AUTO_OPEN="false"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      if ((${#@} > 0)); then
        EXTRA_ARGS+=("$@")
      fi
      break
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -n "$VM_URI" ]]; then
  DEPLOY_APP="false"
fi

if [[ "$DEPLOY_APP" == "auto" ]]; then
  if [[ "$NO_DEPLOY" == "true" ]]; then
    DEPLOY_APP="false"
  elif [[ -t 0 ]]; then
    DEPLOY_APP="true"
  else
    DEPLOY_APP="false"
  fi
fi

TOOL_DIR="$(resolve_isolate_monitor_dir "$ROOT" "$SCRIPT_DIR" || true)"

if [[ -z "$TOOL_DIR" || ! -d "$TOOL_DIR" ]]; then
  echo "Isolate monitor tool not found." >&2
  echo "Expected one of:" >&2
  echo "  $SCRIPT_DIR/tools/isolate_monitor" >&2
  echo "  $ROOT/tool/isolate_monitor" >&2
  echo "Set ISOLATE_MONITOR_DIR to override." >&2
  exit 1
fi

BACKEND_PREF_FILE="$TOOL_DIR/.backend-lang"
echo "" >&2
echo "============================================================" >&2
echo " Isolate Monitor — choose server before start" >&2
echo "============================================================" >&2
if [[ "$BACKEND_FROM_CLI" == "true" ]]; then
  BACKEND_LANG="$(pick_backend_language "${BACKEND_LANG:-}" "$BACKEND_PREF_FILE")"
else
  # Always prompt in a TTY; do not auto-use env/pref (pref is Enter default only).
  BACKEND_LANG="$(pick_backend_language "" "$BACKEND_PREF_FILE")"
fi
BACKEND_LANG="${BACKEND_LANG##*$'\n'}"
BACKEND_LANG="$(printf '%s' "$BACKEND_LANG" | tr -d '\r')"
printf '%s\n' "$BACKEND_LANG" >"$BACKEND_PREF_FILE"
export ISOLATE_MONITOR_BACKEND="$BACKEND_LANG"
echo "Selected server: $BACKEND_LANG" >&2
echo "" >&2

case "$BACKEND_LANG" in
  go)
    if ! command -v go >/dev/null 2>&1; then
      echo "Go toolchain not found — install Go, or choose dart." >&2
      exit 1
    fi
    echo "" >&2
    echo "Backend: go (server/go) — same React UI as Dart." >&2
    echo "" >&2
    BACKEND_RUNTIME="go"
    ;;
  typescript)
    echo "" >&2
    echo "Backend preference: typescript" >&2
    echo "Scaffold: $TOOL_DIR/server/typescript" >&2
    echo "TypeScript server is not runnable yet — starting Dart monitor so the GUI keeps working." >&2
    echo "Implement TypeScript under server/typescript, then restart with --backend typescript once ready." >&2
    echo "" >&2
    BACKEND_RUNTIME="dart"
    ;;
  *)
    BACKEND_RUNTIME="dart"
    ;;
esac

apply_backend_preference() {
  if [[ -f "$BACKEND_PREF_FILE" ]]; then
    BACKEND_LANG="$(tr -d '[:space:]' <"$BACKEND_PREF_FILE" | tr '[:upper:]' '[:lower:]')"
  fi
  case "$BACKEND_LANG" in
    go)
      if command -v go >/dev/null 2>&1; then
        BACKEND_RUNTIME="go"
      else
        BACKEND_RUNTIME="dart"
      fi
      ;;
    typescript)
      BACKEND_RUNTIME="dart"
      ;;
    *)
      BACKEND_LANG="dart"
      BACKEND_RUNTIME="dart"
      ;;
  esac
  export ISOLATE_MONITOR_BACKEND="$BACKEND_LANG"
}

if command -v fvm >/dev/null 2>&1; then
  DART=(fvm dart)
else
  DART=(dart)
fi

if [[ "$DEPLOY_APP" == "true" ]]; then
  FLUTTER_DEVICE_ID="$(pick_flutter_device "$FLUTTER_DEVICE_ID")"
  FLUTTER_DEVICE_ID="${FLUTTER_DEVICE_ID##*$'\n'}"
  FLUTTER_DEVICE_ID="$(printf '%s' "$FLUTTER_DEVICE_ID" | tr -d '\r')"

  BUILD_MODE="$(pick_build_mode "${BUILD_MODE:-}")"
  BUILD_MODE="${BUILD_MODE##*$'\n'}"
  BUILD_MODE="$(printf '%s' "$BUILD_MODE" | tr -d '\r')"

  if [[ "$BUILD_MODE" == "release" ]]; then
    echo "" >&2
    echo "Profile mode: flutter run --profile for isolates + device logs in the GUI." >&2
    echo "(Use --release-build for a true store --release install without VM service.)" >&2
    echo "" >&2
  elif [[ "$BUILD_MODE" == "release-build" ]]; then
    echo "" >&2
    echo "Release mode: flutter run --release (store build, device logs only)." >&2
    echo "Dart VM service and isolates are not available in this mode." >&2
    echo "" >&2
  fi

  resolve_build_env
elif [[ -z "${BUILD_MODE:-}" ]]; then
  # Monitor-only: still choose debug / profile / release so Connect + logs match.
  BUILD_MODE="$(pick_build_mode "")"
  BUILD_MODE="${BUILD_MODE##*$'\n'}"
  BUILD_MODE="$(printf '%s' "$BUILD_MODE" | tr -d '\r')"
  if [[ -z "$BUILD_MODE" ]]; then
    BUILD_MODE="debug"
  fi
  if [[ "$BUILD_MODE" == "release-build" ]]; then
    echo "" >&2
    echo "Release attach mode: connect a device in the GUI for logcat + native threads." >&2
    echo "" >&2
  fi
fi

PACKAGE_ID="$(resolve_android_package_id "$ROOT" "$PACKAGE_OVERRIDE")"
bundle_build_mode="$(bundle_build_mode_from_build_mode "$BUILD_MODE")"
BUNDLE_ID="$(resolve_ios_bundle_id "$ROOT" "$BUNDLE_OVERRIDE" "$bundle_build_mode")"

echo "Resolving isolate monitor dependencies..."
(cd "$TOOL_DIR" && "${DART[@]}" pub get >/dev/null)

build_isolate_monitor_ui() {
  local frontend_dir="$TOOL_DIR/frontend"
  if [[ ! -f "$frontend_dir/package.json" ]]; then
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm not found — using existing web/ build for Isolate Monitor UI." >&2
    return 0
  fi
  echo "Building Isolate Monitor React UI..."
  if [[ ! -d "$frontend_dir/node_modules" ]]; then
    (cd "$frontend_dir" && npm install --silent) || {
      echo "npm install failed — using existing web/ build." >&2
      return 0
    }
  fi
  (cd "$frontend_dir" && npm run build --silent) || {
    echo "npm run build failed — using existing web/ build." >&2
    return 0
  }
}

build_isolate_monitor_ui

MONITOR_URL="http://127.0.0.1:$PORT"
MONITOR_LOG="${TMPDIR:-/tmp}/isolate-monitor-${PORT}.log"
GUI_OPENED="false"
export ISOLATE_MONITOR_OPEN_URL_SCRIPT="$_REPO_ROOT/lib/open_browser_url.sh"
export ISOLATE_MONITOR_FILE_OPENER="$(detect_file_opener)"

stop_monitor_on_port() {
  local pids
  pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    echo "Stopping existing isolate monitor on port $PORT..."
    kill $pids 2>/dev/null || true
    sleep 0.4
  fi
}

cleanup() {
  if [[ -n "$MONITOR_PID" ]]; then
    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
    MONITOR_PID=""
  fi
}

trap cleanup EXIT INT TERM

wait_for_monitor_server() {
  local attempt
  for attempt in $(seq 1 30); do
    if curl -fsS "$MONITOR_URL/api/status" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done
  echo "Monitor server did not start on $MONITOR_URL" >&2
  echo "Check log: $MONITOR_LOG" >&2
  return 1
}

print_monitor_banner() {
  echo ""
  echo "============================================================"
  echo " ISOLATE MONITOR GUI"
  echo "   $MONITOR_URL"
  echo "============================================================"
  echo " Keep this page open while the app builds and launches."
  echo " Monitor log: $MONITOR_LOG"
  echo ""
}

open_monitor_gui() {
  local url="$1"
  if [[ "$AUTO_OPEN" != "true" ]]; then
    print_monitor_banner
    return 0
  fi
  if [[ "$GUI_OPENED" == "true" ]]; then
    return 0
  fi
  GUI_OPENED="true"
  print_monitor_banner
  open_or_refresh_browser_url "$url"
}

open_gui_for_connected_vm() {
  local url="$MONITOR_URL"
  local status vm_uri gui_url
  status="$(curl -fsS "$url/api/status" 2>/dev/null || true)"
  if [[ "$status" != *'"vmConnected":true'* ]]; then
    return 1
  fi
  vm_uri="$(STATUS_JSON="$status" python3 -c 'import json, os, urllib.parse; uri=json.loads(os.environ["STATUS_JSON"]).get("vmUri", ""); print(urllib.parse.quote(uri, safe=""))')"
  if [[ -n "$vm_uri" ]]; then
    gui_url="${url}/?vmUri=${vm_uri}"
  else
    gui_url="$url"
  fi
  open_or_refresh_browser_url "$gui_url"
}

wait_for_vm_and_open_gui() {
  if [[ "$BUILD_MODE" == "release-build" ]]; then
    return 0
  fi
  if [[ "$AUTO_OPEN" != "true" ]]; then
    return 0
  fi

  echo "Waiting for VM service on port $FLUTTER_VM_SERVICE_PORT..."
  for _ in $(seq 1 180); do
    if open_gui_for_connected_vm; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for VM service on $MONITOR_URL" >&2
  echo "Check that the app launched in debug with --host-vmservice-port=$FLUTTER_VM_SERVICE_PORT" >&2
  return 1
}

start_monitor_background() {
  local skip_auto_deploy="${1:-false}"
  local -a monitor_args=()
  local monitor_mode

  apply_backend_preference
  monitor_mode="$(monitor_mode_from_build_mode "$BUILD_MODE")"

  echo "Starting Isolate Monitor on $MONITOR_URL"
  echo "Project: $ROOT"
  echo "Backend preference: $BACKEND_LANG (runtime: $BACKEND_RUNTIME)"
  case "$BUILD_MODE" in
    release-build)
      echo "Mode: release (store build · device logs only)"
      ;;
    release)
      echo "Mode: profile (isolates + device logs on port $FLUTTER_VM_SERVICE_PORT)"
      ;;
    *)
      echo "Mode: debug (Dart isolates + device logs on port $FLUTTER_VM_SERVICE_PORT)"
      ;;
  esac
  echo "Android package: $PACKAGE_ID"
  echo "iOS bundle id: $BUNDLE_ID"

  if [[ ! -f "$MONITOR_LOG" ]]; then
    : >"$MONITOR_LOG"
  else
    {
      echo ""
      echo "----- monitor restart $(date '+%Y-%m-%d %H:%M:%S') backend=$BACKEND_LANG runtime=$BACKEND_RUNTIME -----"
    } >>"$MONITOR_LOG"
  fi

  if [[ "$BACKEND_RUNTIME" == "go" ]]; then
    monitor_args=(
      run ./cmd/isolate_monitor
      --port "$PORT"
      --package "$PACKAGE_ID"
      --bundle-id "$BUNDLE_ID"
      --project "$ROOT"
      --mode "$monitor_mode"
    )
    if [[ -n "$FLUTTER_DEVICE_ID" ]]; then
      monitor_args+=(--device "$FLUTTER_DEVICE_ID")
    fi
    if [[ -n "${ENV_FILE:-}" ]]; then
      monitor_args+=(--env-file "$ENV_FILE")
    fi
    if [[ -n "${APP_ENV:-}" ]]; then
      monitor_args+=(--app-env "$APP_ENV")
    fi
    if command -v fvm >/dev/null 2>&1; then
      monitor_args+=(--use-fvm)
    fi
    if [[ "$monitor_mode" != "debug" ]]; then
      monitor_args+=(--release-logs)
    fi
    if [[ "$DEPLOY_APP" == "true" && "$skip_auto_deploy" != "true" ]]; then
      monitor_args+=(--auto-deploy)
    fi
    if [[ -n "$VM_URI" ]]; then
      monitor_args+=(--uri "$VM_URI")
    fi
    if [[ "$AUTO_OPEN" == "false" ]]; then
      monitor_args+=(--no-auto-open)
    else
      monitor_args+=(--auto-open-on-vm)
    fi
    monitor_args+=(--lan)
    (cd "$TOOL_DIR/server/go" && go "${monitor_args[@]}" >>"$MONITOR_LOG" 2>&1) &
    MONITOR_PID=$!
  else
    monitor_args=(run bin/isolate_monitor.dart --port "$PORT" --package "$PACKAGE_ID" --bundle-id "$BUNDLE_ID" --project "$ROOT")
    if [[ -n "$FLUTTER_DEVICE_ID" ]]; then
      monitor_args+=(--device "$FLUTTER_DEVICE_ID")
    fi
    if [[ -n "${ENV_FILE:-}" ]]; then
      monitor_args+=(--env-file "$ENV_FILE")
    fi
    if [[ -n "${APP_ENV:-}" ]]; then
      monitor_args+=(--app-env "$APP_ENV")
    fi
    if command -v fvm >/dev/null 2>&1; then
      monitor_args+=(--use-fvm)
    fi
    monitor_args+=(--mode "$monitor_mode")
    if [[ "$monitor_mode" != "debug" ]]; then
      monitor_args+=(--release-logs)
    fi
    if [[ "$DEPLOY_APP" == "true" && "$skip_auto_deploy" != "true" ]]; then
      monitor_args+=(--auto-deploy)
    fi
    if [[ -n "$VM_URI" ]]; then
      monitor_args+=(--uri "$VM_URI")
    fi
    if [[ "$AUTO_OPEN" == "false" ]]; then
      monitor_args+=(--no-auto-open)
    else
      monitor_args+=(--auto-open-on-vm)
    fi
    monitor_args+=(--lan)
    if array_not_empty EXTRA_ARGS; then
      array_append_all monitor_args EXTRA_ARGS
    fi
    (cd "$TOOL_DIR" && "${DART[@]}" "${monitor_args[@]}" >>"$MONITOR_LOG" 2>&1) &
    MONITOR_PID=$!
  fi

  if ! wait_for_monitor_server; then
    tail -30 "$MONITOR_LOG" >&2 || true
    exit 1
  fi
  open_monitor_gui "$MONITOR_URL"
}

# Exit code 100 = GUI asked to switch backend / relaunch monitor.
MONITOR_RESTART_EXIT_CODE=100

run_monitor_supervised() {
  local first=true
  local exit_code=0
  while true; do
    if [[ "$first" == "true" ]]; then
      start_monitor_background "false"
      first=false
    else
      echo ""
      echo "Monitor requested restart (backend preference changed)..."
      stop_monitor_on_port
      sleep 0.3
      start_monitor_background "true"
    fi
    set +e
    wait "$MONITOR_PID"
    exit_code=$?
    set -e
    MONITOR_PID=""
    if [[ "$exit_code" -eq "$MONITOR_RESTART_EXIT_CODE" ]]; then
      apply_backend_preference
      echo "Relaunching monitor (preferred backend: $BACKEND_LANG)..."
      continue
    fi
    return "$exit_code"
  done
}

run_on_device() {
  local -a run_args=(run -d "$FLUTTER_DEVICE_ID")

  case "$BUILD_MODE" in
    release-build)
      run_args+=(--release)
      ;;
    release)
      run_args+=(--profile --host-vmservice-port="$FLUTTER_VM_SERVICE_PORT" --disable-service-auth-codes)
      ;;
    *)
      run_args+=(
        --debug
        --host-vmservice-port="$FLUTTER_VM_SERVICE_PORT"
        --disable-service-auth-codes
      )
      ;;
  esac

  if [[ -n "${ENV_FILE:-}" ]]; then
    run_args+=(--dart-define-from-file="$ENV_FILE")
    if [[ -n "${APP_ENV:-}" ]]; then
      run_args+=(--dart-define="APP_ENV=$APP_ENV")
    fi
  fi

  echo ""
  echo "Running on $FLUTTER_DEVICE_ID ($BUILD_MODE)..."
  flutter_cmd "${run_args[@]}"
}

stop_monitor_on_port

if [[ "$DEPLOY_APP" == "true" ]]; then
  (
    wait_for_vm_and_open_gui || true
  ) &
  echo ""
  echo "Deploying via isolate monitor (use the GUI Reinstall button to rebuild)..."
  if ! run_monitor_supervised; then
    echo "" >&2
    echo "Isolate monitor exited unexpectedly." >&2
    echo "Check log: $MONITOR_LOG" >&2
    tail -30 "$MONITOR_LOG" >&2 || true
    exit 1
  fi
  exit 0
fi

# Monitor only (existing VM URI or --no-deploy).
run_monitor_supervised
exit $?
