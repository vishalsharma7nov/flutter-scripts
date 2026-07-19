#!/usr/bin/env bash
#
# Pick an editor opener for isolate-monitor file:line links.

detect_file_opener() {
  if [[ -n "${ISOLATE_MONITOR_FILE_OPENER:-}" ]]; then
    echo "$ISOLATE_MONITOR_FILE_OPENER"
    return 0
  fi

  if [[ -n "${CURSOR_TRACE_ID:-}" ]] && command -v cursor >/dev/null 2>&1; then
    echo "cursor"
    return 0
  fi

  if [[ "${TERM_PROGRAM:-}" == "vscode" || -n "${VSCODE_GIT_IPC_HANDLE:-}" ]]; then
    if command -v cursor >/dev/null 2>&1; then
      echo "cursor"
      return 0
    fi
    if command -v code >/dev/null 2>&1; then
      echo "code"
      return 0
    fi
  fi

  if command -v cursor >/dev/null 2>&1; then
    echo "cursor"
    return 0
  fi
  if command -v code >/dev/null 2>&1; then
    echo "code"
    return 0
  fi
  if command -v idea >/dev/null 2>&1; then
    echo "idea"
    return 0
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "macos-open"
    return 0
  fi
  if command -v xdg-open >/dev/null 2>&1; then
    echo "xdg-open"
    return 0
  fi

  echo "none"
}
