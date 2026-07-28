import ApplicationServices
import Foundation

enum DictationTextTargetPolicyDecision: Equatable {
    case directAccessibility
    case guardedApplicationPaste
    case reject
}

struct DictationTextTargetCapabilities: Equatable {
    let role: String
    let isEnabled: Bool
    let isSelectedTextSettable: Bool
    let isSelectedTextRangeSettable: Bool
    let isValueSettable: Bool
}

enum DictationTextTargetPolicy {
    private static let nativeTextRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    private static let customEditorRoles: Set<String> = [
        kAXGroupRole as String,
        "AXWebArea",
        "AXGenericElement",
        "AXUnknown",
        "AXCell",
    ]

    private static let interactiveNonTextRoles: Set<String> = [
        kAXSliderRole as String,
        "AXScrollBar",
        "AXButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXMenuItem",
        "AXIncrementor",
        "AXLink",
        "AXImage",
        "AXColorWell",
        "AXDisclosureTriangle",
        "AXTab",
        "AXToolbar",
        "AXTable",
        "AXOutline",
        "AXList",
        "AXBrowser",
    ]

    static func decision(
        for capabilities: DictationTextTargetCapabilities
    ) -> DictationTextTargetPolicyDecision {
        guard capabilities.isEnabled else { return .reject }

        let exposesEditableText =
            capabilities.isSelectedTextSettable
            || capabilities.isSelectedTextRangeSettable
            || capabilities.isValueSettable

        if nativeTextRoles.contains(capabilities.role) {
            return exposesEditableText
                ? .directAccessibility
                : .guardedApplicationPaste
        }

        if customEditorRoles.contains(capabilities.role) {
            return exposesEditableText ? .guardedApplicationPaste : .reject
        }

        return .reject
    }

    static func blocksAncestorFallback(role: String) -> Bool {
        interactiveNonTextRoles.contains(role)
    }
}
