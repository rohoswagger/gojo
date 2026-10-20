#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path
import re

main_protocol = Path("Gojo/XPCHelperClient/GojoXPCHelperProtocol.swift").read_text()
helper_protocol = Path("GojoXPCHelper/GojoXPCHelperProtocol.swift").read_text()
helper_main = Path("GojoXPCHelper/main.swift").read_text()
helper = Path("GojoXPCHelper/GojoXPCHelper.swift").read_text()
client = Path("Gojo/XPCHelperClient/XPCHelperClient.swift").read_text()
service = Path("Gojo/Dictation/GojoDictationService.swift").read_text()
panel = Path("Gojo/Dictation/DictationPanelController.swift").read_text()
resolver = Path("Gojo/WindowManagement/WindowTargetResolver.swift").read_text()
policy_path = Path("GojoXPCHelper/DictationTextTargetPolicy.swift")
assert policy_path.exists(), "Dictation target role policy must live outside the helper for direct regression coverage."
policy = policy_path.read_text()


def protocol_methods(source: str) -> set[str]:
    return {
        re.sub(r"\s+", " ", line.strip())
        for line in source.splitlines()
        if line.strip().startswith("func ")
    }


assert protocol_methods(main_protocol) == protocol_methods(helper_protocol), (
    "Main-app and helper XPC protocol methods must stay synchronized."
)

capture_signature = (
    "func captureFocusedTextTarget(_ promptIfNeeded: Bool, "
    "preferredTarget: NSDictionary?, "
    "with reply: @escaping (NSDictionary) -> Void)"
)
additional_capture_signature = capture_signature.replace(
    "captureFocusedTextTarget", "captureAdditionalFocusedTextTarget"
)
insert_signature = (
    "func insertText(_ text: String, token: String, "
    "with reply: @escaping (NSDictionary) -> Void)"
)
for source in (main_protocol, helper_protocol):
    normalized = re.sub(r"\s+", " ", source)
    assert capture_signature in normalized
    assert additional_capture_signature in normalized
    assert insert_signature in normalized

capture_entry_points = helper[
    helper.index("@objc func captureFocusedTextTarget("):
    helper.index("private func captureTextTarget(")
]
assert "replacingExistingTargets: true" in capture_entry_points
assert "replacingExistingTargets: false" in capture_entry_points
assert capture_entry_points.count("captureTextTarget(") == 2
shared_capture = helper[
    helper.index("private func captureTextTarget("):
    helper.index("@objc func insertText(")
]
assert re.search(
    r"if replacingExistingTargets\s*\{\s*"
    r"self\.capturedTextTargets\.removeAll\(keepingCapacity: true\)\s*\}",
    shared_capture,
), "Only legacy capture may invalidate queued target leases."
assert shared_capture.index("removeAll(") < shared_capture.index(
    "ensureAccessibilityAuthorizationSync("
), "Failed legacy capture must still invalidate earlier target leases."
assert shared_capture.count("removeAll(") == 1
assert shared_capture.count("capturedTextTargets.removeValue(") == 1
assert "capturedTextTargets.removeValue(forKey: token)" in shared_capture
assert "private static let maximumCapturedTextTargets = 16" in helper
assert "capturedTextTargets.count < Self.maximumCapturedTextTargets" in shared_capture
limit_guard = shared_capture[
    shared_capture.index("guard self.capturedTextTargets.count"):
    shared_capture.index("let complete:")
]
assert 'error: "targetLimitReached"' in limit_guard
assert "return" in limit_guard
assert "remove" not in limit_guard, "Capacity rejection must preserve queued target leases."
assert shared_capture.count("focusedTextTargetCandidates(") == 1
assert shared_capture.count("complete(captureReply)") == 5
assert "reply(NSDictionary(dictionary: captureReply))" not in shared_capture
assert 'result["targetIdentity"]' in shared_capture
assert "CFHash(target.element)" in shared_capture
assert "target.kind.rawValue" in shared_capture
assert "!replacingExistingTargets, target.kind != .accessibility" in shared_capture
assert 'error: "unverifiedTextTarget"' in shared_capture

# Capture safety: resolve system focus, reject secure/protected controls and
# ordinary non-editable controls, then retain only an opaque one-shot token.
# App-paste fallback captures the active app and exact window. The current
# cursor inside that window is allowed to change while transcription runs.
assert "kAXFocusedUIElementAttribute" in helper
assert "kAXSecureTextFieldSubrole" in helper
assert 'protectedContentAttribute = "AXContainsProtectedContent"' in helper
assert 'error: "secureTextTarget"' in helper
assert 'error: "nonEditableTarget"' in helper
assert "applicationPasteTarget(focusedElement)" in helper
assert "topmostTargetApplication()" in helper
assert "topmostApplicationPasteTarget()" in helper
assert "WindowTargetResolver.topmostApplicationPasteTarget(" in helper
assert "using main-app application paste target" in helper
assert "WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(" in helper
assert "focusedElements.compactMap(self.elementPID)" in helper
assert "shouldUsePreferredApplicationPasteTarget(" in resolver
assert "allowedBundleIDs: nil" in helper
assert "allowedBundleIDs: nil" in client
assert "axOpaqueDictationBundleIDs" not in resolver
assert "guardedUnicodeTypingBundleIDs" not in resolver
assert "windowID != 0" in helper
assert "kind: .applicationUnicode" in helper
assert "opaqueTextTargetKind" not in helper
assert "isTargetApplication(application)" in helper
assert "focusedTextTargetCandidates(" in helper
assert "preferredApplication: topmostApplication" in helper
assert "systemFocused" in helper
assert "applicationFocused" in helper
assert "frontmostFocused" in helper
assert "preferredFocused" in helper
assert "CFEqual($0, resolvedElement)" in helper
assert "focusedDescendantTextTarget(" in helper, (
    "Chromium can report the coarse page AXWebArea as focused; helper must resolve a nested focused editable descendant."
)
assert "kAXChildrenAttribute" in helper, (
    "focused descendant resolution must inspect AX children under the reported page WebArea."
)
assert "isFocusedAttribute" in helper, (
    "focused descendant resolution must only accept the active focused descendant, not unrelated page inputs."
)
assert "target.kind == .applicationPaste" in helper
assert "target.kind == .applicationUnicode" in helper
assert "let windowID: CGWindowID?" in helper
assert "let displayID: CGDirectDisplayID?" in helper
assert "windowID(of: focusedElement)" in helper
assert "WindowTargetResolver.windowID(" in helper
assert "containing: $0" in helper
assert "displayID(containing:" in helper
assert 'captureReply["displayID"] = NSNumber(value: displayID)' in helper
application_paste_target = helper[
    helper.index("private func applicationPasteTarget"):
    helper.index("private func topmostTargetApplication")
]
assert "preferredTopWindowID" not in application_paste_target
assert "focusedOrMainWindowID" not in application_paste_target
assert "kAXFocusedWindowAttribute" not in application_paste_target
assert "kAXMainWindowAttribute" not in application_paste_target
assert "systemFocusedUIElement()" in helper
assert "if let systemFocusedElement = copyElement(" in helper
assert "return systemFocusedElement" in helper
assert "activeFocusedUIElement(for: target.pid)" in helper
assert "isGojoHostApplication(pid: systemFocusedPID)" in helper
assert "NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID" in helper
assert "inCapturedWindowID: target.windowID" in helper
assert "return windowID(of: element) == expectedWindowID" in helper
assert "focusedUIElement(in: target.pid) ?? focusedUIElement()" not in helper
assert "focusedPID == pid_t(ProcessInfo.processInfo.processIdentifier)" in client
assert "applicationPasteTarget()" not in helper
assert "capturedTextTargets.removeAll(keepingCapacity: true)" in helper
assert "capturedTextTargets[token] = CapturedTextTarget" in helper
assert "UUID().uuidString" in helper
assert "DictationTextTargetPolicy.decision" in helper
assert "DictationTextTargetCapabilities(" in helper
assert "case .directAccessibility" in helper
assert "case .guardedApplicationPaste" in helper
assert "case .reject" in helper
focused_candidates = helper[
    helper.index("private func focusedTextTargetCandidates"):
    helper.index("private func focusedUIElement()")
]
assert "focusedDescendantTextTarget(" in focused_candidates, (
    "Chromium can expose the page AXWebArea as focused; capture must resolve a nested focused editable descendant."
)
assert "kAXChildrenAttribute" in helper[
    helper.index("focusedDescendantTextTarget("):
    helper.index("private func debugElementDescription")
], "focused descendant resolution must inspect AX children instead of accepting the page WebArea."

assert "enum DictationTextTargetPolicyDecision" in policy
assert "case directAccessibility" in policy
assert "case guardedApplicationPaste" in policy
assert "case reject" in policy
assert "kAXTextFieldRole as String" in policy
assert "kAXTextAreaRole as String" in policy
assert "kAXComboBoxRole as String" in policy
assert "kAXSliderRole as String" in policy
assert "AXWebArea" in policy
assert "AXGenericElement" in policy
assert "AXUnknown" in policy
assert "exposesEditableText ? .guardedApplicationPaste : .reject" in policy
assert "static func displayIndex(" in resolver
assert "static func windowID(" in resolver
assert '@Published private(set) var sessionDisplayID: CGDirectDisplayID?' in service
assert 'result["displayID"] as? NSNumber' in service
assert "await controller.targetSnapshot == target" in service
assert "self.sessionDisplayID = target.displayID" in service
assert "service.sessionDisplayID" in panel
provider = service[
    service.index("private struct XPCTargetProvider"):
    service.index("private struct XPCTextInserter")
]
assert "DictationTargetResolution<DictationTextTarget>" in provider
assert 'case "noFocusedTextTarget": return .copyOnly(.noFocusedTextField)' in provider
assert 'case "nonEditableTarget": return .copyOnly(.nonEditableTarget)' in provider
assert 'case "permissionMissing": throw DictationFailure.accessibilityPermissionDenied' in provider
assert 'default: throw DictationXPCError(code: code)' in provider
assert provider.count("return .copyOnly(") == 2, "Only confirmed missing or non-editable destinations may start copy-only recording."
assert 'return .captured(DictationTextTarget(' in provider
assert 'result["token"] as? String' in provider
assert "localizedDescription" not in provider, "Capture resolution must use helper error codes instead of localized messages."
inserter = service[
    service.index("private struct XPCTextInserter"):
    service.index("private struct DictationXPCError")
]
assert inserter.count("async throws -> DictationInsertionOutcome") == 2
assert inserter.count('return (result["verified"] as? NSNumber)?.boolValue == true ? .verified : .unverified') == 2, "Only explicit app confirmation may discard the recovery copy."
shortcut_key_down = service[
    service.index("case .keyDown, .startVoiceMode:"):
    service.index("case .keyUp:")
]
assert "state = await controller.state" not in shortcut_key_down

noneditable_capture = helper[
    helper.index("case .nonEditable:"):
    helper.index("case let .editable")
]
assert "applicationPasteTarget(focusedElement)" in noneditable_capture, (
    "custom or Electron-style content editors should fall back to guarded application paste"
)
assert '"focusedControl"' not in helper, (
    "browser and Electron insertion must not depend on an unstable AX control fingerprint"
)

# Insert safety: native AX insertion keeps exact-element validation. Browser and
# Electron paste keeps the originally captured process and exact window active.
assert "capturedTextTargets.removeValue(forKey: token)" in helper
assert "currentPID == target.pid" in helper
assert "CFEqual(currentElement, target.element)" in helper
assert helper.count("guard isStillFocused(target) else") >= 2
assert '"error": "applicationPasteRequired"' in helper
assert '"error": "applicationUnicodeRequired"' in helper
unicode_handoff = helper[
    helper.index("if target.kind == .applicationUnicode"):
    helper.index("guard self.isStillFocused(target) else")
]
assert "hasSecureFocusedAncestry(for: target.pid)" in unicode_handoff
secure_helper = helper[
    helper.index("private func hasSecureFocusedAncestry(for"):
    helper.index("/// Returns nil for controls")
]
assert "focusedDescendantTextTarget(from:" in secure_helper
assert '"pid": NSNumber(value: target.pid)' in helper
assert '"windowID": NSNumber(value: windowID)' in helper
assert 'let windowID = result["windowID"] as? NSNumber' in client
assert "CGWindowID(truncating: windowID)" in client
assert "guard await raiseWindow(pid: targetPID, windowID: targetWindowID)" not in client
assert "return await DictationApplicationInsertionService.shared.insertUnicode(" in client
unicode_insertion = client[
    client.index("func insertUnicode("):
    client.index("private func failure(")
]
assert "hasSecureFocusedAncestry(target.pid)" in unicode_insertion
secure_client = client[
    client.index("private func hasSecureFocusedAncestry("):
    client.index("private func copyBool(")
]
assert "focusedDescendant(from:" in secure_client
assert "DictationApplicationPasteTarget(" in client
assert "target: DictationApplicationPasteTarget" in client
assert "NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID" in client
assert "WindowTargetResolver.isCapturedWindowTopmost(" in client
assert "window list unavailable for frontmost" not in client
assert "isCapturedFocusActive(" not in client
assert "validateApplicationPasteTarget" not in client
assert "validateApplicationPasteTarget" not in helper
assert "validateApplicationPasteTarget" not in main_protocol
assert "validateApplicationPasteTarget" not in helper_protocol
assert "commandDown.post(tap: .cghidEventTap)" in client
assert "pasteDown.post(tap: .cghidEventTap)" in client
assert "pasteUp.post(tap: .cghidEventTap)" in client
assert "commandUp.post(tap: .cghidEventTap)" in client
assert "var commandIsDown = false" in client
assert "var pasteIsDown = false" in client
assert "if pasteIsDown" in client
assert "if commandIsDown" in client
assert '"method": "application-paste"' in client
assert '"method": "application-unicode"' in client
assert '"verified": false' in helper
assert '"clipboardRestored": false' in client
assert "let shouldRestore = pasteboard.changeCount == injectedChangeCount" not in client

# Direct AX insertion must precede the narrowly allowed paste fallback.
ax_insert = helper.index("AXUIElementSetAttributeValue(")
paste_fallback = helper.index("insertWithGuardedPaste(text")
assert ax_insert < paste_fallback
assert "guard target.allowsPasteFallback else" in helper
assert '"error": "axInsertionNotConfirmed"' in helper
assert "waitForAccessibilityConfirmation(" in helper
assert "attemptsRemaining: 20" in helper
assert "expectation.confirmsNoMutation(currentValue: currentValue)" in helper
assert "expectation.insertionText" in helper
unverified_reply = helper.index('"error": "axInsertionNotConfirmed"')
verified_reply = helper.index('"verified": true', unverified_reply)
assert unverified_reply < verified_reply

# Clipboard fallback must be transient, preserve the old contents best-effort,
# and never overwrite a clipboard changed by the user or target application.
assert '"org.nspasteboard.TransientType"' in helper
assert "let snapshot = PasteboardSnapshot(pasteboard: pasteboard)" in helper
assert "let isComplete: Bool" in helper
assert "let isComplete: Bool" in client
assert "guard snapshot.isComplete else" in helper
assert "guard snapshot.isComplete else" in client
assert '"clipboardSnapshotUnavailable"' in helper
assert '"clipboardSnapshotUnavailable"' in client
assert "pasteboard.changeCount == injectedChangeCount" in helper
assert "snapshot.restore(to: pasteboard)" in helper
assert '"clipboardRestored": restored' in helper
assert '"error": "pasteNotConfirmed"' in helper
assert "waitForPasteConfirmation(" in helper
assert "PasteMutationExpectation" in helper
assert "elementContainsText" not in helper
assert '"verified": true' in helper

# Every insertion result is structured and the async client exposes both calls.
for key in ('"authorized"', '"success"', '"method"', '"error"'):
    assert key in helper
assert "func captureFocusedTextTarget(promptIfNeeded: Bool = false) async -> NSDictionary" in client
assert "nonisolated func captureAdditionalFocusedTextTarget(promptIfNeeded: Bool = false) async -> NSDictionary" in client
shared_client_capture = client[
    client.index("private nonisolated func captureTextTarget("):
    client.index("private func preferredDictationApplicationPasteTarget(")
]
assert shared_client_capture.count("preferredDictationApplicationPasteTarget()") == 1
assert shared_client_capture.count("notifyAuthorizationChange(authorized)") == 1
assert "service.captureFocusedTextTarget(" in shared_client_capture
assert "service.captureAdditionalFocusedTextTarget(" in shared_client_capture
assert "func insertText(_ text: String, token: String) async -> NSDictionary" in client
assert client.count('"error": "helperUnavailable"') >= 2

# The helper is TCC-authorized, so it must reject XPC clients that are not
# signed as the containing Gojo app.
assert "XPCClientValidator.accepts(newConnection)" in helper_main
assert 'identifier "rohoswagger.gojo"' in helper_main
assert 'certificate leaf[subject.OU] = "L6U44C67P5"' in helper_main
assert "SecCodeCopyGuestWithAttributes" in helper_main
assert "SecCodeCheckValidity" in helper_main
assert "newConnection.invalidate()" in helper_main
PY

tmp_binary="$(mktemp -t gojo-paste-mutation.XXXXXX)"
target_binary="$(mktemp -t gojo-application-paste-target.XXXXXX)"
policy_binary="$(mktemp -t gojo-dictation-text-target-policy.XXXXXX)"
chromium_binary="$(mktemp -t gojo-chromium-focused-descendant.XXXXXX)"
trap 'rm -f "$tmp_binary" "$target_binary" "$policy_binary" "$chromium_binary"' EXIT
xcrun swiftc \
  GojoXPCHelper/PasteMutationExpectation.swift \
  tests/paste_mutation_regression.swift \
  -o "$tmp_binary"
"$tmp_binary"

xcrun swiftc \
  GojoXPCHelper/DictationTextTargetPolicy.swift \
  tests/dictation_text_target_policy_regression.swift \
  -o "$policy_binary"
"$policy_binary"

xcrun swiftc \
  Gojo/WindowManagement/WindowTargetResolver.swift \
  tests/application_paste_target_regression.swift \
  -o "$target_binary"
"$target_binary"

xcrun swiftc \
  tests/chromium_focused_descendant_regression.swift \
  -o "$chromium_binary"
"$chromium_binary"

echo "text insertion XPC regression checks passed"
