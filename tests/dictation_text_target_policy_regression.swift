import ApplicationServices
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func decision(
    role: String,
    isEnabled: Bool = true,
    isSelectedTextSettable: Bool = false,
    isSelectedTextRangeSettable: Bool = false,
    isValueSettable: Bool = false
) -> DictationTextTargetPolicyDecision {
    DictationTextTargetPolicy.decision(
        for: DictationTextTargetCapabilities(
            role: role,
            isEnabled: isEnabled,
            isSelectedTextSettable: isSelectedTextSettable,
            isSelectedTextRangeSettable: isSelectedTextRangeSettable,
            isValueSettable: isValueSettable
        )
    )
}

private func acceptsNativeAXTextFieldWhenValueIsEditable() {
    require(
        decision(role: kAXTextFieldRole as String, isValueSettable: true) == .directAccessibility,
        "native AXTextField should be accepted for direct accessibility insertion"
    )
}

private func acceptsNativeAXTextAreaWhenSelectionIsEditable() {
    require(
        decision(
            role: kAXTextAreaRole as String,
            isSelectedTextSettable: true,
            isSelectedTextRangeSettable: true
        ) == .directAccessibility,
        "native AXTextArea should be accepted for direct accessibility insertion"
    )
}

private func acceptsNativeAXComboBoxWhenValueIsEditable() {
    require(
        decision(role: kAXComboBoxRole as String, isValueSettable: true) == .directAccessibility,
        "native AXComboBox should be accepted for direct accessibility insertion"
    )
}

private func rejectsAXSliderWhenValueIsEditable() {
    require(
        decision(role: kAXSliderRole as String, isValueSettable: true) == .reject,
        "AXSlider-like controls must never be treated as editable text"
    )
}

private func usesGuardedApplicationPasteForAXGroupContentEditors() {
    require(
        decision(
            role: kAXGroupRole as String,
            isSelectedTextSettable: true,
            isSelectedTextRangeSettable: true
        ) == .guardedApplicationPaste,
        "custom AXGroup content editors should use guarded application paste"
    )
}

private func usesGuardedApplicationPasteForAXWebAreaContentEditors() {
    require(
        decision(
            role: "AXWebArea",
            isSelectedTextSettable: true,
            isSelectedTextRangeSettable: true
        ) == .guardedApplicationPaste,
        "Electron-style AXWebArea content editors should use guarded application paste"
    )
}

private func usesGuardedApplicationPasteForAXGenericElementContentEditors() {
    require(
        decision(
            role: "AXGenericElement",
            isSelectedTextSettable: true,
            isSelectedTextRangeSettable: true
        ) == .guardedApplicationPaste,
        "Electron-style AXGenericElement content editors should use guarded application paste"
    )
}

private func usesGuardedApplicationPasteForAXUnknownContentEditors() {
    require(
        decision(
            role: "AXUnknown",
            isSelectedTextSettable: true,
            isSelectedTextRangeSettable: true
        ) == .guardedApplicationPaste,
        "opaque AXUnknown content editors should use guarded application paste"
    )
}

private func rejectsNonEditableCustomContainers() {
    for role in [
        kAXGroupRole as String,
        "AXWebArea",
        "AXGenericElement",
        "AXUnknown",
        "AXCell",
    ] {
        require(
            decision(role: role) == .reject,
            "\(role) without an editable AX signal should be rejected"
        )
    }
}

private func rejectsDisabledNativeTextControls() {
    require(
        decision(role: kAXTextFieldRole as String, isEnabled: false, isValueSettable: true) == .reject,
        "disabled native text controls should be rejected"
    )
}

@main
struct DictationTextTargetPolicyRegressionRunner {
    static func main() {
        acceptsNativeAXTextFieldWhenValueIsEditable()
        acceptsNativeAXTextAreaWhenSelectionIsEditable()
        acceptsNativeAXComboBoxWhenValueIsEditable()
        rejectsAXSliderWhenValueIsEditable()
        usesGuardedApplicationPasteForAXGroupContentEditors()
        usesGuardedApplicationPasteForAXWebAreaContentEditors()
        usesGuardedApplicationPasteForAXGenericElementContentEditors()
        usesGuardedApplicationPasteForAXUnknownContentEditors()
        rejectsNonEditableCustomContainers()
        rejectsDisabledNativeTextControls()
    }
}
