#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationSessionStateMachine.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  Gojo/Dictation/DictationController.swift \
  Gojo/Dictation/AVAudioEngineCaptureService.swift \
  tests/dictation_regression.swift \
  -o "$binary_path"
"$binary_path"

notch_activity_source="Gojo/Dictation/DictationNotchActivity.swift"
grep -Fq "recordControl" "$notch_activity_source"
grep -Fq 'Image(systemName: "exclamationmark.triangle.fill")' "$notch_activity_source"
