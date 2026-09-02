#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-search-engine-regression"

if ! grep -Fq 'SystemSettingsSearchProvider(),' Gojo/components/Search/ViewModels/SearchStateViewModel.swift; then
  echo "SystemSettingsSearchProvider is not registered in SearchStateViewModel" >&2
  exit 1
fi

swiftc \
  Gojo/components/Search/CalculatorEngine.swift \
  Gojo/components/Search/FuzzyMatcher.swift \
  Gojo/components/Search/FrecencyMath.swift \
  Gojo/components/Search/Models/SearchResult.swift \
  Gojo/components/Search/Providers/SearchProvider.swift \
  Gojo/components/Search/Providers/SystemSettingsSearchProvider.swift \
  GojoXPCHelper/SearchHotkeyMatch.swift \
  tests/search_engine_regression.swift \
  -o "$BIN"
"$BIN"
