import Foundation

enum DictationSpokenCommands {
    enum Spacing: Equatable, Sendable {
        case punctuation
        case joined
        case opening
        case closing
        case prefix
        case spaced
        case lineBreak
    }

    struct Symbol: Equatable, Sendable {
        let text: String
        let spacing: Spacing
    }

    struct ProtectedSpan: Equatable, Sendable {
        let phrase: String
        let replacement: String
        let symbol: Symbol?

        var key: String {
            phrase.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .split(whereSeparator: { $0.isWhitespace && !$0.isNewline })
                .joined(separator: " ")
        }
    }

    enum Segment: Equatable, Sendable {
        case text(String)
        case protected(ProtectedSpan)
    }

    struct Document: Equatable, Sendable {
        let segments: [Segment]

        var transcript: String {
            segments.map { segment in
                switch segment {
                case .text(let text): return text
                case .protected(let span): return span.phrase
                }
            }.joined()
        }

        var protectedSpans: [ProtectedSpan] {
            segments.compactMap { segment in
                guard case .protected(let span) = segment else { return nil }
                return span
            }
        }

        func mappingText(_ transform: (String) -> String) -> Document {
            Document(segments: segments.map { segment in
                guard case .text(let text) = segment else { return segment }
                return .text(transform(text))
            })
        }
    }

    private struct Phrase {
        let text: String
        let symbol: Symbol
        let codeOnly: Bool
    }

    private struct Match {
        let range: NSRange
        let span: ProtectedSpan
    }

    static func parse(
        _ transcript: String,
        mode: DictationSpokenCommandMode,
        language: DictationCommandLanguage
    ) -> Document {
        var matches = lineBreakMatches(in: transcript)
        if mode != .off {
            let commands = phrases(for: language)
                .filter { mode == .punctuationAndCode || !$0.codeOnly }
                .sorted { $0.text.utf16.count > $1.text.utf16.count }
            for command in commands {
                for range in ranges(of: "literal " + command.text, in: transcript) {
                    guard !overlaps(range, matches: matches),
                          let swiftRange = Range(range, in: transcript) else { continue }
                    let phrase = String(transcript[swiftRange])
                    let literal = phrase.drop(while: { !$0.isWhitespace }).drop(while: \.isWhitespace)
                    matches.append(Match(
                        range: range,
                        span: ProtectedSpan(phrase: phrase, replacement: String(literal), symbol: nil)
                    ))
                }
            }
            for command in commands {
                for range in ranges(of: command.text, in: transcript) {
                    guard !overlaps(range, matches: matches),
                          let swiftRange = Range(range, in: transcript) else { continue }
                    matches.append(Match(
                        range: range,
                        span: ProtectedSpan(
                            phrase: String(transcript[swiftRange]),
                            replacement: command.symbol.text,
                            symbol: command.symbol
                        )
                    ))
                }
            }
        }
        return document(transcript, matches: matches)
    }

    static func restoringProtectedSpans(
        in transcript: String,
        from original: Document
    ) -> Document? {
        let expected = original.protectedSpans
        var matches = lineBreakMatches(in: transcript)
        var seen = Set<String>()
        for span in expected.sorted(by: { $0.phrase.utf16.count > $1.phrase.utf16.count }) {
            guard !span.phrase.contains("\n"), seen.insert(span.key).inserted else { continue }
            for range in ranges(of: span.phrase, in: transcript) {
                guard !overlaps(range, matches: matches) else { continue }
                matches.append(Match(range: range, span: span))
            }
        }
        let ordered = matches.sorted { $0.range.location < $1.range.location }
        guard ordered.map(\.span.key) == expected.map(\.key) else { return nil }
        let restored = zip(ordered, expected).map { match, span in
            Match(range: match.range, span: span)
        }
        return document(transcript, matches: restored)
    }

    static func render(_ document: Document) -> String {
        var output = ""
        var nextSpacing: Spacing?
        for segment in document.segments {
            switch segment {
            case .text(let text):
                if nextSpacing != nil, text.allSatisfy({ $0.isWhitespace && !$0.isNewline }) { continue }
                appendText(text, to: &output, after: nextSpacing)
                nextSpacing = nil
            case .protected(let span):
                guard let symbol = span.symbol else {
                    appendText(span.replacement, to: &output, after: nextSpacing)
                    nextSpacing = nil
                    continue
                }
                trimHorizontalEnd(&output)
                let separatesOpening = symbol.spacing == .opening
                    && (nextSpacing == .spaced || nextSpacing == .punctuation)
                if (symbol.spacing == .spaced || symbol.spacing == .prefix || separatesOpening),
                   !output.isEmpty, output.last?.isNewline == false {
                    output += " "
                }
                output += symbol.text
                nextSpacing = symbol.spacing
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    private static func appendText(_ text: String, to output: inout String, after spacing: Spacing?) {
        guard let spacing else {
            output += text
            return
        }
        if spacing == .closing {
            output += text
            return
        }
        let trimmed = text.drop(while: { $0.isWhitespace && !$0.isNewline })
        if spacing == .punctuation || spacing == .spaced {
            if let first = trimmed.first,
               !first.isNewline,
               !",.;:!?)]}".contains(first),
               !output.isEmpty,
               output.last?.isNewline == false {
                output += " "
            }
        }
        output += trimmed
    }

    private static func trimHorizontalEnd(_ text: inout String) {
        while let last = text.last, last.isWhitespace, !last.isNewline {
            text.removeLast()
        }
    }

    private static func lineBreakMatches(in transcript: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: "\\n+") else { return [] }
        let fullRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        return regex.matches(in: transcript, range: fullRange).compactMap { match in
            guard let range = Range(match.range, in: transcript) else { return nil }
            let phrase = String(transcript[range])
            return Match(
                range: match.range,
                span: ProtectedSpan(
                    phrase: phrase,
                    replacement: phrase,
                    symbol: Symbol(text: phrase, spacing: .lineBreak)
                )
            )
        }
    }

    private static func ranges(of phrase: String, in transcript: String) -> [NSRange] {
        let words = phrase.split(whereSeparator: { $0.isWhitespace && !$0.isNewline })
        let pattern = "(?<![\\p{L}\\p{M}\\p{N}_])"
            + words.map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "[^\\S\\r\\n]+")
            + "(?![\\p{L}\\p{M}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(
            in: transcript,
            range: NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        ).map(\.range)
    }

    private static func overlaps(_ range: NSRange, matches: [Match]) -> Bool {
        matches.contains { NSIntersectionRange(range, $0.range).length > 0 }
    }

    private static func document(_ transcript: String, matches: [Match]) -> Document {
        let source = transcript as NSString
        var segments: [Segment] = []
        var position = 0
        for match in matches.sorted(by: { $0.range.location < $1.range.location }) {
            if match.range.location > position {
                segments.append(.text(source.substring(with: NSRange(
                    location: position,
                    length: match.range.location - position
                ))))
            }
            segments.append(.protected(match.span))
            position = NSMaxRange(match.range)
        }
        if position < source.length {
            segments.append(.text(source.substring(from: position)))
        }
        return Document(segments: segments)
    }

    private static func phrases(for language: DictationCommandLanguage) -> [Phrase] {
        var result: [Phrase] = []
        func add(_ names: [String], _ text: String, _ spacing: Spacing = .punctuation, code: Bool = false) {
            result += names.map { Phrase(text: $0, symbol: Symbol(text: text, spacing: spacing), codeOnly: code) }
        }
        switch language {
        case .english:
            add(["comma"], ",")
            add(["period", "full stop"], ".")
            add(["question mark"], "?")
            add(["exclamation mark", "exclamation point"], "!")
            add(["colon"], ":")
            add(["semicolon", "semi colon"], ";")
            add(["new line", "newline"], "\n", .lineBreak)
            add(["new paragraph"], "\n\n", .lineBreak)
            add(["open parenthesis", "open parentheses", "left parenthesis"], "(", .opening, code: true)
            add(["close parenthesis", "close parentheses", "right parenthesis"], ")", .closing, code: true)
            add(["open bracket", "left bracket"], "[", .opening, code: true)
            add(["close bracket", "right bracket"], "]", .closing, code: true)
            add(["open brace", "left brace"], "{", .opening, code: true)
            add(["close brace", "right brace"], "}", .closing, code: true)
            add(["forward slash", "slash"], "/", .joined, code: true)
            add(["backslash", "back slash"], "\\", .joined, code: true)
            add(["hyphen", "dash"], "-", .joined, code: true)
            add(["underscore"], "_", .joined, code: true)
            add(["dot"], ".", .joined, code: true)
            add(["equals", "equal sign"], "=", .spaced, code: true)
            add(["plus", "plus sign"], "+", .spaced, code: true)
            add(["asterisk", "star"], "*", .spaced, code: true)
            add(["less than"], "<", .spaced, code: true)
            add(["greater than"], ">", .spaced, code: true)
            add(["ampersand"], "&", .spaced, code: true)
            add(["pipe", "vertical bar"], "|", .spaced, code: true)
            add(["at sign"], "@", .joined, code: true)
            add(["hash", "pound sign"], "#", .joined, code: true)
            add(["backtick", "back tick"], "`", .joined, code: true)
            add(["double quote"], "\"", .joined, code: true)
            add(["single quote"], "'", .joined, code: true)
        case .spanish:
            add(["coma"], ",")
            add(["punto"], ".")
            add(["signo de interrogación", "cerrar interrogación"], "?")
            add(["abrir interrogación"], "¿", .prefix)
            add(["signo de exclamación", "cerrar exclamación"], "!")
            add(["abrir exclamación"], "¡", .prefix)
            add(["dos puntos"], ":")
            add(["punto y coma"], ";")
            add(["nueva línea", "nueva linea"], "\n", .lineBreak)
            add(["nuevo párrafo", "nuevo parrafo"], "\n\n", .lineBreak)
            add(["abrir paréntesis", "abrir parentesis"], "(", .opening, code: true)
            add(["cerrar paréntesis", "cerrar parentesis"], ")", .closing, code: true)
            add(["abrir corchete"], "[", .opening, code: true)
            add(["cerrar corchete"], "]", .closing, code: true)
            add(["abrir llave"], "{", .opening, code: true)
            add(["cerrar llave"], "}", .closing, code: true)
            add(["barra", "barra diagonal"], "/", .joined, code: true)
            add(["barra inversa"], "\\", .joined, code: true)
            add(["guion", "guión"], "-", .joined, code: true)
            add(["guion bajo", "guión bajo"], "_", .joined, code: true)
            add(["igual", "signo igual"], "=", .spaced, code: true)
            add(["más", "signo más"], "+", .spaced, code: true)
            add(["asterisco"], "*", .spaced, code: true)
            add(["menor que"], "<", .spaced, code: true)
            add(["mayor que"], ">", .spaced, code: true)
            add(["arroba"], "@", .joined, code: true)
            add(["almohadilla"], "#", .joined, code: true)
            add(["comilla invertida"], "`", .joined, code: true)
            add(["comillas dobles"], "\"", .joined, code: true)
            add(["comilla simple"], "'", .joined, code: true)
        case .portuguese:
            add(["vírgula", "virgula"], ",")
            add(["ponto"], ".")
            add(["ponto de interrogação", "ponto de interrogacao"], "?")
            add(["ponto de exclamação", "ponto de exclamacao"], "!")
            add(["dois pontos"], ":")
            add(["ponto e vírgula", "ponto e virgula"], ";")
            add(["nova linha"], "\n", .lineBreak)
            add(["novo parágrafo", "novo paragrafo"], "\n\n", .lineBreak)
            add(["abrir parênteses", "abrir parenteses"], "(", .opening, code: true)
            add(["fechar parênteses", "fechar parenteses"], ")", .closing, code: true)
            add(["abrir colchete"], "[", .opening, code: true)
            add(["fechar colchete"], "]", .closing, code: true)
            add(["abrir chave"], "{", .opening, code: true)
            add(["fechar chave"], "}", .closing, code: true)
            add(["barra", "barra normal"], "/", .joined, code: true)
            add(["barra invertida"], "\\", .joined, code: true)
            add(["hífen", "hifen", "traço", "traco"], "-", .joined, code: true)
            add(["sublinhado", "sublinha"], "_", .joined, code: true)
            add(["igual", "sinal de igual"], "=", .spaced, code: true)
            add(["mais", "sinal de mais"], "+", .spaced, code: true)
            add(["asterisco"], "*", .spaced, code: true)
            add(["menor que"], "<", .spaced, code: true)
            add(["maior que"], ">", .spaced, code: true)
            add(["arroba"], "@", .joined, code: true)
            add(["cerquilha"], "#", .joined, code: true)
            add(["crase"], "`", .joined, code: true)
            add(["aspas duplas"], "\"", .joined, code: true)
            add(["aspas simples"], "'", .joined, code: true)
        }
        return result
    }
}
