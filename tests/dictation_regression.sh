#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-regression.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationSessionStateMachine.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  Gojo/Dictation/DictationController.swift \
  Gojo/Dictation/DictationUtteranceSegmenter.swift \
  Gojo/components/Settings/DictationMicrophonePermission.swift \
  Gojo/Dictation/AVAudioEngineCaptureService.swift \
  tests/dictation_regression.swift \
  -o "$binary_path"
"$binary_path"
