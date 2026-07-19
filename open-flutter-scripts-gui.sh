#!/usr/bin/env bash
# Root entrypoint → scripts/launcher/open-flutter-scripts-gui.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/launcher/open-flutter-scripts-gui.sh" "$@"
