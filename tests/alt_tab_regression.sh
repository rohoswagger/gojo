#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-alt-tab-regression"
swiftc \
  Gojo/WindowManagement/AltTabSelection.swift \
  tests/alt_tab_regression.swift \
  -o "$BIN"
"$BIN"
