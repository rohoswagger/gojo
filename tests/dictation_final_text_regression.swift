import Foundation

@main
struct DictationFinalTextRegression {
    static func equal(_ actual: String, _ expected: String, _ message: String) {
        guard actual == expected else {
            fatalError("\(message)\nexpected: \(String(reflecting: expected))\nactual:   \(String(reflecting: actual))")
        }
    }

    static func final(
        _ transcript: String,
        options: DictationTextOptions = DictationTextOptions(),
        polished: String? = nil
    ) -> String {
        DictationFinalTextPolicy.finalize(
            DictationFinalTextPolicy.prepare(transcript, options: options),
            polishedTranscript: polished
        )
    }

    static func main() {
        let punctuation = DictationTextOptions(commands: .punctuation)
        let code = DictationTextOptions(intent: .code, commands: .punctuationAndCode, cleanup: .s1Mini(.formal))
        equal(
            final("Hello Maya comma new paragraph the build is ready period", options: punctuation),
            "Hello Maya,\n\nthe build is ready.",
            "punctuation and paragraph commands render after recognition"
        )
        equal(final("hello new paragraph", options: punctuation), "hello\n\n", "an explicit trailing paragraph command survives finalization")
        equal(final("new line", options: punctuation), "\n", "a command-only newline remains insertable text")
        equal(final("new paragraph hello", options: punctuation), "\n\nhello", "an explicit leading paragraph command survives finalization")
        equal(
            final("First paragraph.\n\nSecond paragraph.\nThird line."),
            "First paragraph.\n\nSecond paragraph.\nThird line.",
            "existing paragraphs and line breaks survive the common final pipeline"
        )
        equal(final("One\r\n\r\nTwo\rThree"), "One\n\nTwo\nThree", "line endings normalize without collapsing paragraphs")
        equal(
            final("function open parentheses value slash path dash name comma count close parentheses", options: code),
            "function(value/path-name, count)",
            "code delimiters attach to their contents and paths have no inserted spaces"
        )
        equal(final("call open parenthesis close parenthesis", options: code), "call()", "empty parentheses have no padding")
        equal(
            final("value equals left bracket first comma second right bracket semicolon", options: code),
            "value = [first, second];",
            "operators, delimiters and punctuation have deterministic spacing"
        )
        equal(
            final("path back slash to slash file underscore name dot swift", options: code),
            "path\\to/file_name.swift",
            "longest code phrases take precedence over contained commands"
        )
        equal(
            final("say literal new paragraph then literal CoMmA period", options: punctuation),
            "say new paragraph then CoMmA.",
            "literal escapes preserve the complete command phrase and original case"
        )
        equal(
            final("literal open parentheses and literal slash", options: code),
            "open parentheses and slash",
            "literal escapes protect code commands too"
        )
        equal(
            final("literal comma new paragraph"),
            "literal comma new paragraph",
            "commands and escapes are opt in"
        )
        equal(
            final("open parentheses comma close parentheses", options: punctuation),
            "open parentheses, close parentheses",
            "punctuation mode leaves code phrases as recognized words"
        )
        equal(
            final("um I like actually do not want 42 or build_id removed"),
            "um I like actually do not want 42 or build_id removed",
            "the deterministic policy does not delete filler-like words or content"
        )
        equal(
            final("commaValue comma_value comma2 你好comma commá comma hello", options: punctuation),
            "commaValue comma_value comma2 你好comma commá, hello",
            "Unicode word boundaries protect identifiers, CJK words and combining marks"
        )
        equal(
            final("你好 comma 世界 period", options: punctuation),
            "你好, 世界.",
            "standalone selected-language commands work alongside CJK content"
        )
        let portuguese = DictationTextOptions(commands: .punctuationAndCode, commandLanguage: .portuguese)
        equal(
            final("Tenho um plano vírgula não dois novo parágrafo Vamos testar ponto", options: portuguese),
            "Tenho um plano, não dois\n\nVamos testar.",
            "Portuguese punctuation preserves um, negation and paragraphs"
        )
        equal(
            final("função abrir parênteses x barra y hífen z fechar parênteses", options: portuguese),
            "função(x/y-z)",
            "Portuguese code commands use the same spacing rules"
        )
        equal(
            final("literal ponto e vírgula depois ponto de interrogação", options: portuguese),
            "ponto e vírgula depois?",
            "Portuguese longest phrases and literal escape remain distinct"
        )
        let spanish = DictationTextOptions(commands: .punctuationAndCode, commandLanguage: .spanish)
        equal(
            final("abrir interrogación Hola coma Maya cerrar interrogación nuevo párrafo lista punto y coma listo punto", options: spanish),
            "¿Hola, Maya?\n\nlista; listo.",
            "Spanish punctuation uses longest matches and opening-mark spacing"
        )
        equal(
            final("Hola comma mundo", options: spanish),
            "Hola comma mundo",
            "only the selected command language is active"
        )
        let literal = DictationTextOptions(intent: .literal, commands: .punctuationAndCode, cleanup: .s1Mini(.formal))
        equal(
            final("um comma literal period\n\nkeep build_id 42", options: literal, polished: "Changed."),
            "um comma literal period\n\nkeep build_id 42",
            "Literal disables both commands and semantic cleanup"
        )
        equal(
            final("call open parenthesis build_id comma 42 close parenthesis", options: code, polished: "Changed."),
            "call(build_id, 42)",
            "Code skips semantic cleanup while preserving explicit commands"
        )
        equal(final("press enter submit run shell command", options: code), "press enter submit run shell command", "dictation never generates submit or shell actions")

        let vocabulary = [
            DictationVocabularyEntry(spoken: "visual studio", replacement: "Visual Studio"),
            DictationVocabularyEntry(spoken: "visual studio code", replacement: "VS Code"),
            DictationVocabularyEntry(spoken: "foo", replacement: "bar"),
            DictationVocabularyEntry(spoken: "bar", replacement: "baz"),
            DictationVocabularyEntry(spoken: "g p t", replacement: "GPT"),
        ]
        let vocabularyOptions = DictationTextOptions(vocabulary: vocabulary)
        equal(
            final("visual studio code foo bar g p t", options: vocabularyOptions),
            "VS Code bar baz GPT",
            "longest vocabulary aliases apply once without cascading"
        )
        equal(final("visual studio code foo bar g p t"), "visual studio code foo bar g p t", "empty frozen vocabulary opts out of alias corrections")
        let casual = DictationTextOptions(vocabulary: vocabulary, cleanup: .s1Mini(.casual))
        equal(
            final("g p t foo", options: casual, polished: "GPT Bar."),
            "GPT bar.",
            "cleanup restores canonical spelling after style conversion without applying aliases again"
        )
        equal(
            final("use buildID and build_id 42", options: casual, polished: "Use BUILDID and BUILD_ID 42."),
            "use buildID and build_id 42.",
            "casual cleanup preserves the original spelling of code identifiers"
        )
        equal(
            final("g p t g p t", options: casual, polished: "GPT."),
            "GPT GPT",
            "cleanup cannot delete repeated canonical vocabulary occurrences"
        )
        equal(
            final("g p t", options: casual, polished: "GPTish."),
            "GPT",
            "a canonical term must survive as a complete phrase"
        )
        let cleanup = DictationTextOptions(commands: .punctuation, cleanup: .s1Mini(.punctuated))
        let source = "Hello Maya comma new paragraph the build is ready period"
        equal(
            final(source, options: cleanup, polished: "Hello Maya comma new paragraph The build is ready period"),
            "Hello Maya,\n\nThe build is ready.",
            "safe cleanup can edit prose around preserved command phrases"
        )
        for changed in [
            "Hello Maya comma paragraph the build is ready period",
            "Hello Maya period new paragraph the build is ready comma",
            "Hello Maya comma comma new paragraph the build is ready period",
            "Hello Maya new paragraph the build is ready period",
            "Hello Maya comma new paragraph the build is ready period period",
            "<think>internal</think>",
            "",
        ] {
            equal(
                final(source, options: cleanup, polished: changed),
                "Hello Maya,\n\nthe build is ready.",
                "cleanup falls back when protected phrases change order, count or complete wording"
            )
        }
        equal(final(source, options: cleanup), "Hello Maya,\n\nthe build is ready.", "cleanup failure still renders commands from the corrected original")
        let escaped = "Say literal CoMmA then period"
        equal(final(escaped, options: cleanup, polished: "Say comma then period"), "Say CoMmA then.", "cleanup cannot consume the literal escape")
        equal(final(escaped, options: cleanup, polished: "Say literal comma then period"), "Say CoMmA then.", "accepted cleanup restores literal phrase case verbatim")
        equal(
            final("first\n\nsecond", options: cleanup, polished: "First second."),
            "first\n\nsecond",
            "cleanup cannot collapse an existing paragraph"
        )
        equal(
            final("first\n\nsecond", options: cleanup, polished: "First\n\nSecond."),
            "First\n\nSecond.",
            "safe cleanup preserves the actual paragraph run"
        )
        for changed in ["Ship build_id 42.", "Do not ship build_id 43.", "Do not ship build_name 42."] {
            equal(
                final("do not ship build_id 42", options: cleanup, polished: changed),
                "do not ship build_id 42",
                "cleanup cannot remove negation, change numbers or rename code identifiers"
            )
        }
        equal(
            final("hello comma world", options: cleanup, polished: "Hello comma world semicolon"),
            "Hello, world semicolon",
            "cleanup cannot create newly executable spoken commands"
        )
        var mutableVocabulary = [DictationVocabularyEntry(spoken: "maya", replacement: "Maya")]
        let frozen = DictationTextOptions(vocabulary: mutableVocabulary)
        mutableVocabulary[0].replacement = "Changed"
        equal(final("maya", options: frozen), "Maya", "session text options retain a value copy of vocabulary")
        print("PASS dictation final text policy")
    }
}
