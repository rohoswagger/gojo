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

if ! grep -Fq 'layer?.masksToBounds = true' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not mask native content to rounded corners" >&2
  exit 1
fi

if ! grep -Fq 'SearchPanelLayout.panelFrame(' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not use the tested top-anchored panel frame" >&2
  exit 1
fi

if ! grep -Fq 'SearchPanelHostingPolicy.configure(hostingView)' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController still lets NSHostingView fight the native panel frame" >&2
  exit 1
fi

if ! grep -Fq 'hostingView.sizingOptions = []' Gojo/components/Search/Models/SearchPanelHostingPolicy.swift; then
  echo "SearchPanelHostingPolicy does not disable NSHostingView window sizing" >&2
  exit 1
fi

if grep -Fq '.onChange(of: search.panelHeight)' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView still owns native panel resizing from inside its update transaction" >&2
  exit 1
fi

if grep -Fq 'objectWillChange' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController samples height from a pre-mutation objectWillChange event" >&2
  exit 1
fi

if ! grep -Fq 'Publishers.CombineLatest3(' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not derive height from explicit post-change search values" >&2
  exit 1
fi

if ! grep -Fq '.removeDuplicates()' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController can schedule redundant native resizes" >&2
  exit 1
fi

if ! grep -Fq 'func scheduleContentHeightUpdate' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not defer result-height updates" >&2
  exit 1
fi

if ! grep -Fq 'DispatchQueue.main.async' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController can re-enter AppKit layout from a SwiftUI update transaction" >&2
  exit 1
fi

if grep -Fq 'SearchPanelController.shared.scheduleContentHeightUpdate' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView still reaches into native panel sizing" >&2
  exit 1
fi

if grep -Fq 'hostPanelFrame' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController still reserves an invisible maximum-size hit area" >&2
  exit 1
fi

if ! grep -Fq '@Published private(set) var isSearching = false' Gojo/components/Search/ViewModels/SearchStateViewModel.swift; then
  echo "SearchStateViewModel does not expose an explicit loading state" >&2
  exit 1
fi

if ! grep -Fq 'AppBundleIndexPolicy.shouldInclude(' Gojo/components/Search/Providers/AppSearchProvider.swift; then
  echo "AppSearchProvider does not filter background-only app bundles" >&2
  exit 1
fi

if ! grep -A 12 -F 'private func autoSelectFirstResultIfNeeded()' Gojo/components/Search/ViewModels/SearchStateViewModel.swift \
  | grep -Fq 'lastSelectionWasKeyboard = false'; then
  echo "automatic first-result selection can scroll and clip the top result" >&2
  exit 1
fi

if ! grep -Fq 'completedProviderIDs.contains(provider.providerID)' Gojo/components/Search/ViewModels/SearchStateViewModel.swift; then
  echo "search provider sections can reorder while results stream in" >&2
  exit 1
fi

if grep -Fq 'setAffineTransform' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController still scales the fixed search header during presentation" >&2
  exit 1
fi

if grep -Fq 'panel.animator().setFrame' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController still animates native frame changes that move the focused header" >&2
  exit 1
fi

if ! grep -Fq 'panel.setFrame(frame, display: true, animate: false)' Gojo/components/Search/SearchPanelController.swift; then
  echo "SearchPanelController does not explicitly disable native frame animation" >&2
  exit 1
fi

if ! grep -Fq 'width: SearchPanelLayout.searchIconFrameSize' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not reserve a stable magnifier layout box" >&2
  exit 1
fi

if ! grep -Fq 'HStack(spacing: SearchPanelLayout.headerSpacing)' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not use the tested fixed header spacing" >&2
  exit 1
fi

if ! grep -Fq '.padding(.horizontal, SearchPanelLayout.headerHorizontalPadding)' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not use the tested fixed header padding" >&2
  exit 1
fi

if ! grep -Fq 'width: SearchPanelLayout.progressIndicatorFrameSize' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not reserve a stable progress-indicator layout box" >&2
  exit 1
fi

if ! grep -Fq 'transaction.animation = nil' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not isolate the fixed header from result animations" >&2
  exit 1
fi

if ! grep -Fq '.frame(maxWidth: .infinity, alignment: .leading)' Gojo/components/Search/Views/SearchPanelView.swift; then
  echo "SearchPanelView does not keep query text leading-anchored at full width" >&2
  exit 1
fi

swiftc \
  Gojo/components/Search/CalculatorEngine.swift \
  Gojo/components/Search/FuzzyMatcher.swift \
  Gojo/components/Search/FrecencyMath.swift \
  Gojo/components/Search/Models/AppBundleIndexPolicy.swift \
  Gojo/components/Search/Models/SearchPanelHostingPolicy.swift \
  Gojo/components/Search/Models/SearchPanelLayout.swift \
  Gojo/components/Search/Models/SearchPanelResizeQueue.swift \
  Gojo/components/Search/Models/SearchPanelSpacePolicy.swift \
  Gojo/components/Search/Models/SearchResult.swift \
  Gojo/components/Search/Providers/SearchProvider.swift \
  Gojo/components/Search/Providers/SystemSettingsSearchProvider.swift \
  GojoXPCHelper/SearchHotkeyMatch.swift \
  tests/search_engine_regression.swift \
  -o "$BIN"
"$BIN"
