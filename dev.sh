#!/bin/bash
set -e
cd "$(dirname "$0")"

pkill -x Pulstick 2>/dev/null || true
sleep 0.3
swift build -c release 2>&1
./build.sh 2>&1 | tail -1
open ./build/Pulstick.app
