#!/usr/bin/env bash
# Compatibility launcher — Git LLM now lives in Flutter Scripts GUI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="${1:-${GIT_LLM_REPO:-$PWD}}"

echo "git-llm-tool is now the Git LLM tab inside Flutter Scripts GUI."
echo "Launching flutter_scripts_gui for: $REPO"

exec "$ROOT/open-flutter-scripts-gui.sh" --project "$REPO"
