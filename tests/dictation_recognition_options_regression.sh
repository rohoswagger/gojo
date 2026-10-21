#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
sdk_products="${GOJO_DICTATION_SDK_BUILD_PRODUCTS:-$PWD/.build/DerivedData/Build/Products/Debug}"
if [[ ! -f "$sdk_products/WhisperKit.o" || ! -f "$sdk_products/ArgmaxCore.o" ]]; then
  echo "Build the pinned SDK dependencies or set GOJO_DICTATION_SDK_BUILD_PRODUCTS to their existing products." >&2
  exit 2
fi
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gojo-recognition-options.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
swiftc -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
  -I "$sdk_products" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationModelPreparation.swift \
  Gojo/Dictation/WhisperKitDictationTranscriber.swift \
  tests/dictation_recognition_options_regression.swift \
  "$sdk_products/WhisperKit.o" "$sdk_products/ArgmaxCore.o" \
  -o "$test_directory/regression"
"$test_directory/regression"
