#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-output-silencer.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
python3 - <<'CHECK'
from pathlib import Path
service = Path("Gojo/Dictation/GojoDictationService.swift").read_text()
music = Path("Gojo/managers/MusicManager.swift").read_text()
assert "beforeCapture: { await DictationOutputSilencer.shared.quietForDictation() }" in service
assert all(name not in music for name in ("dictationPause", "pauseForDictation", "resumeAfterDictation"))
CHECK
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationOutputSilencer.swift \
  tests/dictation_output_silencer_regression.swift \
  -o "$binary_path"
"$binary_path"
