import Foundation

struct PasteMutationExpectation: Equatable, Sendable {
    let originalValue: String
    let expectedValue: String
    let insertionText: String

    init?(originalValue: String, selectedRange: CFRange, insertionText: String) {
        guard selectedRange.location >= 0, selectedRange.length >= 0 else { return nil }
        let original = originalValue as NSString
        let replacementRange = NSRange(
            location: selectedRange.location,
            length: selectedRange.length
        )
        guard NSMaxRange(replacementRange) <= original.length else { return nil }
        let expectedValue = original.replacingCharacters(
            in: replacementRange,
            with: insertionText
        )
        // No observable value change means the helper cannot prove that the
        // target consumed Cmd-V before restoring the previous clipboard.
        guard expectedValue != originalValue else { return nil }
        self.originalValue = originalValue
        self.expectedValue = expectedValue
        self.insertionText = insertionText
    }

    func confirms(currentValue: String?) -> Bool {
        currentValue == expectedValue
    }

    func confirmsNoMutation(currentValue: String?) -> Bool {
        currentValue == originalValue
    }
}
