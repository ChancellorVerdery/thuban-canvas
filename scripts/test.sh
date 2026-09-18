#!/bin/zsh
# Unit tests for the core package.
set -uo pipefail
cd "$(dirname "$0")/../Packages/ThubanCanvasCore"
swift test 2>&1 | grep -E "error|failed|Executed|Build complete" | tail -20
