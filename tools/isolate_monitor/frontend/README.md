# Isolate Monitor UI (React)

Source for the monitor web GUI. Built assets are written to `../web/` and served by the Dart Shelf server.

## Develop

```bash
cd frontend
npm install
npm run dev   # http://localhost:5173 — proxies /api to :8765
```

Start the isolate monitor on port 8765 in another terminal.

## Build (required before shipping / after UI changes)

```bash
cd frontend
npm run build
```

This replaces `../web/index.html` and `../web/assets/*`.

`open-isolate-monitor.sh` runs `npm run build` when `node_modules` exists or on first launch if npm is available.
