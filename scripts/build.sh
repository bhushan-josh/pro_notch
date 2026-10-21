#!/bin/bash
# Builds Notch.app into ./build. Usage: scripts/build.sh [--run | --install] [--debug]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG=release
ACTION=""
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug ;;
    --run) ACTION=run ;;
    --install) ACTION=install ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Set NOTCH_SIGN_IDENTITY to a stable code-signing identity to keep privacy grants across rebuilds.
IDENTITY="${NOTCH_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --product Notch
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Notch" "$APP/Contents/MacOS/Notch"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
  cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Support/Notch.entitlements" "$APP"
echo "Built $APP"

case "$ACTION" in
  run)
    pkill -x Notch 2>/dev/null || true
    open "$APP"
    ;;
  install)
    pkill -x Notch 2>/dev/null || true
    rm -rf /Applications/Notch.app
    ditto "$APP" /Applications/Notch.app
    open /Applications/Notch.app
    echo "Installed /Applications/Notch.app"
    ;;
esac
