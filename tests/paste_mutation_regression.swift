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
    }
}
