#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-panel-presentation.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
python3 - "$scratch_dir/fixture.swift" <<'PY'
from pathlib import Path
import sys
source = Path('Gojo/Dictation/DictationPanelController.swift').read_text()
panels = source[source.index('private final class DictationPanelHostingView'):]
Path(sys.argv[1]).write_text(Path('tests/dictation_panel_presentation_regression.swift').read_text() + '\n' + panels)
PY
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationModifierShortcutStateMachine.swift \
  Gojo/Dictation/DictationPanelPlacement.swift \
  Gojo/Dictation/DictationPanelView.swift \
  "$scratch_dir/fixture.swift" -o "$scratch_dir/presentation"
"$scratch_dir/presentation"
