#!/bin/zsh
# Release build of the iOS app installed into the simulator "Thuban iPhone" (iPhone 17 on the newest iOS runtime;
# created if missing, booted, app launched). If `xcrun devicectl list devices` shows a paired iPhone AND
# DEVELOPMENT_TEAM is set, also makes a signed device build and installs it on that iPhone; otherwise prints how.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
BUNDLE="org.thuban.canvas.ios"
DERIVED=".build/DerivedData-iOS-Release"

CONFIG=Release DERIVED="$DERIVED" scripts/ios_build.sh || exit 1
APP="$ROOT/$DERIVED/Build/Products/Release-iphonesimulator/Thuban Canvas.app"

RUNTIME="$(xcrun simctl list runtimes -j | /usr/bin/python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["runtimes"] if r.get("platform")=="iOS" and r.get("isAvailable")]
rs.sort(key=lambda r:[int(x) for x in r["version"].split(".")])
print(rs[-1]["identifier"] if rs else "")')"
[[ -z "$RUNTIME" ]] && { echo "No iOS simulator runtime installed"; exit 1; }

UDID="$(xcrun simctl list devices -j | /usr/bin/python3 -c '
import json,sys
for runtime,devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["name"]=="Thuban iPhone" and d.get("isAvailable"): print(d["udid"]); raise SystemExit
')"
if [[ -z "$UDID" ]]; then
  TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
  xcrun simctl list devicetypes | grep -q "($TYPE)" || TYPE="$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c '
import json,sys,re
ts=[t for t in json.load(sys.stdin)["devicetypes"] if re.search(r"^iPhone [0-9]+$",t["name"])]
print(ts[-1]["identifier"] if ts else "")')"
  UDID="$(xcrun simctl create "Thuban iPhone" "$TYPE" "$RUNTIME")" || exit 1
  echo "Created simulator Thuban iPhone ($UDID)"
fi
xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" || exit 1
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
echo "Installed on simulator Thuban iPhone ($UDID). Open Simulator.app to use it."

# Physical iPhone: only with a paired device and a signing team.
DEVICES_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1
DEVICE_ID="$(/usr/bin/python3 -c '
import json,sys
try: data=json.load(open(sys.argv[1]))
except Exception: raise SystemExit
for d in data.get("result",{}).get("devices",[]):
    hw=d.get("hardwareProperties",{}); cp=d.get("connectionProperties",{})
    if hw.get("deviceType")=="iPhone" and cp.get("pairingState")=="paired":
        print(d.get("identifier","")); break
' "$DEVICES_JSON")"
rm -f "$DEVICES_JSON"
if [[ -n "$DEVICE_ID" && -n "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Building a signed device build for team $DEVELOPMENT_TEAM…"
  LOG="$DERIVED/xcodebuild-device.log"
  xcodebuild -project ThubanCanvas.xcodeproj -scheme CanvasiOS -configuration Release -derivedDataPath "$DERIVED" \
    -sdk iphoneos -destination 'generic/platform=iOS' -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic build > "$LOG" 2>&1 || { echo "Device build failed (see $LOG)"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE_ID" "$ROOT/$DERIVED/Build/Products/Release-iphoneos/Thuban Canvas.app" || exit 1
  echo "Installed on iPhone $DEVICE_ID"
else
  echo "Device install skipped. To install on your iPhone:"
  echo "  1. Pair it once in Xcode (Window › Devices and Simulators) and enable Developer Mode on the phone."
  echo "  2. Add your Apple ID in Xcode › Settings › Accounts and note its Team ID."
  echo "  3. Run: DEVELOPMENT_TEAM=<TeamID> scripts/ios_install.sh"
  [[ -z "$DEVICE_ID" ]] && echo "  (no paired iPhone found by 'xcrun devicectl list devices')"
  [[ -z "${DEVELOPMENT_TEAM:-}" ]] && echo "  (DEVELOPMENT_TEAM is not set)"
fi
