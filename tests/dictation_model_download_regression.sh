#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/gojo-model-download.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
cd "$repo_root"

python3 - "$scratch/service.swift" <<'PY'
from pathlib import Path
import re
import sys

source = Path("Gojo/Dictation/GojoDictationService.swift").read_text()
template = Path("tests/dictation_model_download_regression.swift").read_text()

def member(name):
    match = re.search(rf"^    (?:private )?func {name}\b", source, re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing production service member: {name}")
    end = re.search(r"^    }$", source[match.start():], re.MULTILINE)
    if not end:
        raise SystemExit(f"Unterminated production service member: {name}")
    return source[match.start():match.start() + end.end()] + "\n"

members = [member(name) for name in (
    "modelOperationError", "downloadModel", "receiveModelDownloadProgress", "finishModelDownload",
)]
marker = '    #error("__PRODUCTION_SERVICE_MEMBERS__")'
assert template.count(marker) == 1
Path(sys.argv[1]).write_text(template.replace(marker, "\n".join(members)))
PY

swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationModelResidency.swift \
  Gojo/Dictation/DictationModelPreparation.swift \
  "$scratch/service.swift" -o "$scratch/regression"
"$scratch/regression"
