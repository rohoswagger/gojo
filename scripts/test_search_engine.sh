#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-search-engine-regression"
swiftc \
  Gojo/components/Search/CalculatorEngine.swift \
  Gojo/components/Search/FuzzyMatcher.swift \
  Gojo/components/Search/FrecencyMath.swift \
  GojoXPCHelper/SearchHotkeyMatch.swift \
  tests/search_engine_regression.swift \
  -o "$BIN"
"$BIN"
