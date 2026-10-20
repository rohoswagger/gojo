#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-audio-configuration.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationUtteranceSegmenter.swift \
  Gojo/Dictation/AVAudioEngineCaptureService.swift \
  tests/dictation_audio_configuration_regression.swift \
  -o "$binary_path"
"$binary_path"
