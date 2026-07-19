#!/usr/bin/env bash
#
# Install device log commands globally on PATH.
#
# Usage:
#   ./install-device-logs-global.sh
#   INSTALL_DIR=~/bin ./install-device-logs-global.sh
#
# Installs:
#   flutter-device-logs
#   flutter-android-logcat
#   flutter-ios-logs
#   flutter-isolate-monitor

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"
SCRIPTS_HOME="$_REPO_ROOT"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

install_wrapper() {
  local command_name="$1"
  local script_name="$2"
  local target="$INSTALL_DIR/$command_name"

  cat >"$target" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$SCRIPTS_HOME/$script_name" "\$@"
EOF
  chmod +x "$target"
  echo "  $target"
}

print_usage() {
  cat <<EOF
Install device log commands globally.

Usage:
  $0 [--dir PATH] [--uninstall]

Options:
  --dir PATH      Install directory (default: \$HOME/.local/bin)
  --uninstall     Remove installed commands
  -h, --help      Show this help

Installed commands:
  flutter-device-logs
  flutter-android-logcat
  flutter-ios-logs
  flutter-isolate-monitor
EOF
}

uninstall_commands() {
  local removed=0
  for command_name in flutter-device-logs flutter-android-logcat flutter-ios-logs flutter-isolate-monitor; do
    local target="$INSTALL_DIR/$command_name"
    if [[ -f "$target" ]]; then
      rm -f "$target"
      echo "Removed $target"
      removed=$((removed + 1))
    fi
  done
  if [[ "$removed" -eq 0 ]]; then
    echo "No device log commands found in $INSTALL_DIR"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      INSTALL_DIR="${2:-}"
      if [[ -z "$INSTALL_DIR" ]]; then
        echo "Missing value for --dir" >&2
        exit 1
      fi
      shift 2
      ;;
    --uninstall)
      uninstall_commands
      exit 0
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

mkdir -p "$INSTALL_DIR"
case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *)
    echo "Warning: $INSTALL_DIR is not on your PATH." >&2
    echo "Add this to ~/.zshrc:" >&2
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2
    ;;
esac

echo "Installing device log commands to $INSTALL_DIR (scripts=$SCRIPTS_HOME):"
install_wrapper flutter-device-logs scripts/debug/device-logs.sh
install_wrapper flutter-android-logcat scripts/debug/android-logcat.sh
install_wrapper flutter-ios-logs scripts/debug/ios-device-logs.sh
install_wrapper flutter-isolate-monitor scripts/launcher/open-isolate-monitor.sh

echo
echo "Done. Try:"
echo "  flutter-device-logs android"
echo "  flutter-device-logs ios"
echo "  flutter-isolate-monitor"
