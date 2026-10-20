#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-s1-polisher-policy.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

cd "$repo_root"
python3 - "$work_dir/ProductionPolisher.swift" <<'PY'
import pathlib
import sys

source = pathlib.Path("Gojo/Dictation/S1MiniDictationPolisher.swift").read_text()
start = source.index("actor S1MiniDictationPolisher: DictationTextPolishing {")
pathlib.Path(sys.argv[1]).write_text("import Foundation\n" + source[start:])
PY
swiftc \
  -swift-version 5 \
  -warnings-as-errors \
  -target arm64-apple-macosx14.0 \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  Gojo/Dictation/DictationSpokenCommands.swift \
  Gojo/Dictation/DictationFinalTextPolicy.swift \
  tests/s1_mini_polisher_policy_regression.swift \
  "$work_dir/ProductionPolisher.swift" \
  -o "$work_dir/regression"
"$work_dir/regression"
