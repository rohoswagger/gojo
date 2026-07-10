#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

source = Path("Gojo/components/Windows/WindowPowerView.swift").read_text()

# Three-column panel structure
assert "WindowsTabPanel" in source, "Windows tab must use the three-column panel."
assert "StageStrip" in source, "Windows tab must show the stage strip of open windows."
assert "PreviewMonitor" in source, "Windows tab must show the preview monitor."
assert "ChipGrid" in source, "Windows tab must show the snap chip grid."
assert "@EnvironmentObject var vm: GojoViewModel" in source, "Windows tab must use per-notch view model."
assert "vm.windowPowerState" in source, "Windows tab must bind per-notch window power state."
assert "NSWorkspace.didActivateApplicationNotification" in source, "Windows tab must refresh when frontmost app changes."
assert "screenUUID: vm.screenUUID" in source, "Refresh must be scoped to this notch display."

# Stage strip overflow: scrolls instead of truncating or compressing
assert "ScrollingStageStrip" in source, "Stage strip must scroll when windows overflow."
assert "prefix(maxVisibleWindows)" not in source, "Stage strip must not silently truncate the window list."
assert "flexThreshold" in source, "Small window counts must keep flex-fill card sizing."
assert "cardHeight(available:" in source, "Scroll mode must derive a fixed card height with a half-clipped peek card."
assert "scrollIndicators(.hidden)" in source, "Stage strip scroll view must hide scrollbar chrome."
assert "edgeFadeMask" in source, "Stage strip must fade edges toward additional content."
assert "scrollToFocused" in source, "Stage strip must auto-scroll the focused window into view."
assert "accessibilityReduceMotion" in source, "Auto-scroll must respect reduced motion."

executor = Path("Gojo/WindowManagement/WindowActionExecutor.swift").read_text()
assert "screenUUID: String?" in executor, "Executor must accept screen UUID."
assert "state: WindowPowerState" in executor, "Executor must accept per-notch state."
assert "focusedWindow(for: notchScreen" in executor, "Executor must resolve focus for the notch screen."

vm = Path("Gojo/models/GojoViewModel.swift").read_text()
assert "let windowPowerState = WindowPowerState()" in vm, "Each view model owns window power state."

content = Path("Gojo/ContentView.swift").read_text()
assert "WindowPowerView()" in content, "ContentView must host the Windows tab."

print("window_power_view_regression: ok")
PY
