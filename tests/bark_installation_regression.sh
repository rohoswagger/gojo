#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gojo-bark-installation.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
python3 - "$scratch" <<'PY'
from pathlib import Path
import sys
root = Path('Gojo/Dictation')
output = Path(sys.argv[1])
source = (root / 'BarkDictationTranscriber.swift').read_text().replace('@preconcurrency import ArgmaxCore\n', '')
(output / 'BarkDictationTranscriber.swift').write_text(source)
whisper = (root / 'WhisperKitDictationTranscriber.swift').read_text()
(output / 'Errors.swift').write_text('import Foundation\n' + whisper[whisper.index('enum WhisperKitDictationError:'):])
PY
swiftc -swift-version 5 -warnings-as-errors \
  Gojo/Dictation/DictationModels.swift Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationProtocols.swift Gojo/Dictation/DictationModelPreparation.swift \
  Gojo/Dictation/DictationModelValidationCache.swift \
  "$scratch/BarkDictationTranscriber.swift" "$scratch/Errors.swift" \
  tests/bark_installation_regression.swift -o "$scratch/regression"
mkdir -p "$scratch/home"
CFFIXED_USER_HOME="$scratch/home" "$scratch/regression"
