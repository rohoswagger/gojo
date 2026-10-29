#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
: "${BARK_MODEL_FOLDER:?Set BARK_MODEL_FOLDER to the pinned coreml/ane model folder}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gojo-bark-live.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
say -v Samantha -r 150 -o "$scratch/speech.wav" --file-format=WAVE --data-format=LEF32@16000 \
  'The meeting is tomorrow at ten. Please bring the blue notebook.'
swiftc -O -swift-version 5 -warnings-as-errors \
  Gojo/Dictation/BarkTensorArchive.swift Gojo/Dictation/BarkSpeechRuntime.swift \
  tests/bark_inference_live.swift -o "$scratch/inference"
"$scratch/inference" "$BARK_MODEL_FOLDER" "$scratch/speech.wav"
