import Foundation

enum DictationFinalTextPolicy {
    struct Prepared: Equatable, Sendable {
        let options: DictationTextOptions
        let document: DictationSpokenCommands.Document
        let protectedTerms: [String]

        var transcript: String { document.transcript }
    }

    static func prepare(_ transcript: String, options: DictationTextOptions) -> Prepared {
        let normalized = transcript
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let document = DictationSpokenCommands.parse(
            normalized,
            mode: options.commands,
            language: options.commandLanguage
        ).mappingText { text in
            DictationVocabularyPolicy.apply(options.vocabulary, to: text)
        }
        let corrected = document.transcript
        return Prepared(
            options: options,
            document: document,
            protectedTerms: options.vocabulary.map(\.replacement) + semanticTerms(in: corrected)
        )
    }

    static func finalize(_ prepared: Prepared, polishedTranscript: String? = nil) -> String {
        let fallback = DictationSpokenCommands.render(prepared.document)
        guard case .s1Mini(let style) = prepared.options.cleanup,
              let polishedTranscript,
              S1MiniOutputPolicy.isSafe(
                rawTranscript: prepared.transcript,
                polishedTranscript: polishedTranscript,
                protectedTerms: []
              ),
              signature(of: prepared.protectedTerms, in: polishedTranscript)
                == signature(of: prepared.protectedTerms, in: prepared.transcript),
              DictationSpokenCommands.restoringProtectedSpans(
                in: polishedTranscript,
                from: prepared.document
              ) != nil else {
            return fallback
        }
        let polished = S1MiniVocabularyPipeline.finalize(
            correctedRawTranscript: prepared.transcript,
            polishedTranscript: polishedTranscript,
            vocabulary: prepared.options.vocabulary,
            style: style
        )
        guard let spellingPreserved = restoringIdentifierSpelling(in: polished, prepared: prepared),
              let restored = DictationSpokenCommands.restoringProtectedSpans(
            in: spellingPreserved,
            from: prepared.document
        ) else {
            return fallback
        }
        return DictationSpokenCommands.render(restored)
    }

    private static func semanticTerms(in transcript: String) -> [String] {
        let pattern = "[+-]?\\p{N}+(?:[.,:/-]\\p{N}+)*|[\\p{L}\\p{M}_][\\p{L}\\p{M}\\p{N}_]*(?:['’][\\p{L}\\p{M}]+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let negations: Set<String> = [
            "no", "not", "never", "neither", "nor", "nobody", "nothing", "nowhere", "without",
            "cannot", "can't", "don't", "doesn't", "didn't", "isn't", "aren't", "wasn't", "weren't",
            "won't", "wouldn't", "shouldn't", "couldn't", "mustn't", "hasn't", "haven't", "hadn't"
        ]
        return regex.matches(
            in: transcript,
            range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        ).compactMap { match in
            guard let range = Range(match.range, in: transcript) else { return nil }
            let term = String(transcript[range])
            let lowercased = term.lowercased().replacingOccurrences(of: "’", with: "'")
            return isIdentifier(term) || negations.contains(lowercased) ? term : nil
        }
    }

    private static func isIdentifier(_ term: String) -> Bool {
        term.contains("_")
            || term.rangeOfCharacter(from: .decimalDigits) != nil
            || (term.first?.isLowercase == true && term.dropFirst().contains(where: \.isUppercase))
    }

    private static func restoringIdentifierSpelling(in transcript: String, prepared: Prepared) -> String? {
        let terms = prepared.protectedTerms.filter(isIdentifier)
        let original = matches(of: terms, in: prepared.transcript)
        let polished = matches(of: terms, in: transcript)
        guard original.map(\.key) == polished.map(\.key) else { return nil }
        let source = prepared.transcript as NSString
        let output = NSMutableString(string: transcript)
        for (before, after) in zip(original, polished).reversed() {
            output.replaceCharacters(in: after.range, with: source.substring(with: before.range))
        }
        return output as String
    }

    private static func signature(of terms: [String], in transcript: String) -> [String] {
        matches(of: terms, in: transcript).map(\.key)
    }

    private static func matches(of terms: [String], in transcript: String) -> [(range: NSRange, key: String)] {
        var seen = Set<String>()
        var matches: [(range: NSRange, key: String)] = []
        for term in terms.sorted(by: { $0.utf16.count > $1.utf16.count }) {
            let key = term.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard !term.isEmpty, seen.insert(key).inserted else { continue }
            let pattern = "(?<![\\p{L}\\p{M}\\p{N}_])"
                + NSRegularExpression.escapedPattern(for: term)
                + "(?![\\p{L}\\p{M}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(
                in: transcript,
                range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            ) {
                guard !matches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else {
                    continue
                }
                matches.append((match.range, key))
            }
        }
        return matches.sorted { $0.range.location < $1.range.location }
    }
}
