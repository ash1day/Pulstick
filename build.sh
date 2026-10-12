#!/bin/bash
set -e

cd "$(dirname "$0")"

# SwiftUI のマクロ（@State 等）は CommandLineTools だけではビルドできないため、
# xcode-select が CLT を指していても Xcode があればそちらを使う
if [ -z "$DEVELOPER_DIR" ] && [ -d /Applications/Xcode.app ] \
    && [[ "$(xcode-select -p)" == *CommandLineTools* ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# UNIVERSAL=1 で Apple Silicon と Intel の両方で動くバイナリを作る（配布用。ビルドは遅くなる）
if [ -n "$UNIVERSAL" ]; then
    echo "Building Pulstick (universal)..."
    swift build -c release --arch arm64 --arch x86_64
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Pulstick"
else
    echo "Building Pulstick..."
    swift build -c release
    BINARY=".build/release/Pulstick"
fi

APP_DIR="./build/Pulstick.app/Contents/MacOS"
mkdir -p "$APP_DIR"

cp Resources/Info.plist "./build/Pulstick.app/Contents/Info.plist"
mkdir -p "./build/Pulstick.app/Contents/Resources"
cp -R Resources/*.lproj "./build/Pulstick.app/Contents/Resources/"
cp Resources/AppIcon.icns "./build/Pulstick.app/Contents/Resources/"
cp "$BINARY" "$APP_DIR/Pulstick"
chmod +x "$APP_DIR/Pulstick"

# アドホック署名でバンドル全体（Info.plist やリソース）を封印する。
# 署名がないと、ダウンロードした zip から開いたときに「壊れている」と表示されることがある
codesign --force --deep --sign - ./build/Pulstick.app

echo ""
echo "Build complete: ./build/Pulstick.app"
echo "Run with: open ./build/Pulstick.app"
