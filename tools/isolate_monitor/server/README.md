# Isolate Monitor server backends

Pick which language implements the monitor server (HTTP API, deploy, logs, VM).

| Backend | Path | Status |
|---------|------|--------|
| **Dart** | `dart/` (live code still at repo `bin/` + `lib/` until fully moved) | **Active** |
| **Go** | `go/` | **Active** — same React UI |
| **TypeScript** | `typescript/` | Scaffold — implement next |

## Preference

Written by the GUI switch or CLI:

- File: `../.backend-lang` (values: `dart` | `go` | `typescript`)
- CLI: `--backend dart|go|typescript`
- Env: `ISOLATE_MONITOR_BACKEND`

**Dart** and **Go** are runnable. TypeScript saves preference only until implemented.
