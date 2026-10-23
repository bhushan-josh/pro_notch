#!/bin/bash
# Builds "Pro Notch.app" into ./build. Usage: scripts/build.sh [--run | --install] [--debug]
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
# scripts/create-signing-identity.sh creates "Dynamic Notch Local" in a project keychain; ad-hoc ("-") is the fallback.
IDENTITY="${NOTCH_SIGN_IDENTITY:-}"
KEYCHAIN_ARGS=()
SIGNING_KEYCHAIN="$ROOT/.signing/dynamic-notch.keychain-db"
if [[ -z "$IDENTITY" && -f "$SIGNING_KEYCHAIN" ]]; then
  security unlock-keychain -p "dynamic-notch-local" "$SIGNING_KEYCHAIN"
  IDENTITY="Dynamic Notch Local"
  KEYCHAIN_ARGS=(--keychain "$SIGNING_KEYCHAIN")
fi
IDENTITY="${IDENTITY:--}"

cd "$ROOT"
swift build -c "$CONFIG" --product ProNotch
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/Pro Notch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ProNotch" "$APP/Contents/MacOS/ProNotch"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Support/AppIcon.icns" ]]; then
  cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign "$IDENTITY" ${KEYCHAIN_ARGS[@]+"${KEYCHAIN_ARGS[@]}"} --entitlements "$ROOT/Support/ProNotch.entitlements" "$APP"
echo "Built $APP (signed with: $IDENTITY)"

case "$ACTION" in
  run)
    pkill -x ProNotch 2>/dev/null || true
    open "$APP"
    ;;
  install)
    pkill -x ProNotch 2>/dev/null || true
    rm -rf "/Applications/Pro Notch.app"
    ditto "$APP" "/Applications/Pro Notch.app"
    open "/Applications/Pro Notch.app"
    echo "Installed /Applications/Pro Notch.app"
    ;;
esac
