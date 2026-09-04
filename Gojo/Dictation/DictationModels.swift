import Foundation

struct DictationAudio: Equatable, Sendable {
    static let transcriptionSampleRate = 16_000.0

    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double = transcriptionSampleRate) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

struct DictationAudioPolicy: Equatable, Sendable {
    let minimumDuration: TimeInterval

    init(minimumDuration: TimeInterval = 0.12) {
        self.minimumDuration = max(0, minimumDuration)
    }

    func shouldTranscribe(_ audio: DictationAudio) -> Bool {
        !audio.samples.isEmpty
            && audio.sampleRate > 0
            && audio.duration >= minimumDuration
    }
}

enum DictationWritingStyle: String, CaseIterable, Identifiable, Sendable {
    case casual
    case punctuated
    case formal

    static let defaultsKey = "gojo.dictation.writingStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .casual: return "Casual"
        case .punctuated: return "Conversational"
        case .formal: return "Formal"
        }
    }

    var prompt: String {
        switch self {
        case .casual:
            return "Use all lowercase. Keep the wording conversational and natural, like a text message. Preserve contractions and use only the punctuation needed for clarity."
        case .punctuated:
            return "Keep the wording conversational and natural, with standard capitalization and light punctuation as needed for clarity."
        case .formal:
            return "Use polished, professional wording and complete punctuation without changing the meaning or adding information."
        }
    }

    var s1MiniStyle: String {
        switch self {
        case .casual: return "semi-casual"
        case .punctuated: return "semi-casual"
        case .formal: return "formal"
        }
    }

    func applyOutputConventions(to transcript: String) -> String {
        switch self {
        case .casual:
            return transcript.lowercased()
        case .punctuated, .formal:
            return transcript
        }
    }
}

enum DictationTranscriptPolicy {
    static func normalize(_ transcript: String) -> String {
        let collapsed = transcript
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return collapsed
            .replacingOccurrences(of: "Go-jo", with: "Gojo", options: .caseInsensitive)
            .replacingOccurrences(of: "Go jo", with: "Gojo", options: .caseInsensitive)
    }
}

struct DictationVocabularyEntry: Codable, Equatable, Identifiable, Sendable {
    static let maximumEntries = 250
    static let maximumSpokenLength = 120
    static let maximumReplacementLength = 240

    let id: UUID
    var spoken: String
    var replacement: String

    init(id: UUID = UUID(), spoken: String, replacement: String) {
        self.id = id
        self.spoken = spoken
        self.replacement = replacement
    }

    var normalized: DictationVocabularyEntry? {
        let cleanSpoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSpoken.isEmpty,
              !cleanReplacement.isEmpty,
              cleanSpoken.count <= Self.maximumSpokenLength,
              cleanReplacement.count <= Self.maximumReplacementLength else {
            return nil
        }
        return DictationVocabularyEntry(
            id: id,
            spoken: cleanSpoken,
            replacement: cleanReplacement
        )
    }
}

enum DictationVocabularyPolicy {
    static let defaultsKey = "gojo.dictation.vocabulary"

    static func sanitized(_ entries: [DictationVocabularyEntry]) -> [DictationVocabularyEntry] {
        var seen = Set<String>()
        var result: [DictationVocabularyEntry] = []
        for entry in entries.prefix(DictationVocabularyEntry.maximumEntries) {
            guard let normalized = entry.normalized else { continue }
            let key = normalized.spoken.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    static func apply(_ entries: [DictationVocabularyEntry], to transcript: String) -> String {
        let candidates = sanitized(entries).enumerated().sorted {
            if $0.element.spoken.utf16.count == $1.element.spoken.utf16.count {
                return $0.offset < $1.offset
            }
            return $0.element.spoken.utf16.count > $1.element.spoken.utf16.count
        }
        guard !candidates.isEmpty, !transcript.isEmpty else { return transcript }

        struct Replacement {
            let range: NSRange
            let value: String
        }

        let fullRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        var accepted: [Replacement] = []
        for (_, entry) in candidates {
            let escaped = NSRegularExpression.escapedPattern(for: entry.spoken)
            let startsWithWord = entry.spoken.first.map(isVocabularyWordCharacter) ?? false
            let endsWithWord = entry.spoken.last.map(isVocabularyWordCharacter) ?? false
            let pattern = (startsWithWord ? "(?<![\\p{L}\\p{N}_])" : "")
                + escaped
                + (endsWithWord ? "(?![\\p{L}\\p{N}_])" : "")
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .useUnicodeWordBoundaries]
            ) else { continue }

            for match in expression.matches(in: transcript, range: fullRange) {
                guard !accepted.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) else {
                    continue
                }
                accepted.append(Replacement(range: match.range, value: entry.replacement))
            }
        }

        let output = NSMutableString(string: transcript)
        for replacement in accepted.sorted(by: { $0.range.location > $1.range.location }) {
            output.replaceCharacters(in: replacement.range, with: replacement.value)
        }
        return output as String
    }

    private static func isVocabularyWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_"
        }
    }
}

enum S1MiniModel {
    static let displayName = "S1-mini by Superwhisper"
    static let fileName = "s1-mini-q4_k_m.gguf"
    static let downloadSize = 484_219_808
    static let downloadSizeLabel = "462 MiB"
    static let sha256 = "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634"
    static let revision = "34add00a48a2e5d24e5a4ee5405a99620a3a240c"
    static let downloadURL = URL(string:
        "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/\(revision)/\(fileName)?download=true"
    )!

    static let systemPrompt = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    static func prompt(transcript: String, style: DictationWritingStyle) -> String {
        "<|im_start|>system\n"
            + systemPrompt
            + "<|im_end|>\n<|im_start|>user\n"
            + "[Styling: \(style.s1MiniStyle)] [Structure: prose] [Context: general]\n"
            + transcript
            + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }
}

enum S1MiniOutputPolicy {
    static func isSafe(
        rawTranscript: String,
        polishedTranscript: String,
        protectedTerms: [String]
    ) -> Bool {
        let output = polishedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty,
              output.utf8.count <= rawTranscript.utf8.count * 2 + 128 else {
            return false
        }
        let forbiddenMarkers = ["<|im_", "<think>", "</think>"]
        guard forbiddenMarkers.allSatisfy({ !output.localizedCaseInsensitiveContains($0) }) else {
            return false
        }
        return protectedTerms.allSatisfy { term in
            output.range(of: term, options: [.caseInsensitive]) != nil
        }
    }
}

enum S1MiniVocabularyPipeline {
    static func prepare(
        transcript: String,
        vocabulary: [DictationVocabularyEntry]
    ) -> String {
        DictationVocabularyPolicy.apply(vocabulary, to: transcript)
    }

    static func finalize(
        correctedRawTranscript: String,
        polishedTranscript: String,
        vocabulary: [DictationVocabularyEntry]
    ) -> String {
        let protectedTerms = vocabulary.compactMap { entry in
            correctedRawTranscript.range(of: entry.replacement, options: [.caseInsensitive]) == nil
                ? nil
                : entry.replacement
        }
        guard S1MiniOutputPolicy.isSafe(
            rawTranscript: correctedRawTranscript,
            polishedTranscript: polishedTranscript,
            protectedTerms: protectedTerms
        ) else {
            return correctedRawTranscript
        }

        // The aliases were already applied before inference. Only re-case exact
        // canonical terms here; applying aliases a second time could cascade
        // `foo -> bar` and `bar -> baz` into an unintended `foo -> baz`.
        let canonicalTerms = vocabulary.map {
            DictationVocabularyEntry(spoken: $0.replacement, replacement: $0.replacement)
        }
        return DictationVocabularyPolicy.apply(canonicalTerms, to: polishedTranscript)
    }
}

actor DictationWarmupSequencer {
    typealias Generation = UInt
    typealias Prepare = @Sendable () async -> Void
    typealias SpeechReady = @Sendable (Generation) async -> Void
    typealias ShouldRunCleanup = @Sendable (Generation) async -> Bool

    private var speechTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?

    func startSpeechThenCleanup(
        generation: Generation,
        prepareSpeech: @escaping Prepare,
        speechReady: @escaping SpeechReady,
        shouldRunCleanup: @escaping ShouldRunCleanup,
        prepareCleanup: @escaping Prepare
    ) {
        let previousSpeechTask = speechTask
        let previousCleanupTask = cleanupTask
        speechTask = Task {
            await previousSpeechTask?.value
            await previousCleanupTask?.value
            guard !Task.isCancelled else { return }

            await prepareSpeech()
            await speechReady(generation)
            startCleanup(
                generation: generation,
                after: nil,
                shouldRunCleanup: shouldRunCleanup,
                prepareCleanup: prepareCleanup
            )
        }
    }

    func startCleanupAfterCurrentSpeech(
        generation: Generation,
        shouldRunCleanup: @escaping ShouldRunCleanup,
        prepareCleanup: @escaping Prepare
    ) {
        startCleanup(
            generation: generation,
            after: speechTask,
            shouldRunCleanup: shouldRunCleanup,
            prepareCleanup: prepareCleanup
        )
    }

    private func startCleanup(
        generation: Generation,
        after speechTask: Task<Void, Never>?,
        shouldRunCleanup: @escaping ShouldRunCleanup,
        prepareCleanup: @escaping Prepare
    ) {
        guard cleanupTask == nil else { return }
        cleanupTask = Task {
            await speechTask?.value
            guard !Task.isCancelled, await shouldRunCleanup(generation) else {
                finishCleanup()
                return
            }

            await prepareCleanup()
            finishCleanup()
        }
    }

    private func finishCleanup() {
        cleanupTask = nil
    }
}

enum DictationModelRequest: Sendable {
    case settingsDownload
    case transcription

    var allowsDownload: Bool {
        self == .settingsDownload
    }
}

enum DictationModelStorage {
    private static let downloadMetadataPath = [".cache", "huggingface", "download"]

    static func hubRepositoryRoot(_ repository: String) -> URL? {
        let components = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let documents = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first else {
            return nil
        }
        return components.reduce(
            documents
                .appendingPathComponent("huggingface", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
        ) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    static func storedPath(_ storedPath: String?, matches expectedURL: URL) -> Bool {
        guard let storedPath else { return false }
        let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true).standardizedFileURL
        return storedURL.path == expectedURL.standardizedFileURL.path
    }

    static func removeAllowlistedItems(
        from repositoryRoot: URL,
        topLevelItems: [String]
    ) throws {
        let standardizedRoot = try validatedRemovalRoot(repositoryRoot)
        try validateTopLevelItems(topLevelItems)
        // Validate the entire metadata path before deleting the model itself.
        // This keeps a malicious intermediate symlink from turning the second
        // deletion into an escape after the first deletion has already run.
        let metadataRoot = try existingDirectory(
            beneath: standardizedRoot,
            components: downloadMetadataPath
        )
        for item in topLevelItems {
            try removeItemIfPresent(standardizedRoot.appendingPathComponent(item))
            if let metadataRoot {
                try removeItemIfPresent(metadataRoot.appendingPathComponent(item))
            }
        }
    }

    static func removeAllowlistedTopLevelItems(
        from root: URL,
        topLevelItems: [String]
    ) throws {
        let standardizedRoot = try validatedRemovalRoot(root)
        try validateTopLevelItems(topLevelItems)
        for item in topLevelItems {
            try removeItemIfPresent(standardizedRoot.appendingPathComponent(item))
        }
    }

    private static func validatedRemovalRoot(_ root: URL) throws -> URL {
        let standardizedRoot = root.standardizedFileURL
        guard standardizedRoot.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw DictationModelStorageError.unsafeRemovalTarget
        }
        return standardizedRoot
    }

    private static func validateTopLevelItems(_ items: [String]) throws {
        guard !items.isEmpty, items.allSatisfy(isSafeTopLevelName) else {
            throw DictationModelStorageError.unsafeRemovalTarget
        }
    }

    private static func existingDirectory(
        beneath root: URL,
        components: [String]
    ) throws -> URL? {
        let fileManager = FileManager.default
        var current = root
        for component in components {
            let next = current.appendingPathComponent(component, isDirectory: true).standardizedFileURL
            guard next.path.hasPrefix(root.path + "/"),
                  (try? fileManager.destinationOfSymbolicLink(atPath: next.path)) == nil else {
                throw DictationModelStorageError.unsafeRemovalTarget
            }

            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: next.path, isDirectory: &isDirectory) else {
                return nil
            }
            guard isDirectory.boolValue,
                  next.path == next.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw DictationModelStorageError.unsafeRemovalTarget
            }
            current = next
        }
        return current
    }

    private static func isSafeTopLevelName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains(":")
    }

    private static func removeItemIfPresent(_ url: URL) throws {
        let fileManager = FileManager.default
        let isSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
        if isSymlink || fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

enum DictationModelStorageError: Error {
    case unsafeRemovalTarget
}

enum DictationEngineID: String, Sendable {
    case whisperKit
    case fluidAudio
}

enum DictationModelID: String, CaseIterable, Identifiable, Sendable {
    case whisperSmallEnglish = "whisperkit:small.en_217MB"
    case whisperLargeV3 = "whisperkit:large-v3-v20240930_626MB"
    case parakeetUnifiedEnglish = "fluidaudio:parakeet-unified-en-0.6b"
    case parakeetV3Multilingual = "fluidaudio:parakeet-tdt-0.6b-v3"

    var id: String { rawValue }

    var engine: DictationEngineID {
        switch self {
        case .whisperSmallEnglish, .whisperLargeV3:
            return .whisperKit
        case .parakeetUnifiedEnglish, .parakeetV3Multilingual:
            return .fluidAudio
        }
    }

    static func resolveSelection(_ rawValue: String?) -> DictationModelID {
        if let rawValue, let current = DictationModelID(rawValue: rawValue) {
            return current
        }
        switch rawValue {
        case WhisperDictationModel.smallEnglish.rawValue:
            return .whisperSmallEnglish
        case WhisperDictationModel.largeV3.rawValue:
            return .whisperLargeV3
        default:
            return .whisperSmallEnglish
        }
    }

    var whisperModel: WhisperDictationModel? {
        switch self {
        case .whisperSmallEnglish: return .smallEnglish
        case .whisperLargeV3: return .largeV3
        case .parakeetUnifiedEnglish, .parakeetV3Multilingual: return nil
        }
    }
}

enum DictationModelOperation: Equatable, Sendable {
    case installing(DictationModelID)
    case selecting(DictationModelID)
    case removing(DictationModelID)

    var model: DictationModelID {
        switch self {
        case .installing(let model), .selecting(let model), .removing(let model):
            return model
        }
    }
}

struct DictationModelDescriptor: Identifiable, Sendable {
    let id: DictationModelID
    let displayName: String
    let detail: String
    let downloadSizeLabel: String
    let isRecommended: Bool

    var engine: DictationEngineID { id.engine }
    var engineLabel: String {
        switch engine {
        case .whisperKit: return "WhisperKit"
        case .fluidAudio: return "FluidAudio"
        }
    }

    static let all: [DictationModelDescriptor] = [
        DictationModelDescriptor(
            id: .parakeetUnifiedEnglish,
            displayName: "Parakeet Unified",
            detail: "Strong English dictation with punctuation and capitalization",
            downloadSizeLabel: "614 MB",
            isRecommended: true
        ),
        DictationModelDescriptor(
            id: .parakeetV3Multilingual,
            displayName: "Parakeet v3",
            detail: "Fast dictation in 25 European languages",
            downloadSizeLabel: "483 MB",
            isRecommended: false
        ),
        DictationModelDescriptor(
            id: .whisperSmallEnglish,
            displayName: "Whisper Small",
            detail: "Fast and good for everyday dictation",
            downloadSizeLabel: "217 MB",
            isRecommended: false
        ),
        DictationModelDescriptor(
            id: .whisperLargeV3,
            displayName: "Whisper Large v3",
            detail: "Higher accuracy for English dictation",
            downloadSizeLabel: "626 MB",
            isRecommended: false
        ),
    ]

    static func descriptor(for id: DictationModelID) -> DictationModelDescriptor {
        all.first { $0.id == id }!
    }
}

enum WhisperDictationModel: String, CaseIterable, Identifiable, Sendable {
    case smallEnglish = "small.en_217MB"
    case largeV3 = "large-v3-v20240930_626MB"

    static let repository = "argmaxinc/whisperkit-coreml"
    static let revision = "97a5bf9bbc74c7d9c12c755d04dea59e672e3808"

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .smallEnglish: return "openai_whisper-small.en_217MB"
        case .largeV3: return "openai_whisper-large-v3-v20240930_626MB"
        }
    }

}

enum DictationFailure: Error, Equatable, Sendable {
    case modelNotInstalled
    case cloudConfigurationMissing(String)
    case microphonePermissionDenied
    case targetUnavailable(String)
    case captureFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case transcriptionReturnedNoText
    case insertionFailed(String)
}

enum DictationState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
    case transcribing
    case inserting
    case succeeded(String)
    case error(DictationFailure)
}

enum DictationSettingsStatus {
    static func title(for state: DictationState) -> String {
        switch state {
        case .idle, .succeeded:
            return "Ready"
        case .requestingPermission:
            return "Getting ready"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .inserting:
            return "Adding text"
        case .error:
            return "Could not dictate"
        }
    }
}

enum DictationShortcutEvent: Sendable {
    case keyDown
    case keyUp
    case cancel
}

/// Preserves callback order even when a global shortcut library delivers events
/// from different executors. Each event waits for the previous handler to finish.
final class DictationShortcutEventQueue: @unchecked Sendable {
    typealias Handler = @Sendable (DictationShortcutEvent) async -> Void

    private let lock = NSLock()
    private let handler: Handler
    private var tail: Task<Void, Never>?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ event: DictationShortcutEvent) {
        lock.withLock {
            let predecessor = tail
            let handler = self.handler
            let next = Task {
                await predecessor?.value
                await handler(event)
            }
            tail = next
        }
    }

    func drain() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}
