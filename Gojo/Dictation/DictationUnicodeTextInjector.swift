import CoreGraphics
import Foundation

enum DictationUnicodeTextInjector {
    struct Failure: Equatable {
        let code: String
        let isPartialInsertion: Bool
    }

    static let eventUTF16Limit = 20

    static func failure(
        afterPostedChunks postedChunkCount: Int,
        fallbackCode: String
    ) -> Failure {
        guard postedChunkCount > 0 else {
            return Failure(
                code: fallbackCode,
                isPartialInsertion: false
            )
        }
        return Failure(
            code: "partialInsertion",
            isPartialInsertion: true
        )
    }

    static func chunks(
        for text: String,
        maxUTF16Units: Int = eventUTF16Limit
    ) -> [String] {
        guard maxUTF16Units > 0, !text.isEmpty else { return [] }

        var result: [String] = []
        var current = ""
        var currentUTF16Count = 0

        for character in text {
            let value = String(character)
            let valueUTF16Count = value.utf16.count
            guard valueUTF16Count <= maxUTF16Units else {
                return []
            }

            if currentUTF16Count + valueUTF16Count > maxUTF16Units {
                result.append(current)
                current = value
                currentUTF16Count = valueUTF16Count
            } else {
                current.append(character)
                currentUTF16Count += valueUTF16Count
            }
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func post(
        _ text: String,
        source: CGEventSource? = nil,
        tap: CGEventTapLocation = .cgSessionEventTap
    ) -> Bool {
        guard !text.isEmpty,
              text.utf16.count <= eventUTF16Limit,
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 0,
                keyDown: false
              ) else {
            return false
        }

        var utf16 = Array(text.utf16)
        keyDown.flags = []
        keyUp.flags = []
        keyDown.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: &utf16
        )
        keyUp.keyboardSetUnicodeString(
            stringLength: utf16.count,
            unicodeString: &utf16
        )
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        return true
    }
}
