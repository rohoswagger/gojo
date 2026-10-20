#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-final-text.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationSpokenCommands.swift \
  Gojo/Dictation/DictationFinalTextPolicy.swift \
  tests/dictation_final_text_regression.swift \
  -o "$binary_path"
"$binary_path"
