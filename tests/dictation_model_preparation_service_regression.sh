#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gojo-model-preparation-service.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

cd "$repo_root"
python3 - "$test_directory/service.swift" "${GOJO_MODEL_PREPARATION_SERVICE_SOURCE:-Gojo/Dictation/GojoDictationService.swift}" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[2]).read_text()
template = Path("tests/dictation_model_preparation_service_regression.swift").read_text()

def member(name):
    match = re.search(rf"^    (?:private )?func {name}\b", source, re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing production service member: {name}")
    end = re.search(r"^    }$", source[match.start():], re.MULTILINE)
    if not end:
        raise SystemExit(f"Unterminated production service member: {name}")
    return source[match.start():match.start() + end.end()] + "\n"

members = [member(name) for name in (
    "warmSelectedTranscriber", "recordModelPreparationResult",
    "finishTranscriberWarmupIfCurrent", "shouldPrepareTranscriberWarmup",
    "shouldRunS1MiniWarmup", "receive",
)]
marker = "    // __PRODUCTION_SERVICE_MEMBERS__"
if template.count(marker) != 1:
    raise SystemExit("Expected one production service extraction marker")
Path(sys.argv[1]).write_text(template.replace(marker, "\n".join(members)))
PY

swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationModelPreparation.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  "$test_directory/service.swift" \
  -o "$test_directory/regression"
"$test_directory/regression"
