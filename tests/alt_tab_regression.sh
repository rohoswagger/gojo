#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-alt-tab-regression"
swiftc \
  Gojo/WindowManagement/AltTabSelection.swift \
  Gojo/WindowManagement/WindowTargetResolver.swift \
  tests/alt_tab_regression.swift \
  -o "$BIN"
"$BIN"

python3 - <<'PY'
from pathlib import Path

helper = Path("GojoXPCHelper/GojoXPCHelper.swift").read_text()
raise_window = helper.split("@objc func raiseWindow", 1)[1].split(
    "@objc func enumerateWindows", 1
)[0]
assert "WindowTargetResolver.windowActivationTarget(" in raise_window
assert "requestedWindowID: allowApplicationFallback ? nil : cgID" in raise_window
assert "?? self.bestWindowElement" not in raise_window

assert "kAXMinimizedAttribute as CFString, kCFBooleanFalse" in raise_window
assert "reply(frontmostResult == .success)" not in raise_window

manager = Path("Gojo/managers/AltTabManager.swift").read_text()
commit = manager.split("func commit()", 1)[1].split("func cancel()", 1)[0]
assert "NSRunningApplication(processIdentifier: item.pid)?.activate()" not in commit
assert "allowApplicationFallback: false" in commit

advance = manager.split("func advance(reverse: Bool)", 1)[1].split("func selectFromPointer", 1)[0]
assert "resetPointerGate()" in advance

switcher = Path("Gojo/components/AltTab/AltTabSwitcherView.swift").read_text()
assert "manager.selectFromPointer(index: index)" in switcher

panel = Path("Gojo/components/AltTab/AltTabPanel.swift").read_text()
assert "func acceptsFirstMouse" in panel
PY
