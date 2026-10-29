#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
: "${BARK_CLEAN_MODEL_FOLDER:?Set BARK_CLEAN_MODEL_FOLDER to the pinned bark-3.0-clean folder}"
products="${GOJO_DICTATION_SDK_BUILD_PRODUCTS:-$PWD/.build/DerivedData/Build/Products/Debug}"
fluid_sources="${GOJO_FLUIDAUDIO_SOURCE_ROOT:-$PWD/.build/DerivedData/SourcePackages/checkouts/FluidAudio}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gojo-bark-clean-live.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
say -v Samantha -r 150 -o "$scratch/speech.wav" --file-format=WAVE --data-format=LEF32@16000 \
  'Um, the meeting is, uh, tomorrow at ten. Please bring the, um, blue notebook.'
swiftc -O -swift-version 5 -warnings-as-errors -I "$products" \
  -I "$fluid_sources/Sources/FastClusterWrapper/include" \
  -I "$fluid_sources/Sources/MachTaskSelfWrapper/include" \
  Gojo/Dictation/DictationModels.swift Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/BarkTensorArchive.swift Gojo/Dictation/BarkSpeechRuntime.swift \
  Gojo/Dictation/BarkModelVariant.swift Gojo/Dictation/BarkSpeechEngine.swift \
  tests/bark_clean_inference_live.swift "$products/FluidAudio.o" "$products/FastClusterWrapper.o" "$products/MachTaskSelfWrapper.o" -lc++ -o "$scratch/inference"
"$scratch/inference" "$BARK_CLEAN_MODEL_FOLDER" "$scratch/speech.wav"
