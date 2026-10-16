#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

python3 - <<'PY'
from pathlib import Path
import re
import sys

legacy_notch_symbols = re.compile(
    r"\b(?:\w*NotchAlert\w*|DictationNotch\w*|notchAlert\w*|dictationActivity|"
    r"shouldShowDictationActivity|isDictationSessionDisplay)\b"
)
content_dependencies = re.compile(r"\b(?:GojoDictationService|DictationState|audioLevel)\b")
violations = []

def reject_matches(path, pattern, reason):
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        for symbol in sorted(set(pattern.findall(line))):
            violations.append(f"{path}:{line_number}: {reason}: {symbol}")

for path in sorted(Path("Gojo").rglob("*.swift")):
    reject_matches(path, legacy_notch_symbols, "legacy notch dictation wiring")
for path in sorted(Path("Gojo.xcodeproj").rglob("project.pbxproj")):
    reject_matches(path, legacy_notch_symbols, "legacy notch dictation project entry")
reject_matches(
    Path("Gojo/ContentView.swift"),
    content_dependencies,
    "notch view depends on dictation session state",
)

if violations:
    print("\n".join(violations), file=sys.stderr)
    print(f"Dictation presentation ownership regressions failed ({len(violations)})", file=sys.stderr)
    sys.exit(1)

print("Dictation presentation ownership regressions passed")
PY
