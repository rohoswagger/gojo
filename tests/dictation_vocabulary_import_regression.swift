import Foundation

private typealias Import = DictationVocabularyImport

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct DictationVocabularyImportRegression {
    static func main() throws {
        try supportedFormats()
        try jsonShapesAndInvalidItems()
        try encodingAndSizeBounds()
        try atomicSyntaxFailures()
        try csvQuotingAndHeaders()
        try csvEmptyCellsAndLines()
        try validation()
        try duplicateMatching()
        try capacityAndIdempotence()
        try mergeUsesLatestVocabulary()
        print("Dictation vocabulary import regression passed")
    }

    private static func parse(_ text: String, _ format: Import.Format) throws -> Import.Document {
        try Import.parse(Data(text.utf8), format: format)
    }

    private static func expect(
        _ document: Import.Document,
        existing: [DictationVocabularyEntry] = [],
        words: [String],
        report: Import.Report,
        _ message: String
    ) {
        let result = document.merging(into: existing)
        require(result.entries.prefix(existing.count).elementsEqual(existing), "\(message): preserve existing entries")
        require(result.entries.dropFirst(existing.count).map(\.spoken) == words, "\(message): exact imported words")
        require(result.entries.dropFirst(existing.count).map(\.replacement) == words, "\(message): plain words need no aliases")
        require(result.report == report, "\(message): exact report, got \(result.report)")
    }

    private static func expectFailure(
        _ text: String,
        _ format: Import.Format,
        _ expected: Import.Failure,
        _ message: String
    ) {
        do {
            _ = try parse(text, format)
            require(false, "\(message): parsing must fail")
        } catch let error as Import.Failure {
            require(error == expected, "\(message): expected \(expected), got \(error)")
        } catch {
            require(false, "\(message): unexpected error \(error)")
        }
    }

    private static func supportedFormats() throws {
        for (text, format) in [
            (#"[" Kubernetes ","gpt-5.6-sol","New York"]"#, Import.Format.json),
            (" Kubernetes ,gpt-5.6-sol\r\nNew York", .csv),
            (" Kubernetes \r\ngpt-5.6-sol\rNew York\n", .wordList)
        ] {
            expect(try parse(text, format), words: ["Kubernetes", "gpt-5.6-sol", "New York"],
                   report: .init(added: 3, duplicates: 0, invalid: 0, overLimit: 0), "supported format")
        }
        expect(try parse("hello, world\n\"literal quotes\"", .wordList),
               words: ["hello, world", "\"literal quotes\""],
               report: .init(added: 2, duplicates: 0, invalid: 0, overLimit: 0), "text punctuation is literal")
        for format in [Import.Format.json, .csv, .wordList] {
            expect(try parse(" \r\n \n", format), words: [],
                   report: .init(added: 0, duplicates: 0, invalid: 0, overLimit: 0), "blank input")
        }
    }

    private static func jsonShapesAndInvalidItems() throws {
        let document = try parse(
            #"{"words":["Kubernetes",{"word":"PostgreSQL","source":"local"},null,17,true,{}, {"word":false},"",["nested"],"kubernetes"]}"#,
            .json
        )
        expect(document, words: ["Kubernetes", "PostgreSQL"],
               report: .init(added: 2, duplicates: 1, invalid: 7, overLimit: 0), "mixed JSON records")
        expect(try parse(#"[{"word":"C++"},{"word":"SwiftUI"}]"#, .json), words: ["C++", "SwiftUI"],
               report: .init(added: 2, duplicates: 0, invalid: 0, overLimit: 0), "JSON word objects")
        for text in [#"{"word":"term"}"#, #"{"words":"term"}"#, "true", "42", #""term""#] {
            expectFailure(text, .json, .unsupportedJSONShape, "unsupported JSON root")
        }
    }

    private static func encodingAndSizeBounds() throws {
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("café\n東京\n👩🏽‍💻".utf8)
        expect(try Import.parse(bom, format: .wordList), words: ["café", "東京", "👩🏽‍💻"],
               report: .init(added: 3, duplicates: 0, invalid: 0, overLimit: 0), "UTF-8 BOM and Unicode")
        let boundary = Data(repeating: 0x20, count: 1_048_576)
        expect(try Import.parse(boundary, format: .wordList), words: [],
               report: .init(added: 0, duplicates: 0, invalid: 0, overLimit: 0), "exact byte boundary")
        do {
            _ = try Import.parse(boundary + Data([0x20]), format: .wordList)
            require(false, "size limit plus one must fail")
        } catch let error as Import.Failure {
            require(error == .tooLarge, "size overflow is typed")
        }
        for bytes: [UInt8] in [[0xFF], [0xC3, 0x28], [0xEF, 0xBB], [0xFF, 0xFE, 0x41, 0x00]] {
            do {
                _ = try Import.parse(Data(bytes), format: .wordList)
                require(false, "invalid UTF-8 must fail without replacement characters")
            } catch let error as Import.Failure {
                require(error == .unreadableEncoding, "encoding failure is typed")
            }
        }
    }

    private static func atomicSyntaxFailures() throws {
        for text in [#"["valid", {"word":"late"}"#, #"["valid",]"#, "valid\nsecond"] {
            expectFailure(text, .json, .malformedJSON, "malformed JSON never falls back to text")
        }
        expectFailure("valid\n\"unclosed", .csv, .malformedCSV(record: 2), "late unclosed quote")
        expectFailure("valid\nstray\"quote", .csv, .malformedCSV(record: 2), "late stray quote")
        expectFailure("valid\n\"closed\"suffix", .csv, .malformedCSV(record: 2), "content after closing quote")
        expectFailure("valid\n\"closed\" \"again\"", .csv, .malformedCSV(record: 2), "separated quote is not an escape")
    }

    private static func csvQuotingAndHeaders() throws {
        expect(try parse("  \"hello, world\",\"say \"\"hi\"\"\"\rNext\nLast\r\n", .csv),
               words: ["hello, world", "say \"hi\"", "Next", "Last"],
               report: .init(added: 4, duplicates: 0, invalid: 0, overLimit: 0), "CSV quoted punctuation and line endings")
        expect(try parse("\nsource, WoRd ,notes\nlocal,PostgreSQL,metadata\nweb,Kubernetes,ignored\n", .csv),
               words: ["PostgreSQL", "Kubernetes"],
               report: .init(added: 2, duplicates: 0, invalid: 0, overLimit: 0), "CSV metadata header")
        for header in ["word", "WORDS", " Term "] {
            expect(try parse("\(header)\nactual\n", .csv), words: ["actual"],
                   report: .init(added: 1, duplicates: 0, invalid: 0, overLimit: 0), "first literal word is a header")
        }
        expect(try parse("word", .csv), words: [],
               report: .init(added: 0, duplicates: 0, invalid: 0, overLimit: 0), "header alone adds nothing")
        expectFailure("word,term\na,b", .csv, .ambiguousCSVHeader, "multiple recognized columns")
        expectFailure("word,WORD\na,b", .csv, .ambiguousCSVHeader, "duplicate recognized columns")
        expectFailure("word,metadata\nvalid,yes\nragged", .csv, .malformedCSV(record: 3), "ragged header row rejects all")
        expect(try parse("\"line\nbreak\",valid\n\"other\nphrase\"", .csv), words: ["valid"],
               report: .init(added: 1, duplicates: 0, invalid: 2, overLimit: 0), "quoted newlines are invalid terms")
    }

    private static func csvEmptyCellsAndLines() throws {
        expect(try parse("\n  \r\n\"\"\n,\r\nvalid,,other\n", .csv), words: ["valid", "other"],
               report: .init(added: 2, duplicates: 0, invalid: 4, overLimit: 0), "explicit empty CSV cells count")
        expect(try parse("word,metadata\n,ignored\n\nvalid,\n", .csv), words: ["valid"],
               report: .init(added: 1, duplicates: 0, invalid: 1, overLimit: 0), "empty metadata is ignored")
    }

    private static func validation() throws {
        let limitWord = String(repeating: "é", count: 120)
        let longWord = String(repeating: "é", count: 121)
        let values = [limitWord, longWord, "tab\there", "nul\0here", "new\nline", "", "  New  York  ", "\t\nOuter whitespace\r\n\t"]
        let data = try JSONEncoder().encode(values)
        expect(try Import.parse(data, format: .json), words: [limitWord, "New  York", "Outer whitespace"],
               report: .init(added: 3, duplicates: 0, invalid: 5, overLimit: 0), "term length, trimming, and embedded controls")
        expect(try parse("valid\nline\u{2028}separator\nvertical\u{B}tab\nparagraph\u{2029}separator", .wordList),
               words: ["valid"], report: .init(added: 1, duplicates: 0, invalid: 3, overLimit: 0),
               "only CR and LF separate word-list records")
    }

    private static func duplicateMatching() throws {
        let existing = [
            DictationVocabularyEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                     spoken: "post grez", replacement: "PostgreSQL"),
            DictationVocabularyEntry(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                     spoken: "Café", replacement: "Café")
        ]
        expect(try parse("POST GREZ\npostgresql\nCafe\u{301}\nCAFE\nSwiftUI\nswiftui\n", .wordList),
               existing: existing, words: ["CAFE", "SwiftUI"],
               report: .init(added: 2, duplicates: 4, invalid: 0, overLimit: 0), "alias, canonical, case, NFC, and accents")
        expect(try parse("Straße\nSTRASSE\n", .wordList), words: ["Straße"],
               report: .init(added: 1, duplicates: 1, invalid: 0, overLimit: 0), "POSIX case folding")
    }

    private static func capacityAndIdempotence() throws {
        let existing = (0..<249).map { DictationVocabularyEntry(spoken: "term\($0)", replacement: "term\($0)") }
        let document = try parse("term0\nnew\nNEW\noverflow\nOVERFLOW\nlast\n", .wordList)
        expect(document, existing: existing, words: ["new"],
               report: .init(added: 1, duplicates: 3, invalid: 0, overLimit: 2), "capacity follows deduplication")
        let full = document.merging(into: existing).entries
        expect(try parse("term0\nfresh\nFRESH", .wordList), existing: full, words: [],
               report: .init(added: 0, duplicates: 2, invalid: 0, overLimit: 1), "full capacity reserves overflow keys")
        let small = try parse("one\nTWO\none", .wordList)
        let first = small.merging(into: [])
        expect(small, existing: first.entries, words: [],
               report: .init(added: 0, duplicates: 3, invalid: 0, overLimit: 0), "repeat import is a no-op")
    }

    private static func mergeUsesLatestVocabulary() throws {
        let document = try parse("new\nanother", .wordList)
        let latest = [DictationVocabularyEntry(spoken: "new alias", replacement: "new")]
        expect(document, existing: latest, words: ["another"],
               report: .init(added: 1, duplicates: 1, invalid: 0, overLimit: 0), "merge uses vocabulary supplied after parsing")
    }
}
