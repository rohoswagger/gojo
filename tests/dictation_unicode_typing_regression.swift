import CoreGraphics
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func chunksStayWithinCoreGraphicsUnicodeEventLimit() {
    let chunks = DictationUnicodeTextInjector.chunks(
        for: "abcdefghijklmnopqrstuvwxyz",
        maxUTF16Units: 20
    )

    require(
        chunks.map { $0.utf16.count } == [20, 6],
        "Unicode typing chunks should stay within the 20 UTF-16 unit CoreGraphics event limit"
    )
}

private func chunksDoNotSplitExtendedGraphemeClusters() {
    let family = "👨‍👩‍👧‍👦"
    let text = "abcdefghijklmnopqrs\(family)tail"
    let chunks = DictationUnicodeTextInjector.chunks(for: text, maxUTF16Units: 20)

    require(
        chunks.joined() == text,
        "Unicode typing chunks should round-trip the transcript exactly"
    )
    require(
        chunks.allSatisfy { $0.utf16.count <= 20 },
        "Unicode typing chunks should never exceed the CoreGraphics event limit"
    )
    require(
        chunks.contains { $0.contains(family) },
        "Unicode typing chunks should keep an extended grapheme cluster intact when it would cross a boundary"
    )
}

private func overlongGraphemeFailsClosed() {
    let overlongGrapheme = "a" + String(repeating: "\u{0301}", count: 20)
    require(
        DictationUnicodeTextInjector.chunks(for: overlongGrapheme).isEmpty,
        "A grapheme larger than one CoreGraphics event should be rejected instead of split"
    )
}

private func partialDeliveryIsReportedPrecisely() {
    require(
        DictationUnicodeTextInjector.failure(
            afterPostedChunks: 0,
            fallbackCode: "focusChanged"
        ) == .init(code: "focusChanged", isPartialInsertion: false),
        "Focus loss before the first chunk should not claim partial delivery"
    )
    require(
        DictationUnicodeTextInjector.failure(
            afterPostedChunks: 1,
            fallbackCode: "focusChanged"
        ) == .init(code: "partialInsertion", isPartialInsertion: true),
        "Focus loss after a chunk should report partial delivery"
    )
    require(
        DictationUnicodeTextInjector.failure(
            afterPostedChunks: 2,
            fallbackCode: "unicodeEventUnavailable"
        ) == .init(code: "partialInsertion", isPartialInsertion: true),
        "Event failure after earlier chunks should report partial delivery"
    )
}

@main
struct DictationUnicodeTypingRegressionRunner {
    static func main() {
        chunksStayWithinCoreGraphicsUnicodeEventLimit()
        chunksDoNotSplitExtendedGraphemeClusters()
        overlongGraphemeFailsClosed()
        partialDeliveryIsReportedPrecisely()
    }
}
