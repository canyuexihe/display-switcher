#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/DisplaySwitcher.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
swiftc -O "$DIR/DisplaySwitcher.swift" -o "$APP/Contents/MacOS/DisplaySwitcher" \
  -framework AppKit -framework ServiceManagement
codesign --force --sign - "$APP"
echo "构建完成: $APP"