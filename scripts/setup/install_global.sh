#!/usr/bin/env bash
#
# Install Flutter scripts globally (wrappers on PATH).
#
# Usage:
#   ./install_global.sh
#   ./install_global.sh --in-place
#   ./install_global.sh --dest ~/Documents/flutter-scripts
#   ./install_global.sh --bin-dir ~/.local/bin
#
# Creates/updates:
#   ~/.local/bin/flutter-*   (wrappers → this clone under scripts/…)
#
# After install, add to ~/.zshrc:
#   source "${FLUTTER_SCRIPTS_HOME:-$HOME/Documents/flutter-scripts}/shell-profile.snippet"

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"
SRC_DIR="$_REPO_ROOT"
DEST_DIR="${FLUTTER_SCRIPTS_HOME:-$HOME/Documents/flutter-scripts}"
BIN_DIR="${FLUTTER_BIN_DIR:-$HOME/.local/bin}"
IN_PLACE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in-place)
      IN_PLACE="true"
      DEST_DIR="$SRC_DIR"
      shift
      ;;
    --dest)
      DEST_DIR="$2"
      shift 2
      ;;
    --bin-dir)
      BIN_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$DEST_DIR" "$BIN_DIR"

echo "Installing scripts:"
echo "  from: $SRC_DIR"
if [[ "$IN_PLACE" == "true" ]]; then
  echo "  mode: in-place (wrappers use this clone; no copy)"
  DEST_DIR="$SRC_DIR"
else
  echo "  to:   $DEST_DIR"
fi
echo "  bin:  $BIN_DIR"

if [[ "$IN_PLACE" != "true" ]]; then
  rsync -a --delete \
    --exclude '.DS_Store' \
    --exclude 'backups/' \
    "$SRC_DIR/" "$DEST_DIR/"
fi

declare -a LINK_NAMES=(
  flutter-scripts
  flutter-scripts-gui
  flutter-build-android
  flutter-build-ios
  flutter-clear-pub-cache
  flutter-get-iam-token
  flutter-inspect-apk
  flutter-classify-version-bump
  flutter-build-mobile
  flutter-setup-packages
  flutter-device-logs
  flutter-android-logcat
  flutter-ios-logs
  flutter-isolate-monitor
  flutter-build-both-release-apks
  release-package
)
declare -a LINK_TARGETS=(
  scripts/launcher/flutter-scripts.sh
  scripts/launcher/open-flutter-scripts-gui.sh
  scripts/build/build_android.sh
  scripts/build/build_ios.sh
  scripts/deps/clear_pub_cache.sh
  scripts/debug/get_iam_token.sh
  scripts/debug/inspect_apk_environment.sh
  scripts/build/classify-version-bump.sh
  scripts/build/build_mobile_release.sh
  scripts/deps/setup_packages.sh
  scripts/debug/device-logs.sh
  scripts/debug/android-logcat.sh
  scripts/debug/ios-device-logs.sh
  scripts/launcher/open-isolate-monitor.sh
  scripts/build/build_both_release_apks.sh
  scripts/git/release_package.sh
)

for i in "${!LINK_NAMES[@]}"; do
  name="${LINK_NAMES[$i]}"
  target="$DEST_DIR/${LINK_TARGETS[$i]}"
  link="$BIN_DIR/$name"
  if [[ ! -f "$target" ]]; then
    echo "Skip missing script: $target" >&2
    continue
  fi
  chmod +x "$target"
  rm -f "$link"
  cat >"$link" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$target" "\$@"
EOF
  chmod +x "$link"
  echo "  linked $name -> $target"
done

PROFILE_SNIPPET="$DEST_DIR/shell-profile.snippet"
cat >"$PROFILE_SNIPPET" <<'EOF'
# Flutter global scripts — portable shell setup.
# After git clone, run: ./setup.sh
#
# Add to ~/.zshrc or ~/.bashrc:
#   source "/path/to/scripts/shell-profile.snippet"

_flutter_scripts_snippet_path() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "${BASH_SOURCE[0]}"
    return 0
  fi
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    printf '%s\n' "${(%):-%x}"
    return 0
  fi
  printf '%s\n' "$0"
}

if [[ -z "${SCRIPTS_DIR:-}" ]]; then
  _flutter_scripts_snippet="$(_flutter_scripts_snippet_path)"
  export SCRIPTS_DIR="$(cd "$(dirname "$_flutter_scripts_snippet")" && pwd)"
  unset _flutter_scripts_snippet
fi

if [[ -f "${SCRIPTS_DIR}/setup.env" ]]; then
  # shellcheck source=/dev/null
  source "${SCRIPTS_DIR}/setup.env"
fi

_flutter_scripts_bin_dir="${FLUTTER_BIN_DIR:-$HOME/.local/bin}"
if [[ -d "$_flutter_scripts_bin_dir" ]]; then
  case ":$PATH:" in
    *":$_flutter_scripts_bin_dir:"*) ;;
    *) export PATH="$_flutter_scripts_bin_dir:$PATH" ;;
  esac
fi
unset _flutter_scripts_bin_dir

unset -f _flutter_scripts_snippet_path 2>/dev/null || true
EOF

echo ""
if [[ "$IN_PLACE" == "true" ]]; then
  echo "Installed in-place from: $DEST_DIR"
else
  echo "Installed copy to: $DEST_DIR"
fi
echo ""
echo "Add to ~/.zshrc (portable — uses \$HOME, works on any machine):"
echo '  export FLUTTER_SCRIPTS_HOME="'"$DEST_DIR"'"'
echo '  source "${FLUTTER_SCRIPTS_HOME}/shell-profile.snippet"'
echo ""
echo "Or run ./setup.sh after git clone for full bootstrap."
