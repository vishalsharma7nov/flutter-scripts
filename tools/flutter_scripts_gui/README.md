# flutter-scripts GUI

React UI + Go backend for the interactive `flutter-scripts` catalog.

## Layout

| Path | Role |
|------|------|
| `server/go/` | Go HTTP API + static file server |
| `frontend/` | Vite + React source (Scripts + embedded Git tool) |
| `frontend/src/git-tool/` | **Git LLM** — how-to, troubleshoot catalog, optional Ollama analyze |
| `web/` | Built static UI (served by Go) |
| `shared/script_catalog.json` | Shared script labels/descriptions (Go catalog + keep in sync with CLI) |
| `bin/flutter_scripts_gui` | Built Go binary (created on first launch) |

## API

- `GET /api/status` — includes `git` repo snapshot + `ollama` availability
- `GET /api/git/repo` — live git status for the selected project
- `POST /api/git/analyze` — catalog + optional local LLM diagnosis
- `GET /api/scripts`
- `POST /api/project` — `{ "source": "<git-url|owner/repo|local-path>" }` clones (if needed) and switches project when Flutter-compatible
- `POST /api/run` — `{ "file": "build_android.sh", "args": ["--aab"] }`
- `POST /api/stop`
- `GET /api/logs` — SSE events (`log`, `started`, `exited`, `error`)
- `POST /api/localization/check` — `{ "mode": "hardcoded"|"full"|"suggestions", "path": [] }` runs ARB/hardcoded scan (JSON)

Default port: **8766** (isolate-monitor uses 8765).

### Git LLM (Ollama, optional)

Catalog matching works offline. For local LLM enrichment:

```bash
brew install ollama && ollama serve
ollama pull qwen2.5-coder:7b
```

Env: `GIT_LLM_MODEL` (default `qwen2.5-coder:7b`), `OLLAMA_HOST`.

### Project source examples

```text
https://github.com/org/my_flutter_app.git
git@github.com:org/my_flutter_app.git
org/my_flutter_app
~/StudioProjects/my_flutter_app
/Users/me/StudioProjects/my_flutter_app
```

Flutter check: `pubspec.yaml` with a `flutter:` section and a `lib/` directory.
Clones land in `~/StudioProjects/<repo>` when that folder exists, otherwise
`~/Documents/flutter-scripts-clones/<repo>`.

## Develop

```bash
# Backend
cd server/go
go run ./cmd/flutter_scripts_gui --scripts-dir ../../.. --project ~/StudioProjects/my_app --no-open

# Frontend (proxies /api → :8766)
cd frontend
npm install
npm run dev
```

Production UI build:

```bash
cd frontend && npm install && npm run build
```

## Launch

From any Flutter project:

```bash
flutter-scripts
# or
open-flutter-scripts-gui.sh --project "$PWD"
```

Use `flutter-scripts --cli` for the classic terminal picker.

## macOS app (double-click / Dock)

Build a Finder-launchable app and install it into `~/Applications`:

```bash
cd ~/Documents/flutter-scripts
./tools/flutter_scripts_gui/package-macos-app.sh --install
```

Then open **Flutter Scripts** from Applications (or drag it to the Dock).

- First local Gatekeeper prompt: right-click → **Open**.
- Quit the Dock icon to stop the GUI server.
- Rebuild after UI/Go changes with the same command.
