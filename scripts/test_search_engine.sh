#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-search-engine-regression"

if ! grep -Fq 'SystemSettingsSearchProvider(),' Gojo/components/Search/ViewModels/SearchStateViewModel.swift; then
  echo "SystemSettingsSearchProvider is not registered in SearchStateViewModel" >&2
  exit 1
fi

if ! grep -Fq 'collectionBehavior = SearchPanelSpacePolicy.collectionBehavior' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not use SearchPanelSpacePolicy.collectionBehavior" >&2
  exit 1
fi

if ! grep -Fq 'SearchPanelSpacePolicy.shouldHideAfterResigningKey(' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not use SearchPanelSpacePolicy.shouldHideAfterResigningKey" >&2
  exit 1
fi

if ! grep -Fq 'isOnActiveSpace: panel.isOnActiveSpace' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not read panel.isOnActiveSpace for resign-key policy" >&2
  exit 1
fi

if ! grep -Fq 'SearchPanelSpacePolicy.shouldHideOnToggle(' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not use SearchPanelSpacePolicy.shouldHideOnToggle" >&2
  exit 1
fi

swiftc \
  Gojo/components/Search/CalculatorEngine.swift \
  Gojo/components/Search/FuzzyMatcher.swift \
  Gojo/components/Search/FrecencyMath.swift \
  Gojo/components/Search/Models/SearchPanelSpacePolicy.swift \
  Gojo/components/Search/Models/SearchResult.swift \
  Gojo/components/Search/Providers/SearchProvider.swift \
  Gojo/components/Search/Providers/SystemSettingsSearchProvider.swift \
  GojoXPCHelper/SearchHotkeyMatch.swift \
  tests/search_engine_regression.swift \
  -o "$BIN"
"$BIN"
