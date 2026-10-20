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

struct DictationCorrectionSnapshot: Equatable, Sendable {
    static let maximumValueLength = 64_000
    static let maximumEditedLength = 4_000

    let insertedText: String
    let prefix: String
    let suffix: String

    /// `caret` must be collapsed and sit immediately after `insertedText`.
    init?(value: String, caret: CFRange, insertedText: String) {
        let inserted = insertedText as NSString
        let current = value as NSString
        guard inserted.length > 0,
              insertedText.count <= Self.maximumEditedLength,
              current.length <= Self.maximumValueLength,
              caret.length == 0,
              caret.location >= inserted.length,
              caret.location <= current.length else { return nil }
        let insertionRange = NSRange(
            location: caret.location - inserted.length,
            length: inserted.length
        )
        guard Self.isScalarAligned(insertionRange, in: value),
              current.substring(with: insertionRange) == insertedText else { return nil }
        let prefix = current.substring(to: insertionRange.location)
        let suffix = current.substring(from: caret.location)
        self.insertedText = insertedText
        self.prefix = prefix
        self.suffix = suffix
    }

    /// NSString maps a split surrogate pair to U+FFFD, so equal-looking text
    /// can hide an invalid boundary; check it against the Swift String.
    private static func isScalarAligned(_ range: NSRange, in value: String) -> Bool {
        guard let swiftRange = Range(range, in: value) else { return false }
        return swiftRange.lowerBound.samePosition(in: value.unicodeScalars) != nil
            && swiftRange.upperBound.samePosition(in: value.unicodeScalars) != nil
    }

    /// The text between the unchanged prefix and suffix, or nil when either
    /// side changed or the value or span is out of bounds. With an empty
    /// suffix, text appended after the insertion is indistinguishable from an
    /// edit of it; callers must treat a pure append as no correction.
    func editedText(in value: String) -> String? {
        let current = value as NSString
        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        guard current.length <= Self.maximumValueLength,
              current.length >= prefixLength + suffixLength else { return nil }
        guard current.substring(to: prefixLength) == prefix,
              current.substring(from: current.length - suffixLength) == suffix else { return nil }
        let middleRange = NSRange(
            location: prefixLength,
            length: current.length - prefixLength - suffixLength
        )
        guard Self.isScalarAligned(middleRange, in: value) else { return nil }
        let middle = current.substring(with: middleRange)
        guard middle.count <= Self.maximumEditedLength else { return nil }
        return middle
    }
}
