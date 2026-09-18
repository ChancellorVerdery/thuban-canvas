#!/bin/zsh
# Regenerates the Xcode project after adding/removing source files.
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"
mkdir -p ThubanCanvas/Resources/web
xcodegen generate --quiet
