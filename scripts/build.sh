#!/bin/bash
# Builds "Dynamic Notch.app" into ./build. Usage: scripts/build.sh [--run | --install] [--debug]
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

# A stable identity keeps macOS privacy grants (Accessibility, Automation) across rebuilds.
# scripts/create-signing-identity.sh creates "Dynamic Notch Local"; ad-hoc ("-") is the fallback.
IDENTITY="${NOTCH_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]] && security find-certificate -c "Dynamic Notch Local" >/dev/null 2>&1; then
  IDENTITY="Dynamic Notch Local"
fi
IDENTITY="${IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --product DynamicNotch
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Dynamic Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DynamicNotch" "$APP/Contents/MacOS/DynamicNotch"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
  cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Support/DynamicNotch.entitlements" "$APP"
echo "Built $APP (signed with: $IDENTITY)"

case "$ACTION" in
  run)
    pkill -x DynamicNotch 2>/dev/null || true
    open "$APP"
    ;;
  install)
    pkill -x DynamicNotch 2>/dev/null || true
    rm -rf "/Applications/Dynamic Notch.app"
    ditto "$APP" "/Applications/Dynamic Notch.app"
    open "/Applications/Dynamic Notch.app"
    echo "Installed /Applications/Dynamic Notch.app"
    ;;
esac
