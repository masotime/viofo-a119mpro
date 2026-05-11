#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/VIOFO A119M Pro.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$MODULE_CACHE_DIR"

swiftc \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  "$ROOT_DIR"/Sources/*.swift \
  -o "$MACOS_DIR/ViofoA119MPro"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "$APP_DIR"
