#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-notch-auto-hide.XXXXXX")"
trap 'rm -rf "$scratch_dir"' EXIT
cd "$repo_root"
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  Gojo/observers/NotchAutoHidePolicy.swift \
  tests/notch_auto_hide_regression.swift -o "$scratch_dir/policy"
python3 - "$scratch_dir/layout.swift" <<'PY'
from pathlib import Path
import re
import sys

source = Path("Gojo/ContentView.swift").read_text()
hover_padding = re.search(r"private let zeroHeightHoverPadding: CGFloat = (\d+)", source)
assert hover_padding is not None, "ContentView must declare its zero-height hover padding"
padding_start = source.index("                    .padding(\n                        .bottom,\n                        vm.effectiveClosedNotchHeight")
layout_start = source.index("\n                mainLayout\n", padding_start)
modifiers_start = layout_start + len("\n                mainLayout\n")
modifiers_end = source.index("                    .conditionalModifier(true)", modifiers_start)
padding = source[padding_start:layout_start].rstrip()
modifiers = source[modifiers_start:modifiers_end].rstrip()

Path(sys.argv[1]).write_text("""import SwiftUI

private enum FixtureNotchState {
    case open, closed
}

private let zeroHeightHoverPadding: CGFloat = """ + hover_padding.group(1) + """

@MainActor
func notchHoverLayout(isAutoHidden: Bool, closedNotchHeight: CGFloat, contentHeight: CGFloat? = nil, isOpen: Bool = false) -> some View {
    let vm = (
        isAutoHidden: isAutoHidden,
        notchState: isOpen ? FixtureNotchState.open : .closed,
        closedNotchSize: CGSize(width: 185, height: closedNotchHeight),
        notchSize: CGSize(width: 185, height: 300),
        effectiveClosedNotchHeight: closedNotchHeight
    )
    let mainLayout = Color.black.frame(width: 185, height: contentHeight ?? closedNotchHeight)
""" + padding + """
    return mainLayout
""" + modifiers + """
}
""")
PY
swiftc -swift-version 5 -warnings-as-errors \
  -target "$(uname -m)-apple-macosx14.0" \
  "$scratch_dir/layout.swift" tests/notch_auto_hide_layout_regression.swift \
  -o "$scratch_dir/layout"
status=0
"$scratch_dir/policy" || status=$?
"$scratch_dir/layout" || status=$?
"$repo_root/tests/notch_auto_hide_hover_regression.sh" || status=$?
"$repo_root/tests/notch_music_spacer_paint_regression.sh" || status=$?
exit "$status"
