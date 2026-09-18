#!/bin/zsh
# Visual smoke test: builds (unless SKIP_BUILD=1), launches the app against a temporary THUBAN_CANVAS_HOME with the
# real Canvas credentials (read-only) and THUBAN_CANVAS_SMOKE=<output dir>; the app walks its screens, writes PNGs
# and exits. Credentials: pass CANVAS_HOST + CANVAS_TOKEN, or CANVAS_TOKEN_FILE (a file containing the token).
# Usage: scripts/smoke.sh [output-dir]      (default: .build/smoke)
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="${1:-$ROOT/.build/smoke}"
DERIVED="${DERIVED:-.build/DerivedData}"
APP="$ROOT/$DERIVED/Build/Products/Debug/Thuban Canvas.app/Contents/MacOS/Thuban Canvas"
LOG="${TMPDIR:-/tmp}/thuban-canvas-smoke.log"

if [[ "${SKIP_BUILD:-0}" != "1" || ! -x "$APP" ]]; then
  DERIVED="$DERIVED" scripts/build.sh || exit 1
fi

HOME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/thuban-canvas-smoke-home.XXXXXX")"
rm -rf "$OUT"; mkdir -p "$OUT"
if [[ -n "${CANVAS_TOKEN_FILE:-}" ]]; then CANVAS_TOKEN="$(cat "$CANVAS_TOKEN_FILE")"; fi
if [[ -n "${CANVAS_TOKEN:-}" ]]; then
  mkdir -p "$HOME_DIR"
  printf '{"host":"%s","token":"%s"}' "${CANVAS_HOST:-https://instructure.charlotte.edu}" "$CANVAS_TOKEN" > "$HOME_DIR/credentials.json"
  chmod 600 "$HOME_DIR/credentials.json"
fi
pkill -f "$APP" 2>/dev/null
echo "Smoke home: $HOME_DIR"
echo "Output:     $OUT"
THUBAN_CANVAS_SMOKE="$OUT" THUBAN_CANVAS_HOME="$HOME_DIR" "$APP" > "$LOG" 2>&1 &
PID=$!
for i in {1..180}; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "TIMEOUT: app still running after 180 s; killing"; kill "$PID" 2>/dev/null; STATUS=2
else
  wait "$PID"; STATUS=$?; echo "App exited with status $STATUS"
fi
echo "--- app output (last 40 lines of $LOG):"; tail -40 "$LOG"
echo "--- screenshots:"; ls -la "$OUT"/*.png 2>/dev/null || echo "(none)"
rm -rf "$HOME_DIR"
exit $STATUS
