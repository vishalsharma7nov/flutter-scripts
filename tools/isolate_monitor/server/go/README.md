# Go backend (active)

Implements the isolate monitor HTTP API in Go and serves the same React UI from `../../web`.

## Run

```bash
cd tools/isolate_monitor/server/go
go run ./cmd/isolate_monitor --port 8765 --project /path/to/app --device DEVICE_ID --mode profile --lan
```

Or via launcher:

```bash
./open-isolate-monitor.sh --backend go
```

## Parity with Dart

| Feature | Status |
|---------|--------|
| React static UI | Yes |
| `/api/status`, `/api/logs`, `/api/events`, `/api/backend` | Yes |
| Flutter deploy / reinstall / hot reload / stop | Yes |
| Device logcat streaming | Yes |
| ADB devices connect/pair | Yes |
| Open file in editor | Yes |
| VM isolates list | Basic placeholder |
| Screen mirror | Not yet |

Restart exit code `100` matches Dart so the launcher can relaunch after a backend switch.
