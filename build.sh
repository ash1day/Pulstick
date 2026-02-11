#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Pulstick..."
swift build -c release

APP_DIR="./build/Pulstick.app/Contents/MacOS"
mkdir -p "$APP_DIR"
mkdir -p "./build/Pulstick.app/Contents"

cp Resources/Info.plist "./build/Pulstick.app/Contents/Info.plist"
cp ".build/release/Pulstick" "$APP_DIR/Pulstick"
chmod +x "$APP_DIR/Pulstick"

echo ""
echo "Build complete: ./build/Pulstick.app"
echo "Run with: open ./build/Pulstick.app"
