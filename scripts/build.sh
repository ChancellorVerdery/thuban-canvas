#!/bin/zsh
# Debug build of the app (ad-hoc signed, runs locally). Prints only errors/warnings from our sources and the result.
# DERIVED=<dir> overrides the DerivedData path (parallel builds); CONFIG=Release builds Release.
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData}"
LOG="${DERIVED}/xcodebuild.log"
mkdir -p "$DERIVED"
if [[ ! -d ThubanCanvas.xcodeproj || project.yml -nt ThubanCanvas.xcodeproj/project.pbxproj || "${REGEN:-0}" == "1" ]]; then
  xcodegen generate --quiet || exit 1
fi
xcodebuild -project ThubanCanvas.xcodeproj -scheme ThubanCanvas -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "ThubanCanvas/|ThubanCanvasCore/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -60
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG/Thuban Canvas.app"
exit $STATUS
