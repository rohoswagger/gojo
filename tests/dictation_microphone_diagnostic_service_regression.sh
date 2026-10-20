#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/gojo-microphone-diagnostic-service.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

cd "$repo_root"
python3 - "$test_directory/service.swift" "${GOJO_DIAGNOSTIC_SERVICE_SOURCE:-Gojo/Dictation/GojoDictationService.swift}" <<'PY'
from pathlib import Path
import re
import sys

source = Path(sys.argv[2]).read_text()
template = Path("tests/dictation_microphone_diagnostic_service_regression.swift").read_text()

def member(name, optional=False):
    pattern = rf"^    (?:private )?(?:func|var) {name}\b"
    match = re.search(pattern, source, re.MULTILINE)
    if not match:
        if optional:
            return ""
        raise SystemExit(f"Missing production service member: {name}")
    end = re.search(r"^    }$", source[match.start():], re.MULTILINE)
    if not end:
        raise SystemExit(f"Unterminated production service member: {name}")
    return source[match.start():match.start() + end.end()] + "\n"

members = [member(name) for name in (
    "isDictationInactive", "processShortcutEvent", "rejectShortcutStart",
    "testMicrophone", "cancelMicrophoneTest", "receive",
    "makeRecognitionRequest", "makeSessionPlan", "receiveCompletion",
    "observeCorrections", "setLearnsCorrections", "cancelCorrectionObservationTask", "resetCorrectionLearning",
)]
members.append(member("canTestMicrophone", optional=True))
for name in ("shortcutPreflighting", "awaitingControllerStart"):
    match = re.search(rf"^    .*\bvar {name}\b[^\n]*$", source, re.MULTILINE)
    if match:
        members.append(match.group() + "\n")
    elif name == "shortcutPreflighting":
        raise SystemExit(f"Missing production service property: {name}")

def declaration(name):
    match = re.search(rf"^private (?:enum|struct) {name}\b", source, re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing production target declaration: {name}")
    end = re.search(r"^}$", source[match.start():], re.MULTILINE)
    if not end:
        raise SystemExit(f"Unterminated production target declaration: {name}")
    return source[match.start():match.start() + end.end()] + "\n"

targets = "\n".join(declaration(name) for name in ("DictationTextTarget", "XPCTargetProvider", "DictationXPCError"))
template = template.replace("// __PRODUCTION_TARGET_DECLARATIONS__", targets)
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
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationProtocols.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  "$test_directory/service.swift" \
  -o "$test_directory/regression"
"$test_directory/regression"
