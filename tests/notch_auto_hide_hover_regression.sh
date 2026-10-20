#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-notch-hover.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
python3 - "$scratch_dir/hover.swift" <<'PY'
from pathlib import Path
import re
import sys

source = Path("Gojo/ContentView.swift").read_text()
model = Path("Gojo/models/GojoViewModel.swift").read_text()
fixture = Path("tests/notch_auto_hide_hover_regression.swift").read_text()

def declaration(text, signature):
    start = text.index(signature)
    body = text.index("{", start)
    depth = 1
    end = body + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end].replace("private ", "", 1)

hover_property = re.search(r"@Published var (isHoveringNotch|isHoverRevealed): Bool = false", model)
assert hover_property, "The model must expose its hover presentation state"
fixture = fixture.replace("/* MODEL_PRESENTATION */", "var " + hover_property.group(1) + ": Bool = false { didSet { revealTransaction = AnimationScope.current } }\n" + declaration(model, "var isAutoHidden: Bool"))
methods = [declaration(source, signature) for signature in ["private func doOpen()", "private func handleHover(_ hovering: Bool)"]]
fixture = fixture.replace("/* HOVER_METHODS */", "\n\n".join(methods))
spring = re.search(r"private let animationSpring = (.+)", source)
assert spring, "ContentView must declare its hover animation"
fixture = fixture.replace("/* HOVER_ANIMATION */", "let animationSpring = " + spring.group(1))
if "private var openAnimation: Animation" in source:
    fixture = fixture.replace("/* OPEN_ANIMATION */", declaration(source, "private var openAnimation: Animation"))
Path(sys.argv[1]).write_text(fixture)
PY
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/observers/NotchAutoHidePolicy.swift "$scratch_dir/hover.swift" \
  -o "$scratch_dir/hover"
"$scratch_dir/hover"
