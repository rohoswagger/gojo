#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-search-file-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT
cd "$repo_root"
swiftc -swift-version 5 \
  Gojo/components/Search/Models/SearchResult.swift \
  Gojo/components/Search/FuzzyMatcher.swift \
  Gojo/components/Search/Providers/SearchProvider.swift \
  Gojo/components/Search/Providers/FileSearchProvider.swift \
  tests/search_file_cancellation_regression.swift -o "$binary_path"
"$binary_path"
