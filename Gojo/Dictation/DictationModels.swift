import Foundation

enum DictationMicrophoneAuthorizationFailure: Error, Equatable, Sendable, LocalizedError {
    case denied
    case restricted
    case notDetermined
    case unknown(Int)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Allow Gojo to use the microphone in System Settings, then try again."
        case .restricted:
            return "Microphone access is restricted on this Mac. Check its privacy or device management settings."
        case .notDetermined:
            return "Microphone permission has not been decided. Allow access before starting dictation."
        case .unknown:
            return "Gojo could not determine microphone access. Reopen Gojo and try again."
        }
    }
}

enum DictationMicrophoneDiagnosticState: Equatable, Sendable {
    case idle
    case testing
    case passed
    case failed(String)
}

enum DictationTargetResolution<Target: Sendable>: Sendable {
    case captured(Target)
    case copyOnly(DictationCopyOnlyReason)

    var capturedTarget: Target? {
        guard case .captured(let target) = self else { return nil }
        return target
    }

    var copyOnlyReason: DictationCopyOnlyReason? {
        guard case .copyOnly(let reason) = self else { return nil }
        return reason
    }
}

enum DictationCopyOnlyReason: CaseIterable, Equatable, Sendable {
    case noFocusedTextField
    case nonEditableTarget

    var message: String {
        switch self {
        case .noFocusedTextField:
            return "No text field was selected. Your text is saved for copying."
        case .nonEditableTarget:
            return "The selected control cannot accept text. Your text is saved for copying."
        }
    }
}

enum DictationInsertionOutcome: Equatable, Sendable {
    case verified
    case unverified

    var recoveryMessage: String? {
        switch self {
        case .verified: return nil
        case .unverified: return "The app did not confirm receiving this text. It is saved for copying."
        }
    }
}

enum DictationCaptureMode: Sendable {
    case singleUtterance
    case continuous
}

enum DictationContinuousCaptureError: LocalizedError {
    case unsupported
    case bufferOverflow

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This audio capture does not support continuous dictation."
        case .bufferOverflow: return "Dictation could not keep up. Stop and start again."
        }
    }
}

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

    static func load() -> [DictationVocabularyEntry] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([DictationVocabularyEntry].self, from: data) else {
            return []
        }
        return sanitized(entries)
    }

    static func recognitionTerms(_ entries: [DictationVocabularyEntry]) -> [String] {
        var seen = Set<String>()
        return sanitized(entries).compactMap { entry in
            let key = entry.replacement.folding(
                options: [.caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return seen.insert(key).inserted ? entry.replacement : nil
        }
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

enum DictationCorrectionLearningPolicy {
    static let defaultsKey = "gojo.dictation.learnCorrections"
    static let maximumTextLength = 4_000
    static let maximumSegmentTokens = 3
    static let maximumPhraseLength = 60

    static func candidate(original: String, edited: String) -> DictationVocabularyEntry? {
        let originalText = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let editedText = edited.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !originalText.isEmpty,
              !editedText.isEmpty,
              originalText.count <= maximumTextLength,
              editedText.count <= maximumTextLength,
              !originalText.contains(where: \.isNewline),
              !editedText.contains(where: \.isNewline) else {
            return nil
        }

        let originalTokens = tokens(originalText)
        let editedTokens = tokens(editedText)
        let shared = min(originalTokens.count, editedTokens.count)
        var prefix = 0
        while prefix < shared, originalTokens[prefix] == editedTokens[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shared - prefix,
              originalTokens[originalTokens.count - 1 - suffix]
                  == editedTokens[editedTokens.count - 1 - suffix] {
            suffix += 1
        }

        let originalSegment = originalTokens[prefix..<(originalTokens.count - suffix)]
        let editedSegment = editedTokens[prefix..<(editedTokens.count - suffix)]
        guard !originalSegment.isEmpty,
              !editedSegment.isEmpty,
              originalSegment.count <= maximumSegmentTokens,
              editedSegment.count <= maximumSegmentTokens,
              let spoken = trimmedPhrase(originalSegment),
              let replacement = trimmedPhrase(editedSegment),
              spoken.count <= maximumPhraseLength,
              replacement.count <= maximumPhraseLength,
              spoken.contains(where: \.isLetter),
              replacement.contains(where: \.isLetter) else {
            return nil
        }

        guard wordsAndSpaces(spoken) != wordsAndSpaces(replacement) else { return nil }

        if isFirstLetterCaseChange(from: spoken, to: replacement),
           isSentenceStart(afterTokens: originalTokens.prefix(prefix)) {
            return nil
        }

        let spokenKey = foldedAlphanumerics(spoken)
        let replacementKey = foldedAlphanumerics(replacement)
        let longest = max(spokenKey.count, replacementKey.count)
        guard longest <= maximumPhraseLength,
              editDistance(spokenKey, replacementKey) <= max(2, longest / 3) else {
            return nil
        }
        if originalSegment.count != editedSegment.count,
           spokenKey != replacementKey,
           !spokenKey.isEmpty,
           !replacementKey.isEmpty {
            let (longer, shorter) = spokenKey.count > replacementKey.count
                ? (spokenKey, replacementKey)
                : (replacementKey, spokenKey)
            if longer.starts(with: shorter) || longer.reversed().starts(with: shorter.reversed()) {
                return nil
            }
        }
        return DictationVocabularyEntry(spoken: spoken, replacement: replacement)
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func trimmedPhrase(_ tokens: ArraySlice<String>) -> String? {
        let characters = Array(tokens.joined(separator: " "))
        var start = 0
        var end = characters.count
        while start < end, isEdgePunctuation(characters[start]) { start += 1 }
        while end > start, isEdgePunctuation(characters[end - 1]) { end -= 1 }
        return start < end ? String(characters[start..<end]) : nil
    }

    private static let meaningfulEdgeCharacters = Set<Unicode.Scalar>(["_", "@", "#"])

    private static func isEdgePunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) && !meaningfulEdgeCharacters.contains($0)
        }
    }

    private static func wordsAndSpaces(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    private static func foldedAlphanumerics(_ text: String) -> [Character] {
        Array(text.filter { $0.isLetter || $0.isNumber }.lowercased())
    }

    private static func isFirstLetterCaseChange(from spoken: String, to replacement: String) -> Bool {
        let before = Array(spoken)
        let after = Array(replacement)
        guard before.count == after.count,
              let first = before.first,
              let newFirst = after.first,
              first != newFirst,
              String(first).lowercased() == String(newFirst).lowercased() else {
            return false
        }
        return before.dropFirst().elementsEqual(after.dropFirst())
    }

    private static func isSentenceStart(afterTokens preceding: ArraySlice<String>) -> Bool {
        guard let last = preceding.last else { return true }
        let closers = Set<Character>(["\"", "'", ")", "]", "}", "\u{201D}", "\u{2019}", "\u{00BB}"])
        guard let terminal = last.last(where: { !closers.contains($0) }) else { return false }
        return ".!?\u{2026}".contains(terminal)
    }

    private static func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }
        var previous = Array(0...rhs.count)
        for (row, left) in lhs.enumerated() {
            var current = [row + 1]
            for (column, right) in rhs.enumerated() {
                current.append(min(
                    previous[column + 1] + 1,
                    current[column] + 1,
                    previous[column] + (left == right ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[rhs.count]
    }
}

struct DictationCorrectionLearner: Sendable {
    static let maximumCandidates = 250

    private struct Candidate: Sendable {
        let aliasKey: String
        let replacement: String
    }

    private var candidates: [Candidate] = []

    mutating func observe(_ entry: DictationVocabularyEntry) -> DictationVocabularyEntry? {
        guard let normalized = entry.normalized else { return nil }
        let aliasKey = Self.collapsed(normalized.spoken).folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let replacement = Self.collapsed(normalized.replacement)

        guard let index = candidates.firstIndex(where: { $0.aliasKey == aliasKey }) else {
            append(Candidate(aliasKey: aliasKey, replacement: replacement))
            return nil
        }
        if candidates[index].replacement == replacement {
            candidates.remove(at: index)
            return normalized
        }
        candidates.remove(at: index)
        append(Candidate(aliasKey: aliasKey, replacement: replacement))
        return nil
    }

    mutating func reset() {
        candidates.removeAll()
    }

    private mutating func append(_ candidate: Candidate) {
        candidates.append(candidate)
        if candidates.count > Self.maximumCandidates {
            candidates.removeFirst(candidates.count - Self.maximumCandidates)
        }
    }

    private static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
        vocabulary: [DictationVocabularyEntry],
        style: DictationWritingStyle = .punctuated
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
        return DictationVocabularyPolicy.apply(
            canonicalTerms,
            to: style.applyOutputConventions(to: polishedTranscript)
        )
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
    case accessibilityPermissionDenied
    case secureTextTarget
    case targetUnavailable(String)
    case captureFailed(String)
    case transcriptionFailed(String)
    case transcriptionReturnedNoText
    case insertionFailed(String)
}

enum DictationTargetPolicy: Sendable {
    case fixed
    case followFocus
}

enum DictationState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
    case pausing
    case paused
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
        case .pausing:
            return "Finishing phrase"
        case .paused:
            return "Paused"
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
    case startVoiceMode
    case lockVoiceMode
    case pauseVoiceMode
    case resumeVoiceMode
    case finishVoiceMode
    case clearRecoveryText
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

    func send(_ event: DictationShortcutEvent, completion: (@Sendable () async -> Void)? = nil) {
        lock.withLock {
            let predecessor = tail
            let handler = self.handler
            let next = Task {
                await predecessor?.value
                await handler(event)
                await completion?()
            }
            tail = next
        }
    }

    func drain() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}
