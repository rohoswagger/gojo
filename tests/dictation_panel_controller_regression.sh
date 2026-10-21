#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_path="$(mktemp "${TMPDIR:-/tmp}/gojo-dictation-panel-controller.XXXXXX")"
trap 'rm -f "$binary_path"' EXIT

cd "$repo_root"
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -DDEBUG \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  Gojo/Dictation/DictationPanelPlacement.swift \
  Gojo/Dictation/DictationPanelView.swift \
  Gojo/Dictation/DictationPanelController.swift \
  tests/dictation_panel_controller_regression.swift \
  -o "$binary_path"
python3 - "$binary_path" <<'PYTHON'
import subprocess
import sys
try:
    subprocess.run([sys.argv[1]], check=True, timeout=90)
except subprocess.TimeoutExpired:
    sys.exit("Dictation panel controller regression timed out")
except subprocess.CalledProcessError as error:
    sys.exit(error.returncode)
PYTHON
