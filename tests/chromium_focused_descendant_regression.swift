import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private enum FixtureDecision: Equatable {
    case directAccessibility(String)
    case guardedApplicationPaste(String)
    case reject
}

private final class FixtureAXElement {
    let id: String
    let role: String
    let isFocused: Bool
    let isEnabled: Bool
    let isSelectedTextSettable: Bool
    let isSelectedTextRangeSettable: Bool
    let isValueSettable: Bool
    let children: [FixtureAXElement]

    init(
        id: String,
        role: String,
        isFocused: Bool = false,
        isEnabled: Bool = true,
        isSelectedTextSettable: Bool = false,
        isSelectedTextRangeSettable: Bool = false,
        isValueSettable: Bool = false,
        children: [FixtureAXElement] = []
    ) {
        self.id = id
        self.role = role
        self.isFocused = isFocused
        self.isEnabled = isEnabled
        self.isSelectedTextSettable = isSelectedTextSettable
        self.isSelectedTextRangeSettable = isSelectedTextRangeSettable
        self.isValueSettable = isValueSettable
        self.children = children
    }
}

private enum ChromiumFocusedDescendantFixtureResolver {
    static func decision(from coarseFocusedElement: FixtureAXElement) -> FixtureDecision {
        guard coarseFocusedElement.role == "AXWebArea" else {
            return decision(for: coarseFocusedElement)
        }
        guard let focusedDescendant = focusedDescendant(in: coarseFocusedElement) else {
            return .reject
        }
        return decision(for: focusedDescendant)
    }

    private static func focusedDescendant(in element: FixtureAXElement) -> FixtureAXElement? {
        if element.isFocused && element.role != "AXWebArea" {
            return element
        }
        for child in element.children {
            if let focused = focusedDescendant(in: child) {
                return focused
            }
        }
        return nil
    }

    private static func decision(for element: FixtureAXElement) -> FixtureDecision {
        guard element.isEnabled else { return .reject }
        let exposesEditableText = element.isSelectedTextSettable
            || element.isSelectedTextRangeSettable
            || element.isValueSettable

        switch element.role {
        case "AXTextField", "AXTextArea", "AXComboBox":
            return exposesEditableText ? .directAccessibility(element.id) : .reject
        case "AXGroup", "AXWebArea", "AXGenericElement", "AXUnknown", "AXCell":
            return exposesEditableText ? .guardedApplicationPaste(element.id) : .reject
        default:
            return .reject
        }
    }
}

private func resolvesNestedFocusedTextInputWhenChromiumFocusReportsPageWebArea() {
    let activeInput = FixtureAXElement(
        id: "prompt-input",
        role: "AXTextArea",
        isFocused: true,
        isSelectedTextSettable: true,
        isSelectedTextRangeSettable: true
    )
    let pageWebArea = FixtureAXElement(
        id: "page",
        role: "AXWebArea",
        children: [
            FixtureAXElement(id: "toolbar", role: "AXGroup"),
            activeInput,
        ]
    )

    require(
        ChromiumFocusedDescendantFixtureResolver.decision(from: pageWebArea)
            == .directAccessibility("prompt-input"),
        "Chromium page AXWebArea focus should resolve to the nested focused text input"
    )
}

private func resolvesNestedFocusedContentEditableWhenChromiumFocusReportsPageWebArea() {
    let editor = FixtureAXElement(
        id: "message-editor",
        role: "AXGroup",
        isFocused: true,
        isSelectedTextSettable: true,
        isSelectedTextRangeSettable: true
    )
    let pageWebArea = FixtureAXElement(
        id: "page",
        role: "AXWebArea",
        children: [
            FixtureAXElement(id: "sidebar", role: "AXGroup"),
            FixtureAXElement(id: "composer", role: "AXGroup", children: [editor]),
        ]
    )

    require(
        ChromiumFocusedDescendantFixtureResolver.decision(from: pageWebArea)
            == .guardedApplicationPaste("message-editor"),
        "Chromium page AXWebArea focus should resolve to the nested focused contenteditable editor"
    )
}

private func rejectsUnrelatedPageWebAreaWhenNoFocusedEditableDescendantExists() {
    let unrelatedInput = FixtureAXElement(
        id: "stale-input",
        role: "AXTextField",
        isFocused: false,
        isValueSettable: true
    )
    let pageWebArea = FixtureAXElement(
        id: "page",
        role: "AXWebArea",
        children: [
            FixtureAXElement(id: "nav", role: "AXGroup"),
            unrelatedInput,
        ]
    )

    require(
        ChromiumFocusedDescendantFixtureResolver.decision(from: pageWebArea) == .reject,
        "unrelated page AXWebArea should not be accepted without a focused editable descendant"
    )
}

resolvesNestedFocusedTextInputWhenChromiumFocusReportsPageWebArea()
resolvesNestedFocusedContentEditableWhenChromiumFocusReportsPageWebArea()
rejectsUnrelatedPageWebAreaWhenNoFocusedEditableDescendantExists()
