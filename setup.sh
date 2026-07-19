#!/usr/bin/env bash
# Root entrypoint → scripts/setup/setup.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/setup/setup.sh" "$@"
