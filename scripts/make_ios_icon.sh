#!/bin/zsh
# Regenerates CanvasiOS/Resources/Assets.xcassets/AppIcon.appiconset (1024 px, Brass dark plate) from the app's mark,
# using the same AppArt drawing code as the Mac icon (scripts/make_app_icon.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
cp scripts/make_ios_icon.swift "$TMP/main.swift"
swiftc -D APPICON_TOOL -o "$TMP/make_ios_icon" "$TMP/main.swift" \
  ThubanCanvas/Views/Components/AppArt.swift ThubanCanvas/Views/Components/AppArtSource.swift
DEST=CanvasiOS/Resources/Assets.xcassets/AppIcon.appiconset
mkdir -p "$DEST"
find "$DEST" -name "*.png" -delete
"$TMP/make_ios_icon" "$DEST"
rm -rf "$TMP"
