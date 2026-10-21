#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-permission-settings.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
artifact_dir="${GOJO_SETTINGS_RENDER_DIR:-$repo_root/.omx/permissions}"
mkdir -p "$artifact_dir"

python3 - "$scratch_dir/fixture.swift" <<'PY'
from pathlib import Path
import sys

source = Path("Gojo/components/Settings/SettingsView.swift").read_text()
source = source[source.index("struct DictationSettings: View {"):]
names = ["permissionSection", "helperStatusLabel", "accessibilityStatusLabel", "shortcutStatusLabel",
         "microphoneTestLabel", "microphoneStatusLabel", "microphonePermissionGuidance"]

def member(name):
    start = source.index(f"    private var {name}:")
    opening = source.index("{", start)
    depth = 1
    position = opening + 1
    quoted = False
    escaped = False
    while depth:
        char = source[position]
        if quoted:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        position += 1
    return source[start:position]

fixture = Path("tests/dictation_permission_settings_regression.swift").read_text()
assert fixture.count("/* PRODUCTION_PERMISSION_MEMBERS */") == 1
fixture = fixture.replace("/* PRODUCTION_PERMISSION_MEMBERS */", "\n\n".join(map(member, names)))
Path(sys.argv[1]).write_text(fixture)
PY

swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/Dictation/DictationHelperReadiness.swift \
  Gojo/Dictation/DictationModels.swift \
  Gojo/Dictation/DictationSessionPlan.swift \
  "$scratch_dir/fixture.swift" -o "$scratch_dir/settings-render"
"$scratch_dir/settings-render" "$artifact_dir"
