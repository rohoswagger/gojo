import Foundation

enum DictationVocabularyImport {
    static let maximumBytes = 1_048_576

    enum Format: Sendable {
        case json
        case csv
        case wordList
    }

    struct Report: Equatable, Sendable {
        let added: Int
        let duplicates: Int
        let invalid: Int
        let overLimit: Int
    }

    struct Document: Sendable {
        fileprivate let words: [Word]
        let invalidCount: Int

        func merging(into existing: [DictationVocabularyEntry]) -> MergeResult {
            var entries = existing
            var seen = Set(existing.flatMap { [key($0.spoken), key($0.replacement)] })
            var duplicates = 0
            var overLimit = 0
            var added = 0
            for word in words {
                guard seen.insert(word.key).inserted else {
                    duplicates += 1
                    continue
                }
                guard entries.count < DictationVocabularyEntry.maximumEntries else {
                    overLimit += 1
                    continue
                }
                entries.append(DictationVocabularyEntry(spoken: word.value, replacement: word.value))
                added += 1
            }
            return MergeResult(
                entries: entries,
                report: Report(added: added, duplicates: duplicates, invalid: invalidCount, overLimit: overLimit)
            )
        }
    }

    struct MergeResult: Sendable {
        let entries: [DictationVocabularyEntry]
        let report: Report
    }

    enum Failure: LocalizedError, Equatable {
        case tooLarge
        case unreadableEncoding
        case malformedJSON
        case unsupportedJSONShape
        case malformedCSV(record: Int)
        case ambiguousCSVHeader

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                return "The vocabulary input exceeds 1 MiB."
            case .unreadableEncoding:
                return "The vocabulary input must use UTF-8 text."
            case .malformedJSON:
                return "The JSON syntax is invalid."
            case .unsupportedJSONShape:
                return "Use a JSON array of words or an object with a words array."
            case .malformedCSV(let record):
                return "The CSV syntax or column count is invalid in record \(record)."
            case .ambiguousCSVHeader:
                return "The CSV header has more than one word, words, or term column."
            }
        }
    }

    fileprivate struct Word: Sendable {
        let value: String
        let key: String

        init?(_ raw: String) {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= DictationVocabularyEntry.maximumSpokenLength,
                  !value.unicodeScalars.contains(where: {
                switch $0.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator: return true
                default: return false
                }
            }) else { return nil }
            self.value = value
            key = DictationVocabularyImport.key(value)
        }
    }

    static func parse(_ data: Data, format: Format) throws -> Document {
        try Task.checkCancellation()
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw Failure.unreadableEncoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Document(words: [], invalidCount: 0)
        }
        switch format {
        case .json: return try parseJSON(text)
        case .csv: return try parseCSV(text)
        case .wordList:
            return try document(from: text.components(separatedBy: CharacterSet(charactersIn: "\r\n")).filter {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }
    }

    private static func key(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    private static func document(from candidates: [String?]) throws -> Document {
        var words: [Word] = []
        var invalid = 0
        for (index, candidate) in candidates.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            if let candidate, let word = Word(candidate) {
                words.append(word)
            } else {
                invalid += 1
            }
        }
        return Document(words: words, invalidCount: invalid)
    }

    private static func parseJSON(_ text: String) throws -> Document {
        var insideString = false
        var escaped = false
        var previous: Unicode.Scalar?
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            if insideString {
                if escaped {
                    escaped = false
                } else if scalar == "\\" {
                    escaped = true
                } else if scalar == "\"" {
                    insideString = false
                }
            } else if scalar == "\"" {
                insideString = true
            } else if (scalar == "]" || scalar == "}"), previous == "," {
                // Foundation accepts trailing commas although JSON does not.
                throw Failure.malformedJSON
            }
            if insideString || !CharacterSet.whitespacesAndNewlines.contains(scalar) { previous = scalar }
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
        } catch {
            throw Failure.malformedJSON
        }
        let items: [Any]
        if let array = root as? [Any] {
            items = array
        } else if let object = root as? [String: Any], let array = object["words"] as? [Any] {
            items = array
        } else {
            throw Failure.unsupportedJSONShape
        }
        return try document(from: items.map { item in
            if let word = item as? String { return word }
            return (item as? [String: Any])?["word"] as? String
        })
    }

    private enum CSVFieldState {
        case leadingSpace
        case unquoted
        case quoted
        case closedQuote
    }

    private static func parseCSV(_ text: String) throws -> Document {
        let scalars = Array(text.unicodeScalars)
        var state = CSVFieldState.leadingSpace
        var field = String.UnicodeScalarView()
        var row: [String] = []
        var records: [(number: Int, fields: [String])] = []
        var recordNumber = 1
        var explicitRecord = false
        var index = 0

        func finishField() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            state = .leadingSpace
        }

        func finishRecord() {
            finishField()
            if explicitRecord || row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                records.append((recordNumber, row))
            }
            row = []
            explicitRecord = false
            recordNumber += 1
        }

        while index < scalars.count {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let scalar = scalars[index]
            if state == .quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append(scalar)
                        index += 1
                    } else {
                        state = .closedQuote
                    }
                } else {
                    field.append(scalar)
                }
            } else if scalar == "\r" || scalar == "\n" {
                finishRecord()
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 1
                }
            } else if scalar == "," {
                explicitRecord = true
                finishField()
            } else {
                switch state {
                case .leadingSpace:
                    if scalar == "\"" {
                        field = String.UnicodeScalarView()
                        explicitRecord = true
                        state = .quoted
                    } else {
                        field.append(scalar)
                        if scalar != " " { state = .unquoted }
                    }
                case .unquoted:
                    guard scalar != "\"" else { throw Failure.malformedCSV(record: recordNumber) }
                    field.append(scalar)
                case .closedQuote:
                    guard scalar == " " else { throw Failure.malformedCSV(record: recordNumber) }
                case .quoted:
                    break
                }
            }
            index += 1
        }
        guard state != .quoted else { throw Failure.malformedCSV(record: recordNumber) }
        finishRecord()
        guard let first = records.first else { return Document(words: [], invalidCount: 0) }
        let wordColumns = first.fields.indices.filter {
            ["word", "words", "term"].contains(first.fields[$0].trimmingCharacters(in: .whitespaces).lowercased())
        }
        guard wordColumns.count <= 1 else { throw Failure.ambiguousCSVHeader }
        if let column = wordColumns.first {
            var candidates: [String?] = []
            for record in records.dropFirst() {
                try Task.checkCancellation()
                guard record.fields.count == first.fields.count else {
                    throw Failure.malformedCSV(record: record.number)
                }
                candidates.append(record.fields[column])
            }
            return try document(from: candidates)
        }
        return try document(from: records.flatMap(\.fields))
    }
}
