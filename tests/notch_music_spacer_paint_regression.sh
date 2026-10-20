#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-notch-paint.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
python3 - "$scratch_dir/paint.swift" <<'PY'
from pathlib import Path
import re
import sys

source = Path("Gojo/ContentView.swift").read_text()
music = source[source.index("func MusicLiveActivity()") :]
fill = re.search(r"Rectangle\(\)\s*\.fill\(([^\n)]+)\)\s*\.overlay\(", music)
assert fill, "MusicLiveActivity must expose its middle spacer fill"
sizing = Path("Gojo/sizing/matters.swift").read_text()
radius = re.search(r"closed:\s*\(top:\s*([\d.]+)", sizing)
assert radius, "Closed notch sizing must declare its top radius"
fixture = Path("tests/notch_music_spacer_paint_regression.swift").read_text()
fixture = fixture.replace("/* MUSIC_CENTER_FILL */", fill.group(1))
fixture = fixture.replace("/* CLOSED_TOP_RADIUS */", radius.group(1))
Path(sys.argv[1]).write_text(fixture)
PY
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/components/Notch/NotchShape.swift "$scratch_dir/paint.swift" \
  -o "$scratch_dir/paint"
"$scratch_dir/paint"
