#!/usr/bin/env bash
set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/repo_bootstrap.sh
source "$_SCRIPT_DIR/../../lib/repo_bootstrap.sh"

PACKAGES_ROOT="${PACKAGES_ROOT:-$HOME/Documents/flutter-packages}"
PACKAGES_LIST="${PACKAGES_LIST:-$_REPO_ROOT/packages.list}"
UPDATE=false

usage() {
  cat <<'EOF'
Clone shared Flutter packages for local path overrides.

Usage:
  flutter-setup-packages [--update] [--help]

Options:
  --update   Run git pull --ff-only in existing clones instead of skipping them
  --help     Show this help

Environment:
  PACKAGES_ROOT    Target directory (default: ~/Documents/flutter-packages)
  PACKAGES_LIST    Manifest file (default: ./packages.list next to this script)

Manifest format (one package per line):
  https://github.com/org/my_package.git|my_package
  https://github.com/org/native_plugin.git|native/my_plugin

Copy config/packages.list.example to packages.list (repo root) and edit URLs.

After this script, run from your app repo:
  fvm flutter pub get
EOF
}

clone_or_update() {
  local url="$1"
  local dest="$2"
  local name
  name="$(basename "$dest")"

  if [[ -d "$dest/.git" ]]; then
    if [[ "$UPDATE" == true ]]; then
      echo "Updating $name..."
      git -C "$dest" pull --ff-only
    else
      echo "already cloned: $name"
    fi
    return
  fi

  if [[ -e "$dest" ]]; then
    echo "error: $dest exists but is not a git repository" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dest")"
  echo "Cloning $name..."
  git clone "$url" "$dest"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      UPDATE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required but not installed" >&2
  exit 1
fi

if [[ ! -f "$PACKAGES_LIST" ]]; then
  echo "Missing package manifest: $PACKAGES_LIST" >&2
  echo "Copy `config/packages.list.example` to `packages.list` at the repo root and edit URLs for your org.
" >&2
  exit 1
fi

mkdir -p "$PACKAGES_ROOT"
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  if [[ "$line" != *"|"* ]]; then
    echo "Invalid manifest line (expected url|dest): $line" >&2
    exit 1
  fi
  url="${line%%|*}"
  dest_name="${line#*|}"
  clone_or_update "$url" "$PACKAGES_ROOT/$dest_name"
  count=$((count + 1))
done <"$PACKAGES_LIST"

if [[ "$count" -eq 0 ]]; then
  echo "No packages listed in: $PACKAGES_LIST" >&2
  exit 1
fi

echo
echo "Done. Packages are in: $PACKAGES_ROOT"
echo "Next: fvm flutter pub get"
