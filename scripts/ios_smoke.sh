#!/bin/zsh
# Offline visual smoke test for the iOS app. Boots its OWN simulator ("Thuban Canvas Smoke", iPhone 17 on the newest
# iOS runtime; created if missing), installs a Debug build, and launches the app once per scene with
# SIMCTL_CHILD_THUBAN_CANVAS_SMOKE_SCENE=<scene>. In smoke mode the app runs on the built-in demo account through a
# fake transport (no network, nothing written to Canvas, throwaway home), navigates to the scene and writes a ready
# marker; the script then saves `xcrun simctl io … screenshot` PNGs into the output folder.
# Also runs dark-mode shots and (unless IPAD=0) an iPad pass on "Thuban Canvas Smoke iPad".
#   scripts/ios_smoke.sh [out-dir]        default .build/ios-smoke
#   SKIP_BUILD=1  reuse the last build     SCENES="home grades"  only these scenes     KEEP_BOOTED=1  leave simulators on
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/.build/ios-smoke}"
DERIVED="${DERIVED:-.build/DerivedData-iOS}"
APP="$ROOT/$DERIVED/Build/Products/Debug-iphonesimulator/Thuban Canvas.app"
BUNDLE="org.thuban.canvas.ios"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -d "$APP" ]]; then
  DERIVED="$DERIVED" scripts/ios_build.sh || exit 1
fi

# Newest iOS runtime (26.5 on this Mac).
RUNTIME="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("platform")=="iOS" and r.get("isAvailable")]
rs.sort(key=lambda r:[int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')"
[[ -z "$RUNTIME" ]] && { echo "No iOS simulator runtime installed"; exit 1; }

# ensure_device <name> <preferred device type id> <fallback name pattern>
ensure_device() {
  local name="$1" type="$2" pattern="$3"
  local udid
  udid="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json,sys
name=sys.argv[1]
for runtime,devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["name"]==name and d.get("isAvailable"): print(d["udid"]); raise SystemExit
' "$name")"
  if [[ -z "$udid" ]]; then
    if ! xcrun simctl list devicetypes | grep -q "($type)"; then
      type="$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys,re
pat=sys.argv[1]
ts=[t for t in json.load(sys.stdin)["devicetypes"] if re.search(pat,t["name"])]
print(ts[-1]["identifier"] if ts else "")' "$pattern")"
    fi
    udid="$(xcrun simctl create "$name" "$type" "$RUNTIME")" || return 1
  fi
  echo "$udid"
}

# shoot <udid> <scene> <file> [appearance] [scheme]
shoot() {
  local udid="$1" scene="$2" file="$3" appearance="${4:-light}" scheme="${5:-}"
  local data marker
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
  data="$(xcrun simctl get_app_container "$udid" "$BUNDLE" data 2>/dev/null)"
  marker="$data/Library/Caches/smoke-ready"
  rm -f "$marker"
  SIMCTL_CHILD_THUBAN_CANVAS_SMOKE_SCENE="$scene" SIMCTL_CHILD_THUBAN_CANVAS_SMOKE_APPEARANCE="$appearance" \
    SIMCTL_CHILD_THUBAN_CANVAS_SMOKE_SCHEME="$scheme" xcrun simctl launch "$udid" "$BUNDLE" >/dev/null || { echo "  launch failed: $scene"; return 1; }
  for i in {1..60}; do [[ -f "$marker" ]] && break; sleep 0.5; done
  if [[ ! -f "$marker" ]]; then echo "  TIMEOUT waiting for $scene"; FAILED=1; fi
  sleep 0.6
  xcrun simctl io "$udid" screenshot --type=png "$OUT/$file" >/dev/null 2>&1 || { echo "  screenshot failed: $scene"; FAILED=1; }
  local note="$(cat "$marker" 2>/dev/null)"
  [[ "$note" == *"blockedWrites=0"* ]] || { [[ -n "$note" ]] && echo "  WRITE ATTEMPT: $note"; [[ -n "$note" ]] && FAILED=1; }
  echo "  $file"
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1
}

prepare() {
  local udid="$1"
  xcrun simctl boot "$udid" >/dev/null 2>&1
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1
  sleep "${WARMUP:-8}"   # let first-boot system banners pass before the first shot
  xcrun simctl ui "$udid" appearance light >/dev/null 2>&1
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 >/dev/null 2>&1
  xcrun simctl uninstall "$udid" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl install "$udid" "$APP" || return 1
}

wanted() { [[ -z "${SCENES:-}" ]] || [[ " $SCENES " == *" $1 "* ]]; }

rm -rf "$OUT"; mkdir -p "$OUT"
FAILED=0

PHONE="$(ensure_device "Thuban Canvas Smoke" "com.apple.CoreSimulator.SimDeviceType.iPhone-17" "^iPhone [0-9]+$")" || exit 1
echo "iPhone simulator: $PHONE ($RUNTIME)"
prepare "$PHONE" || exit 1
N=0
for scene in home home-swipe courses calendar calendar-month inbox conversation course modules assignment assignments \
             grades announcement syllabus people past-semesters settings file connect; do
  wanted "$scene" || continue
  N=$((N+1)); shoot "$PHONE" "$scene" "$(printf '%02d' $N)-$scene.png"
done
for scene in home courses calendar inbox course assignment grades settings; do
  wanted "$scene" || continue
  N=$((N+1)); shoot "$PHONE" "$scene" "$(printf '%02d' $N)-$scene-dark.png" dark
done
if wanted "home"; then N=$((N+1)); shoot "$PHONE" home "$(printf '%02d' $N)-home-cobalt-dark.png" dark cobalt; fi
[[ "${KEEP_BOOTED:-0}" == "1" ]] || xcrun simctl shutdown "$PHONE" >/dev/null 2>&1

if [[ "${IPAD:-1}" == "1" ]]; then
  PAD="$(ensure_device "Thuban Canvas Smoke iPad" "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB" "^iPad Pro 13")" || exit 1
  echo "iPad simulator: $PAD"
  prepare "$PAD" || exit 1
  for scene in ipad ipad-home ipad-grades; do
    wanted "$scene" || wanted "ipad-all" || [[ -z "${SCENES:-}" ]] || continue
    N=$((N+1)); shoot "$PAD" "$scene" "$(printf '%02d' $N)-$scene.png"
  done
  if [[ -z "${SCENES:-}" ]]; then N=$((N+1)); shoot "$PAD" ipad "$(printf '%02d' $N)-ipad-dark.png" dark; fi
  [[ "${KEEP_BOOTED:-0}" == "1" ]] || xcrun simctl shutdown "$PAD" >/dev/null 2>&1
fi

echo "--- screenshots in $OUT:"
ls "$OUT"
exit $FAILED
