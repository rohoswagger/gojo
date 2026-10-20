import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct PasteMutationRegressionRunner {
    static func main() {
        let transcript = "Gojo local dictation."
        let existing = "Already here: \(transcript)"
        let append = PasteMutationExpectation(
            originalValue: existing,
            selectedRange: CFRange(location: (existing as NSString).length, length: 0),
            insertionText: transcript
        )
        require(append != nil, "an insertion with a visible mutation should be verifiable")
        require(
            append?.confirms(currentValue: existing) == false,
            "pre-existing transcript text must not confirm an unconsumed paste"
        )
        require(
            append?.confirmsNoMutation(currentValue: existing) == true,
            "an unchanged field should permit the guarded paste fallback"
        )
        require(
            append?.confirms(currentValue: existing + transcript) == true,
            "only the exact expected before/selection/after value should confirm paste"
        )
        require(
            append?.confirmsNoMutation(currentValue: existing + "other") == false,
            "a changed field must not permit a second insertion attempt"
        )

        let identicalSelection = PasteMutationExpectation(
            originalValue: transcript,
            selectedRange: CFRange(location: 0, length: (transcript as NSString).length),
            insertionText: transcript
        )
        require(
            identicalSelection == nil,
            "an identical replacement has no observable mutation and must fail closed"
        )

        let unicodeOriginal = "A🙂B"
        let unicodeReplacement = PasteMutationExpectation(
            originalValue: unicodeOriginal,
            selectedRange: CFRange(location: 1, length: 2),
            insertionText: "voice"
        )
        require(
            unicodeReplacement?.expectedValue == "AvoiceB",
            "AX UTF-16 ranges should produce the exact replacement value"
        )

        verifyCorrectionSnapshot()
    }

    static func verifyCorrectionSnapshot() {
        let inserted = "hello 🙂 world"
        let insertedLength = (inserted as NSString).length
        let value = "Before: \(inserted) after 🙂"
        let caret = CFRange(location: ("Before: " as NSString).length + insertedLength, length: 0)
        let snapshot = DictationCorrectionSnapshot(value: value, caret: caret, insertedText: inserted)
        require(snapshot?.prefix == "Before: ", "snapshot should capture the text before the insertion")
        require(snapshot?.suffix == " after 🙂", "snapshot should capture the text after the insertion")
        require(snapshot?.editedText(in: value) == inserted, "an untouched field should return the inserted text")
        require(
            snapshot?.editedText(in: "Before: hello 🙂 word after 🙂") == "hello 🙂 word",
            "an edit inside the span should return only the span"
        )
        require(
            snapshot?.editedText(in: "Before:  after 🙂") == "",
            "deleting the whole span should return an empty span"
        )
        require(
            snapshot?.editedText(in: "Before!: hello 🙂 world after 🙂") == nil,
            "a prefix modification must be rejected"
        )
        require(
            snapshot?.editedText(in: "Before: hello 🙂 world after 🙃") == nil,
            "a suffix modification must be rejected"
        )
        require(
            snapshot?.editedText(in: "Before: hello 🙂 world after 🙂!") == nil,
            "text typed after the suffix must be rejected"
        )
        require(snapshot?.editedText(in: "short") == nil, "a value shorter than prefix plus suffix must be rejected")

        let append = DictationCorrectionSnapshot(
            value: "Hi \(inserted)",
            caret: CFRange(location: ("Hi " as NSString).length + insertedLength, length: 0),
            insertedText: inserted
        )
        require(append?.suffix == "", "an insertion at the end has an empty suffix")
        require(
            append?.editedText(in: "Hi \(inserted) and more") == "\(inserted) and more",
            "with an empty suffix an append is part of the span so the host must reject pure appends"
        )
        require(append?.editedText(in: "Hey \(inserted)") == nil, "the prefix stays fixed with an empty suffix")

        require(
            DictationCorrectionSnapshot(
                value: value,
                caret: CFRange(location: caret.location, length: 1),
                insertedText: inserted
            ) == nil,
            "a non-collapsed selection must be rejected"
        )
        require(
            DictationCorrectionSnapshot(
                value: value,
                caret: CFRange(location: caret.location - 1, length: 0),
                insertedText: inserted
            ) == nil,
            "a caret that does not follow the inserted text must be rejected"
        )
        require(
            DictationCorrectionSnapshot(
                value: value,
                caret: CFRange(location: -1, length: 0),
                insertedText: inserted
            ) == nil,
            "a negative caret must be rejected"
        )
        require(
            DictationCorrectionSnapshot(
                value: value,
                caret: CFRange(location: (value as NSString).length + 1, length: 0),
                insertedText: inserted
            ) == nil,
            "a caret past the end must be rejected"
        )
        require(
            DictationCorrectionSnapshot(value: value, caret: caret, insertedText: "") == nil,
            "empty inserted text must be rejected"
        )
        let split = DictationCorrectionSnapshot(
            value: "A🙂B",
            caret: CFRange(location: 2, length: 0),
            insertedText: "A"
        )
        require(split == nil, "a range splitting a surrogate pair must be rejected")
        let lossySplit = DictationCorrectionSnapshot(
            value: "🙂",
            caret: CFRange(location: 1, length: 0),
            insertedText: "\u{FFFD}"
        )
        require(lossySplit == nil, "a split surrogate must not pass as a replacement character")
        let edgeSuffix = DictationCorrectionSnapshot(
            value: "Ab\u{FFFD}",
            caret: CFRange(location: 2, length: 0),
            insertedText: "b"
        )
        require(edgeSuffix?.editedText(in: "A🙂") == nil, "an edited span ending inside a surrogate pair must be rejected")
        let edgePrefix = DictationCorrectionSnapshot(
            value: "\u{FFFD}b",
            caret: CFRange(location: 2, length: 0),
            insertedText: "b"
        )
        require(edgePrefix?.editedText(in: "🙂") == nil, "an edited span starting inside a surrogate pair must be rejected")

        let big = String(repeating: "x", count: DictationCorrectionSnapshot.maximumValueLength + 1)
        require(
            DictationCorrectionSnapshot(
                value: big,
                caret: CFRange(location: big.utf16.count, length: 0),
                insertedText: "x"
            ) == nil,
            "an oversized field must be rejected"
        )
        let limit = String(repeating: "x", count: DictationCorrectionSnapshot.maximumEditedLength)
        let bounded = DictationCorrectionSnapshot(
            value: "a" + inserted,
            caret: CFRange(location: 1 + insertedLength, length: 0),
            insertedText: inserted
        )
        require(
            bounded?.editedText(in: "a" + limit) == limit,
            "a span at the character limit is allowed"
        )
        require(
            bounded?.editedText(in: "a" + limit + "x") == nil,
            "a span over the character limit must be rejected"
        )
        require(
            bounded?.editedText(in: big) == nil,
            "an oversized current value must be rejected"
        )
    }
}
