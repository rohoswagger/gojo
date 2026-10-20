#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/gojo-window-focus.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
python3 - "$probe_dir/helper.swift" <<'PY'
from pathlib import Path
import sys
source = Path("GojoXPCHelper/GojoXPCHelper.swift").read_text()
method = source.split("    @objc func focusedWindowSnapshot(forPID", 1)[1].split("    @objc func setFocusedWindowFrame", 1)[0]
Path(sys.argv[1]).write_text("import AppKit\nextension ProbeHelper {\n    @objc func focusedWindowSnapshot(forPID" + method + "}\n")
PY
swiftc -module-cache-path "$probe_dir/module-cache" \
  Gojo/WindowManagement/WindowAction.swift \
  Gojo/WindowManagement/WindowFrameCalculator.swift \
  Gojo/WindowManagement/FocusedWindow.swift \
  Gojo/WindowManagement/WindowTargetResolver.swift \
  Gojo/extensions/NSScreen+UUID.swift \
  Gojo/WindowManagement/FocusedWindowProvider.swift \
  tests/window_focus_live_support.swift \
  tests/window_focus_live_probe.swift \
  "$probe_dir/helper.swift" \
  -o "$probe_dir/probe"
"$probe_dir/probe"
