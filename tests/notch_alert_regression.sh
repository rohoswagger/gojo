#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-notch-alert-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  Gojo/components/Notch/NotchAlert.swift \
  tests/notch_alert_regression.swift \
  -o "$binary_path"
"$binary_path"
