#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-clipboard-regression"
swiftc \
  Gojo/components/Clipboard/Models/ClipboardItem.swift \
  tests/clipboard_regression.swift \
  -o "$BIN"
"$BIN"
