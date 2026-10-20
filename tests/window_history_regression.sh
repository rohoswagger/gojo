#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="$(mktemp /tmp/gojo-window-history-regression.XXXXXX)"
trap 'rm -f "$BIN"' EXIT
swiftc \
  Gojo/WindowManagement/WindowAction.swift \
  Gojo/WindowManagement/FocusedWindow.swift \
  Gojo/WindowManagement/WindowHistoryStore.swift \
  tests/window_history_regression.swift \
  -o "$BIN"
"$BIN"
