#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-practice.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationPracticeField.swift \
  Gojo/Dictation/DictationFeedback.swift \
  Gojo/components/Settings/SettingsWindowCloseObserver.swift \
  tests/dictation_practice_regression.swift -o "$scratch_dir/practice"
"$scratch_dir/practice"
