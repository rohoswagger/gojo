#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gojo-residency-regression.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationModelResidency.swift \
  tests/dictation_residency_regression.swift -o "$test_directory/regression"
"$test_directory/regression"
