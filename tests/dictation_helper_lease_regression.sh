#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-helper-lease.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT
cd "$repo_root"
swiftc -swift-version 5 -warnings-as-errors -D DEBUG \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationHelperReadiness.swift \
  GojoXPCHelper/DictationHotkeyTapService.swift \
  tests/dictation_helper_lease_regression.swift -o "$binary_path"
"$binary_path"
