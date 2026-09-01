#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

source = Path("Gojo/GojoApp.swift").read_text()
client = Path("Gojo/XPCHelperClient/XPCHelperClient.swift").read_text()
main_protocol = Path("Gojo/XPCHelperClient/GojoXPCHelperProtocol.swift").read_text()
helper_protocol = Path("GojoXPCHelper/GojoXPCHelperProtocol.swift").read_text()
helper = Path("GojoXPCHelper/GojoXPCHelper.swift").read_text()

assert "dictationCaptureE2EProbeObserver" in source
assert "rohoswagger.gojo.dictation-capture-e2e-probe" in source
assert "runDictationCaptureE2EProbe" in source
assert 'category: "capture"' in source
assert "XPCHelperClient.shared.captureFocusedTextTarget(" in source
assert "expectedPID" in source
assert "windowID" in source
assert "preferredDictationApplicationPasteTarget" in client
assert "preferredTarget: preferredTarget" in client
assert "let preferredTarget = preferredTargetHint?.xpcDictionary" in client
assert '"pid": NSNumber(value: pid)' in client
assert '"windowID": NSNumber(value: windowID)' in client
assert "WindowTargetResolver.topmostApplicationPasteTarget(" in client
for protocol in (main_protocol, helper_protocol):
    assert "preferredTarget: NSDictionary?" in protocol
assert "preferredTarget: NSDictionary?," in helper
assert "let preferredApplicationTarget = preferredTarget.flatMap(" in helper
assert "self.applicationPasteTarget(from:)" in helper
assert "preferredTarget == nil ? self.topmostApplicationPasteTarget() : nil" in helper
assert "private func applicationPasteTarget(\n        from preferredTarget: NSDictionary\n    )" in helper
assert "kind: .applicationUnicode" in helper
assert "opaqueTextTargetKind" not in helper
assert "windowID != 0" in helper
assert "shouldUsePreferredApplicationPasteTarget(" in helper
PY

echo "dictation-capture-probe-regression-pass"
