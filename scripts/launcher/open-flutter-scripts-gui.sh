#!/usr/bin/env bash
#
# Start the flutter-scripts React + Go GUI.
#
# Usage:
#   ./open-flutter-scripts-gui.sh
#   ./open-flutter-scripts-gui.sh --project ~/StudioProjects/my_app
#   ./open-flutter-scripts-gui.sh --port 8766 --no-open
#
# Environment:
#   SCRIPTS_DIR / FLUTTER_SCRIPTS_HOME   Scripts catalog root
#   PROJECT_ROOT                        Default Flutter project cwd for runs
#   FLUTTER_SCRIPTS_GUI_PORT            Port (default 8766)

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"


source "$_REPO_ROOT/lib/open_browser_url.sh"

TOOL_DIR="$_REPO_ROOT/tools/flutter_scripts_gui"
GO_DIR="$TOOL_DIR/server/go"
BIN_DIR="$TOOL_DIR/bin"
BIN="$BIN_DIR/flutter_scripts_gui"
PORT="${FLUTTER_SCRIPTS_GUI_PORT:-8766}"
SCRIPTS_HOME="${SCRIPTS_DIR:-${FLUTTER_SCRIPTS_HOME:-$_REPO_ROOT}}"
PROJECT_DIR="${PROJECT_ROOT:-$PWD}"
AUTO_OPEN="true"
HOST="127.0.0.1"

print_usage() {
  cat <<'EOF'
Open the flutter-scripts web GUI (React UI + Go backend).

Usage:
  open-flutter-scripts-gui.sh [options]

Options:
  --project PATH     Working directory for script runs (default: PROJECT_ROOT or cwd)
  --scripts-dir PATH Scripts catalog root (default: this repo)
  -p, --port PORT    Listen port (default: 8766)
  --host ADDR        Bind address (default: 127.0.0.1)
  --lan              Bind 0.0.0.0
  --no-open          Do not open a browser
  -h, --help         Show help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --scripts-dir)
      SCRIPTS_HOME="$2"
      shift 2
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    --host)
      HOST="$2"
      shift 2
      ;;
    --lan)
      HOST="0.0.0.0"
      shift
      ;;
    --no-open)
      AUTO_OPEN="false"
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$TOOL_DIR" ]]; then
  echo "flutter_scripts_gui tool missing: $TOOL_DIR" >&2
  exit 1
fi

if [[ ! -d "$SCRIPTS_HOME" ]]; then
  echo "Scripts directory not found: $SCRIPTS_HOME" >&2
  exit 1
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SCRIPTS_HOME="$(cd "$SCRIPTS_HOME" && pwd)"

ensure_binary() {
  mkdir -p "$BIN_DIR"
  local need_build="false"
  if [[ ! -x "$BIN" ]]; then
    need_build="true"
  elif [[ -d "$GO_DIR" ]]; then
    if [[ -n "$(find "$GO_DIR" -type f \( -name '*.go' -o -name 'go.mod' -o -name 'go.sum' \) -newer "$BIN" 2>/dev/null | head -1)" ]]; then
      need_build="true"
    fi
  fi
  if [[ "$need_build" != "true" ]]; then
    return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "Go is required to build flutter_scripts_gui (go not found on PATH)." >&2
    exit 1
  fi
  echo "Building flutter_scripts_gui..." >&2
  (cd "$GO_DIR" && go build -o "$BIN" ./cmd/flutter_scripts_gui)
}

ensure_web() {
  local need_build="false"
  if [[ ! -f "$TOOL_DIR/web/index.html" ]]; then
    need_build="true"
  elif [[ -d "$TOOL_DIR/frontend/src" ]]; then
    # Rebuild when source is newer than the shipped UI (keeps Git LLM tab in sync).
    if [[ -n "$(find "$TOOL_DIR/frontend/src" -type f -newer "$TOOL_DIR/web/index.html" 2>/dev/null | head -1)" ]]; then
      need_build="true"
    fi
  fi

  if [[ "$need_build" == "true" ]]; then
    if [[ -d "$TOOL_DIR/frontend" ]] && command -v npm >/dev/null 2>&1; then
      echo "Building flutter_scripts_gui frontend..." >&2
      (cd "$TOOL_DIR/frontend" && npm install && npm run build)
    fi
  fi

  if [[ ! -f "$TOOL_DIR/web/index.html" ]]; then
    echo "Missing UI at $TOOL_DIR/web/index.html — run: (cd tools/flutter_scripts_gui/frontend && npm install && npm run build)" >&2
    exit 1
  fi
}

ensure_binary
ensure_web

stop_stale_listener() {
  local pids
  pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -z "$pids" ]]; then
    return 0
  fi
  local pid
  for pid in $pids; do
    local cmd
    cmd="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    if [[ "$cmd" == *flutter_scripts_gui* ]]; then
      echo "Stopping stale flutter_scripts_gui on port $PORT (pid $pid)…" >&2
      kill "$pid" 2>/dev/null || true
      sleep 0.2
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
      fi
    else
      echo "Port $PORT is in use by another process (pid $pid). Stop it or use --port." >&2
      exit 1
    fi
  done
}

stop_stale_listener

args=(
  --port "$PORT"
  --host "$HOST"
  --scripts-dir "$SCRIPTS_HOME"
  --project "$PROJECT_DIR"
  --no-open
)

echo "Starting flutter-scripts GUI on http://127.0.0.1:${PORT}/" >&2
echo "  project: $PROJECT_DIR" >&2
echo "  scripts: $SCRIPTS_HOME" >&2

"$BIN" "${args[@]}" &
GUI_PID=$!

cleanup() {
  if kill -0 "$GUI_PID" 2>/dev/null; then
    kill "$GUI_PID" 2>/dev/null || true
    wait "$GUI_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Wait until the port accepts connections, then open the browser.
for _ in $(seq 1 50); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$GUI_PID" 2>/dev/null; then
    echo "GUI server exited early." >&2
    exit 1
  fi
  sleep 0.1
done

if [[ "$AUTO_OPEN" == "true" ]]; then
  open_or_refresh_browser_url "http://127.0.0.1:${PORT}/" || true
fi

wait "$GUI_PID"
