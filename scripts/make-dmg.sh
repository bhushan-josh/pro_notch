#!/bin/bash
# Builds a release "Pro Notch.app" and packs it into build/ProNotch.dmg with an Applications shortcut.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT/build/Pro Notch.app" "$STAGE/Pro Notch.app"
ln -s /Applications "$STAGE/Applications"

DMG="$ROOT/build/ProNotch.dmg"
rm -f "$DMG"
hdiutil create -volname "Pro Notch" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
echo "Created $DMG"
