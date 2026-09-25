#!/bin/zsh
# Builds the iOS app for the simulator (unsigned) into .build/DerivedData-iOS. Prints only our errors/warnings.
#   CONFIG=Release scripts/ios_build.sh      Release build (default Debug)
#   DERIVED=<dir>                            private DerivedData
# Output: $DERIVED/Build/Products/<CONFIG>-iphonesimulator/Thuban Canvas.app
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
CONFIG="${CONFIG:-Debug}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
LOG="${DERIVED}/xcodebuild-ios.log"
mkdir -p "$DERIVED"
if [[ ! -d ThubanCanvas.xcodeproj || project.yml -nt ThubanCanvas.xcodeproj/project.pbxproj || "${REGEN:-0}" == "1" ]]; then
  xcodegen generate --quiet || exit 1
fi
xcodebuild -project ThubanCanvas.xcodeproj -scheme CanvasiOS -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build "$@" > "$LOG" 2>&1
STATUS=$?
grep -E "(error|warning): " "$LOG" | grep -E "CanvasiOS/|ThubanCanvas/|ThubanCanvasCore/|xcodebuild: error" | grep -v "DerivedData" | sort -u | head -80
grep -E "\*\* BUILD (SUCCEEDED|FAILED) \*\*" "$LOG" || echo "** BUILD RESULT UNKNOWN (see $LOG) **"
echo "App: $DERIVED/Build/Products/$CONFIG-iphonesimulator/Thuban Canvas.app"
exit $STATUS
