#!/usr/bin/env bash
# Heuristic: scan Flutter AOT binary inside an APK for API host substrings.
# We search the raw libapp.so with grep -a (not `strings`): on macOS, `strings`
# often misses host literals that are still present as contiguous UTF-8 bytes.
# This is not cryptographic proof — tree-shaking can leave both prod and dev
# literals in libapp.so. When the result is ambiguous, confirm from the build
# machine (git + lib/main.dart) or by observing network traffic after install.

set -euo pipefail

PROD_PATTERN="${INSPECT_APK_PROD_PATTERN:-iam.api.prod.example.com}"
DEV_PATTERN="${INSPECT_APK_DEV_PATTERN:-iam.api.dev.example.com}"

usage() {
  cat <<EOF
Usage:
  flutter-inspect-apk /path/to/app.apk

Scans lib/*/libapp.so for host substrings embedded at compile time.

Configure patterns (per app):
  INSPECT_APK_PROD_PATTERN  default: iam.api.prod.example.com
  INSPECT_APK_DEV_PATTERN   default: iam.api.dev.example.com
EOF
}

if [[ $# -lt 1 || "${1:-}" == -h || "${1:-}" == --help ]]; then
  usage
  exit 1
fi

APK="$1"
if [[ ! -f "$APK" ]]; then
  echo "Not a file: $APK" >&2
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

found_so=""
for so_path in lib/arm64-v8a/libapp.so lib/armeabi-v7a/libapp.so lib/x86_64/libapp.so; do
  if unzip -l "$APK" "$so_path" >/dev/null 2>&1; then
    unzip -p "$APK" "$so_path" >"$tmp"
    if [[ -s "$tmp" ]]; then
      found_so=$so_path
      break
    fi
  fi
done

if [[ -z "$found_so" ]]; then
  echo "Could not read libapp.so from APK (expected Flutter app layout)." >&2
  exit 1
fi

echo "Scanned: $APK"
echo "Binary:  $found_so"
echo "Prod pattern: $PROD_PATTERN"
echo "Dev pattern:  $DEV_PATTERN"
echo ""

if grep -aFq "$PROD_PATTERN" "$tmp"; then prod_iam=1; else prod_iam=0; fi
if grep -aFq "$DEV_PATTERN" "$tmp"; then dev_iam=1; else dev_iam=0; fi

if (( prod_iam == 1 && dev_iam == 0 )); then
  echo "Guess: PRODUCTION build (found prod host, no dev host in libapp.so)."
elif (( dev_iam == 1 && prod_iam == 0 )); then
  echo "Guess: DEVELOPMENT build (found dev host, no prod host in libapp.so)."
elif (( prod_iam == 1 && dev_iam == 1 )); then
  echo "Ambiguous: both prod and dev host strings appear in libapp.so."
  echo "  The compiler may retain unused switch branches. Prefer build records"
  echo "  (commit + lib/main.dart const env) or network inspection on device."
else
  echo "Unknown: neither prod nor dev host string found in libapp.so."
  echo "  Hosts may have changed, or set INSPECT_APK_PROD_PATTERN / INSPECT_APK_DEV_PATTERN."
fi

echo ""
echo "Optional: search for Adyen mode prefix (may have false positives):"
if grep -aEq 'live_[A-Za-z0-9_]+' "$tmp" 2>/dev/null; then
  echo "  - Found at least one substring matching live_* (prod Adyen pattern)."
fi
if grep -aEq 'test_[A-Za-z0-9_]+' "$tmp" 2>/dev/null; then
  echo "  - Found at least one substring matching test_* (sandbox Adyen pattern)."
fi
