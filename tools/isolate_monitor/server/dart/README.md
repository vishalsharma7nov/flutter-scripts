# Dart backend (active)

Live isolate monitor server:

- Entry: `../../bin/isolate_monitor.dart`
- Library: `../../lib/src/`

This directory tracks the Dart implementation track. Prefer keeping new Dart server work under `../../lib/src/` until a full move into `server/dart/` is done.

## Run

```bash
cd ../..
fvm dart run bin/isolate_monitor.dart --port 8765 --project /path/to/app
```

Or via:

```bash
./open-isolate-monitor.sh --backend dart
```
