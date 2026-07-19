#!/usr/bin/env bash
# Root entrypoint → scripts/launcher/flutter-scripts.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/launcher/flutter-scripts.sh" "$@"
