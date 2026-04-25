#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH=".build/DerivedData"
APP_PATH="$ROOT/$DERIVED_DATA_PATH/Build/Products/Debug/Gojo.app"

xcodebuild \
  -project Gojo.xcodeproj \
  -scheme Gojo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  >/tmp/gojo-smoke-build.log

test -d "$APP_PATH"

open -na "$APP_PATH"
sleep 5
pgrep -x Gojo >/dev/null
pkill -x Gojo || true
