#!/bin/bash
set -e

cd "$(dirname "$0")"

# SwiftUI のマクロ（@State 等）は CommandLineTools だけではビルドできないため、
# xcode-select が CLT を指していても Xcode があればそちらを使う
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ] \
    && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "Building Pulstick..."
swift build -c release

APP_DIR="./build/Pulstick.app/Contents/MacOS"
mkdir -p "$APP_DIR"

cp Resources/Info.plist "./build/Pulstick.app/Contents/Info.plist"
mkdir -p "./build/Pulstick.app/Contents/Resources"
cp -R Resources/*.lproj "./build/Pulstick.app/Contents/Resources/"
cp ".build/release/Pulstick" "$APP_DIR/Pulstick"
chmod +x "$APP_DIR/Pulstick"

echo ""
echo "Build complete: ./build/Pulstick.app"
echo "Run with: open ./build/Pulstick.app"
