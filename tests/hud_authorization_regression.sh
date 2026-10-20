#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-hud-authorization.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
python3 - "$scratch_dir/fixture.swift" <<'PY'
from pathlib import Path
import sys

source = Path('Gojo/GojoViewCoordinator.swift').read_text()
start = source.index('            if Defaults[.hudReplacement]', source.index('// helloAnimationRunning = firstLaunch'))
opening = source.index('{', start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}')
    end += 1
fixture = Path('tests/hud_authorization_regression.swift').read_text()
Path(sys.argv[1]).write_text(fixture.replace('/* PRODUCTION_STARTUP */', source[start:end]))
PY
swiftc -parse-as-library -swift-version 5 -warnings-as-errors -target "$(uname -m)-apple-macosx14.0" \
  "$scratch_dir/fixture.swift" -o "$scratch_dir/test"
"$scratch_dir/test"
