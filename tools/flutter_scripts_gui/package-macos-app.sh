#!/usr/bin/env bash
#
# Build a double-clickable macOS app for the flutter-scripts GUI.
#
# Usage:
#   ./tools/flutter_scripts_gui/package-macos-app.sh
#   ./tools/flutter_scripts_gui/package-macos-app.sh --install
#
# Result:
#   tools/flutter_scripts_gui/dist/Flutter Scripts.app
#   (with --install) also copied to ~/Applications/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_HOME="$(cd "$SCRIPT_DIR/../.." && pwd)"
GO_DIR="$SCRIPT_DIR/server/go"
FRONTEND_DIR="$SCRIPT_DIR/frontend"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="Flutter Scripts"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
BIN_NAME="flutter_scripts_gui"
INSTALL="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL="true"
      shift
      ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This packaging script only supports macOS." >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required (brew install go)." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to build the React UI." >&2
  exit 1
fi

echo "==> Building React UI…"
(
  cd "$FRONTEND_DIR"
  if [[ ! -d node_modules ]]; then
    npm install
  fi
  npm run build
)

WEB_INDEX="$SCRIPT_DIR/web/index.html"
if [[ ! -f "$WEB_INDEX" ]]; then
  echo "ERROR: UI build did not produce $WEB_INDEX" >&2
  exit 1
fi
# Ensure the built bundle is newer than source (packaged app uses checkout web/).
NEWEST_SRC="$(find "$FRONTEND_DIR/src" -type f \( -name '*.tsx' -o -name '*.ts' -o -name '*.css' \) -print0 | xargs -0 stat -f '%m' 2>/dev/null | sort -nr | head -1 || true)"
WEB_MTIME="$(stat -f '%m' "$WEB_INDEX")"
if [[ -n "${NEWEST_SRC:-}" && "$WEB_MTIME" -lt "$NEWEST_SRC" ]]; then
  echo "ERROR: $WEB_INDEX is older than frontend/src — UI may be stale." >&2
  exit 1
fi
ASSET_JS="$(find "$SCRIPT_DIR/web/assets" -name 'index-*.js' | head -1 || true)"
if [[ -z "$ASSET_JS" ]]; then
  echo "ERROR: No web/assets/index-*.js after build." >&2
  exit 1
fi
echo "    OK: web UI ready ($(basename "$ASSET_JS"))"

echo "==> Building Go binary (macOS $(uname -m))…"
mkdir -p "$SCRIPT_DIR/bin"
(
  cd "$GO_DIR"
  go build -ldflags="-s -w" -o "$SCRIPT_DIR/bin/$BIN_NAME" ./cmd/flutter_scripts_gui
)

echo "==> Assembling ${APP_NAME}.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Baked-in path to the flutter-scripts checkout so the app always finds scripts.
cat > "$APP_DIR/Contents/MacOS/${APP_NAME}" <<EOF
#!/bin/bash
set -euo pipefail

# flutter-scripts home (resolved when the .app was packaged)
SCRIPTS_HOME="${SCRIPTS_HOME}"
TOOL_DIR="\$SCRIPTS_HOME/tools/flutter_scripts_gui"
BIN="\$TOOL_DIR/bin/${BIN_NAME}"
PORT="\${FLUTTER_SCRIPTS_GUI_PORT:-8766}"
PROJECT_DIR="\${PROJECT_ROOT:-\$HOME/StudioProjects}"

if [[ ! -x "\$BIN" ]]; then
  osascript -e "display alert \\"Flutter Scripts\\" message \\"Missing binary at \$BIN. Re-run package-macos-app.sh.\\" as critical"
  exit 1
fi

if [[ ! -f "\$TOOL_DIR/web/index.html" ]]; then
  osascript -e "display alert \\"Flutter Scripts\\" message \\"Missing UI at \$TOOL_DIR/web. Re-run package-macos-app.sh.\\" as critical"
  exit 1
fi

# Prefer current StudioProjects folder as start cwd when present.
if [[ ! -d "\$PROJECT_DIR" ]]; then
  PROJECT_DIR="\$HOME"
fi

# If another instance is already up, just bring the browser forward.
if curl -fsS "http://127.0.0.1:\${PORT}/api/status" >/dev/null 2>&1; then
  open "http://127.0.0.1:\${PORT}/"
  exit 0
fi

# Soft-close any stale listener on our port.
if lsof -tiTCP:"\$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  kill \$(lsof -tiTCP:"\$PORT" -sTCP:LISTEN) 2>/dev/null || true
  sleep 0.3
fi

"\$BIN" \\
  --port "\$PORT" \\
  --host 127.0.0.1 \\
  --scripts-dir "\$SCRIPTS_HOME" \\
  --project "\$PROJECT_DIR" \\
  --open &
GUI_PID=\$!

cleanup() {
  if kill -0 "\$GUI_PID" 2>/dev/null; then
    kill "\$GUI_PID" 2>/dev/null || true
    wait "\$GUI_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Wait until ready, then open browser (binary may also open — duplicate refresh is fine).
for _ in \$(seq 1 60); do
  if curl -fsS "http://127.0.0.1:\${PORT}/api/status" >/dev/null 2>&1; then
    open "http://127.0.0.1:\${PORT}/"
    break
  fi
  if ! kill -0 "\$GUI_PID" 2>/dev/null; then
    osascript -e "display alert \\"Flutter Scripts\\" message \\"GUI server exited early.\\" as critical"
    exit 1
  fi
  sleep 0.1
done

# Keep the .app process alive while the server runs (Dock icon stays present).
wait "\$GUI_PID"
EOF
chmod +x "$APP_DIR/Contents/MacOS/${APP_NAME}"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.flutterscripts.gui</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
EOF

# Generate a simple green marker icon with Python (stdlib only).
ICONSET="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
python3 - "$ICONSET" <<'PY'
import struct, sys, zlib
from pathlib import Path

iconset = Path(sys.argv[1])
iconset.mkdir(parents=True, exist_ok=True)

def write_png(size: int, path: Path) -> None:
    rows = []
    cx = cy = (size - 1) / 2.0
    radius = size * 0.34
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            dx, dy = x - cx, y - cy
            if (dx * dx + dy * dy) <= (radius * radius):
                row += bytes((61, 214, 140, 255))
            else:
                row += bytes((28, 32, 48, 255))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)

for s in (16, 32, 64, 128, 256, 512, 1024):
    write_png(s, iconset / f"icon_{s}x{s}.png")
    if s <= 512:
        write_png(s * 2, iconset / f"icon_{s}x{s}@2x.png")
print("iconset ready:", iconset)
PY

if command -v iconutil >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
else
  echo "iconutil not found — app will use the default macOS icon." >&2
fi

# Clear quarantine so first-run Gatekeeper is less painful for local builds.
xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true

echo ""
echo "Built: $APP_DIR"

if [[ "$INSTALL" == "true" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
  rm -rf "$DEST/${APP_NAME}.app"
  cp -R "$APP_DIR" "$DEST/"
  xattr -dr com.apple.quarantine "$DEST/${APP_NAME}.app" 2>/dev/null || true
  echo "Installed: $DEST/${APP_NAME}.app"
  open "$DEST"
  echo ""
  echo "Double-click \"${APP_NAME}\" in Applications (or keep it in the Dock)."
else
  open "$DIST_DIR"
  echo ""
  echo "Double-click \"${APP_NAME}.app\" to run."
  echo "To install into ~/Applications:"
  echo "  $0 --install"
fi
