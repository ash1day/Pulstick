#!/bin/bash
# LP のスクリーンショット（英語・日本語 × ライト・ダーク）を作り直し、
# HTML の img の高さ属性も合わせる。アプリは起動せず、音も鳴らない
set -e
cd "$(dirname "$0")/.."

./build.sh > /dev/null
APP=build/Pulstick.app/Contents/MacOS/Pulstick
OPTIONS=(--trainer --gap --log)

render() { # 言語 出力先ディレクトリ
    "$APP" --snapshot "$2/screenshot.png" "${OPTIONS[@]}" -AppleLanguages "($1)"
    "$APP" --snapshot "$2/screenshot-dark.png" "${OPTIONS[@]}" --dark -AppleLanguages "($1)"
    local height
    # 2x で書き出しているので半分にする。HTML の属性は整数にしたいので切り上げる
    height=$(sips -g pixelHeight "$2/screenshot.png" | awk '/pixelHeight/ { printf "%d", ($2 + 1) / 2 }')
    sed -i '' "s/width=\"320\" height=\"[0-9]*\"/width=\"320\" height=\"$height\"/" "$2/index.html"
    echo "$2: 320x$height"
}

render en docs
render ja docs/ja
