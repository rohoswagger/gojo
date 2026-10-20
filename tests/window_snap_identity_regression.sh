#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 - <<'PY'
from pathlib import Path

helper = Path("GojoXPCHelper/GojoXPCHelper.swift").read_text()
for name, end in [("setWindowFrame", "performZoom"), ("performZoom", "raiseWindow")]:
    method = helper.split(f"@objc func {name}", 1)[1].split(f"@objc func {end}", 1)[0]
    assert "WindowTargetResolver.windowActivationTarget(" in method, f"{name} must enforce exact window identity"
    assert "requestedWindowID: cgID" in method, f"{name} must preserve the requested window ID"
    assert "?? self.bestWindowElement" not in method, f"{name} must not mutate a sibling when the exact window disappears"
view = Path("Gojo/components/Windows/WindowPowerView.swift").read_text()
selection = view.split("onSelect: { summary in", 1)[1].split(".frame(width: 68)", 1)[0]
assert "allowApplicationFallback: false" in selection, "Stage selection must preserve exact identity"
assert "NSRunningApplication" not in selection, "Stage selection must not reactivate sibling windows"
assert "if !raised" in selection, "Stage selection must report unavailable windows"
print("window_snap_identity_regression: ok")
PY
