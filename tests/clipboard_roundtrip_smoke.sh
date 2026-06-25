#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH=".build/DerivedData"
APP_PATH="$ROOT/$DERIVED_DATA_PATH/Build/Products/Debug/Gojo.app"
HISTORY_PATH="$HOME/Library/Application Support/Gojo/Clipboard/history.json"
DOMAIN="rohoswagger.gojo"
PAYLOAD=$'  line one\n\nline two  '

ORIGINAL_VALUE="$(defaults read "$DOMAIN" clipboardHistoryEnabled 2>/dev/null || echo "__unset__")"

cleanup() {
  pkill -x Gojo >/dev/null 2>&1 || true
  if [[ "$ORIGINAL_VALUE" == "__unset__" ]]; then
    defaults delete "$DOMAIN" clipboardHistoryEnabled >/dev/null 2>&1 || true
  else
    defaults write "$DOMAIN" clipboardHistoryEnabled -bool "$ORIGINAL_VALUE" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

defaults write "$DOMAIN" clipboardHistoryEnabled -bool true >/dev/null 2>&1 || true
rm -f "$HISTORY_PATH"

xcodebuild \
  -project Gojo.xcodeproj \
  -scheme Gojo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  >/tmp/gojo-clipboard-roundtrip-build.log

test -d "$APP_PATH"

open -na "$APP_PATH"
sleep 4

python3 - <<'PY'
import subprocess
payload = "  line one\n\nline two  "
subprocess.run(["pbcopy"], input=payload.encode("utf-8"), check=True)
PY

python3 - <<'PY'
import json
import os
import time

history_path = os.path.expanduser("~/Library/Application Support/Gojo/Clipboard/history.json")
payload = "  line one\n\nline two  "

deadline = time.time() + 8
while time.time() < deadline:
    if os.path.exists(history_path):
        with open(history_path, "r", encoding="utf-8") as f:
            items = json.load(f)
        if items and items[0]["content"] == payload:
            print("clipboard-roundtrip-pass")
            raise SystemExit(0)
    time.sleep(0.25)

raise SystemExit("clipboard roundtrip smoke failed")
PY
