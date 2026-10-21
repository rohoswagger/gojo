#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-capture-liveness.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationSpeechGate.swift \
  Gojo/Dictation/DictationInputDevices.swift \
  Gojo/Dictation/DictationPreviewAudioBuffer.swift \
  Gojo/Dictation/DictationUtteranceSegmenter.swift \
  Gojo/components/Settings/DictationMicrophonePermission.swift \
  Gojo/Dictation/AVAudioEngineCaptureService.swift \
  tests/dictation_capture_liveness_regression.swift \
  -o "$binary_path"
"$binary_path"
