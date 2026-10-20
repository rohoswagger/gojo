#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-accessibility-flow-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/components/Onboarding/AccessibilityAuthorizationFlowPolicy.swift \
  tests/accessibility_authorization_flow_regression.swift \
  -o "$binary_path"
"$binary_path"

if grep -q 'isAccessibilityAuthorized()' Gojo/components/Onboarding/PermissionsRequestView.swift Gojo/components/Settings/SettingsView.swift; then
  echo "Permission screens must distinguish helper failures from a negative authorization reply" >&2
  exit 1
fi
