#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
binary="$(mktemp "${TMPDIR:-/tmp}/gojo-preparation-errors.XXXXXX")"
trap 'rm -f "$binary"' EXIT
swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModelPreparation.swift tests/dictation_model_preparation_regression.swift -o "$binary"
"$binary"
