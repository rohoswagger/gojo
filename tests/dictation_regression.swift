import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

actor EventLog {
    private var values: [String] = []

    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
    func count(of value: String) -> Int { values.filter { $0 == value }.count }
}

actor FakeTargetProvider: DictationTargetCapturing {
    typealias Target = String

    let log: EventLog
    private(set) var captures = 0

    init(log: EventLog) { self.log = log }

    func captureTarget() async throws -> String {
        captures += 1
        await log.append("target")
        return "focused-field"
    }
}

actor FakeAudioCapture: DictationAudioCapturing {
    let log: EventLog
    var permission = true
    var audio = DictationAudio(samples: Array(repeating: 0.25, count: 3_200))
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancellations = 0
    private var cancellationDelay: Duration = .zero

    init(log: EventLog) { self.log = log }

    func requestPermission() async -> Bool {
        await log.append("permission")
        return permission
    }

    func startCapture() async throws {
        starts += 1
        await log.append("start")
    }

    func stopCapture() async throws -> DictationAudio {
        stops += 1
        await log.append("stop")
        return audio
    }

    func cancelCapture() async {
        cancellations += 1
        await log.append("cancel-audio")
        try? await Task.sleep(for: cancellationDelay)
    }

    func setAudio(_ audio: DictationAudio) { self.audio = audio }
    func setCancellationDelay(_ delay: Duration) { cancellationDelay = delay }
}

actor FakeTranscriber: LocalDictationTranscribing {
    enum Behavior {
        case fixed(String)
    }

    let log: EventLog
    private var behavior: Behavior
    private(set) var calls = 0

    init(log: EventLog, behavior: Behavior = .fixed("  locally transcribed  ")) {
        self.log = log
        self.behavior = behavior
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        calls += 1
        await log.append("transcribe")
        switch behavior {
        case .fixed(let transcript):
            return transcript
        }
    }
}

actor GatedAudioCapture: DictationAudioCapturing {
    let log: EventLog
    var audio = DictationAudio(samples: Array(repeating: 0.25, count: 3_200))
    private(set) var permissionRequests = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancellations = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    init(log: EventLog) { self.log = log }

    func requestPermission() async -> Bool {
        permissionRequests += 1
        await log.append("permission")
        return true
    }

    func startCapture() async throws {
        starts += 1
        await log.append("start-waiting")
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        await log.append("start")
    }

    func stopCapture() async throws -> DictationAudio {
        stops += 1
        await log.append("stop")
        return audio
    }

    func cancelCapture() async {
        cancellations += 1
        await log.append("cancel-audio")
    }

    func isWaiting() -> Bool { continuation != nil }

    func releaseStart() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private enum FakePolisherError: Error {
    case unavailable
}

actor FakePolisher: DictationTextPolishing {
    enum Behavior {
        case passthrough
        case polish(String)
        case fail
    }

    let log: EventLog
    private var behavior: Behavior
    private(set) var calls = 0
    private(set) var cancellations = 0

    init(log: EventLog, behavior: Behavior = .passthrough) {
        self.log = log
        self.behavior = behavior
    }

    func polish(_ transcript: String) async throws -> String {
        calls += 1
        await log.append("polish")
        switch behavior {
        case .passthrough:
            return transcript
        case .polish(let transcript):
            return transcript
        case .fail:
            throw FakePolisherError.unavailable
        }
    }

    func cancelPolishing() async {
        cancellations += 1
        await log.append("cancel-polish")
    }
}

actor TeardownAwareTranscriber: LocalDictationTranscribing {
    private var calls = 0
    private var activeInferences = 0
    private var maximumConcurrentInferences = 0

    func transcribe(_ audio: DictationAudio) async throws -> String {
        calls += 1
        let call = calls
        activeInferences += 1
        maximumConcurrentInferences = max(maximumConcurrentInferences, activeInferences)
        defer { activeInferences -= 1 }

        if call == 1 {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                // Simulate Core ML work that needs time to unwind after its
                // Swift task receives cancellation.
                await Task.detached {
                    try? await Task.sleep(for: .milliseconds(60))
                }.value
                throw CancellationError()
            }
        }
        return "replacement transcript"
    }

    func cancelTranscription() async {
        while activeInferences > 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func activeCount() -> Int { activeInferences }
    func maximumConcurrentCount() -> Int { maximumConcurrentInferences }
}

actor TeardownAwarePolisher: DictationTextPolishing {
    private var calls = 0
    private var activePolishes = 0
    private var maximumConcurrentPolishes = 0
    private var cancellations = 0

    func polish(_ transcript: String) async throws -> String {
        calls += 1
        let call = calls
        activePolishes += 1
        maximumConcurrentPolishes = max(maximumConcurrentPolishes, activePolishes)
        defer { activePolishes -= 1 }

        if call == 1 {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                // Match the local model teardown behavior: the cancellation
                // method must not return until the previous request is gone.
                await Task.detached {
                    try? await Task.sleep(for: .milliseconds(60))
                }.value
                throw CancellationError()
            }
        }
        return "replacement polished transcript"
    }

    func cancelPolishing() async {
        cancellations += 1
        while activePolishes > 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func activeCount() -> Int { activePolishes }
    func maximumConcurrentCount() -> Int { maximumConcurrentPolishes }
    func cancellationCount() -> Int { cancellations }
}

actor FakeInserter: DictationTextInserting {
    typealias Target = String

    let log: EventLog
    private(set) var insertions: [(String, String)] = []

    init(log: EventLog) { self.log = log }

    func insert(_ text: String, into target: String) async throws {
        insertions.append((text, target))
        await log.append("insert")
    }

    func insertionCount() -> Int { insertions.count }
}

private struct FriendlyTargetError: LocalizedError {
    var errorDescription: String? { "Enable the required permission in System Settings." }
}

actor FailingTargetProvider: DictationTargetCapturing {
    typealias Target = String

    func captureTarget() async throws -> String {
        throw FriendlyTargetError()
    }
}

actor GatedTargetProvider: DictationTargetCapturing {
    typealias Target = String

    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func captureTarget() async throws -> String {
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return "focused-before-hud"
    }

    func isWaiting() -> Bool { continuation != nil }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [DictationState] = []

    func record(_ state: DictationState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    func snapshot() -> [DictationState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }
}

func waitForState<T, A, R, P, I>(
    _ expected: DictationState,
    controller: DictationController<T, A, R, P, I>,
    message: String
) async where T: DictationTargetCapturing,
              A: DictationAudioCapturing,
              R: LocalDictationTranscribing,
              P: DictationTextPolishing,
              I: DictationTextInserting,
              T.Target == I.Target {
    for _ in 0..<200 {
        if await controller.state == expected { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    let actual = await controller.state
    fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
    exit(1)
}

@main
struct DictationRegressionRunner {
    static func main() async {
        testReducerPolicy()
        testModelDownloadPolicy()
        testVocabularyPolicy()
        testS1MiniContract()
        await testWarmupSequencerRunsSpeechBeforeCleanup()
        await testWarmupSequencerDeduplicatesCleanup()
        await testSpeechWarmupWaitsForActiveCleanup()
        testModelStorageRemoval()
        testWhisperModelCatalog()
        testModifierOnlyShortcutPolicy()
        testEventTapRecoveryPolicy()
        testEventTapStartRequestPolicy()
        testShortcutSessionGate()
        testAudioNormalization()
        testAudioLevelMeter()
        await testShortcutEventOrdering()
        await testTargetCapturedBeforeHUDStatePublication()
        await testSuccessfulControllerFlow()
        await testStartupReleaseFinishesAfterCaptureStarts()
        await testStartupReleaseLatchResetsOnCancel()
        await testStartupReleaseLatchResetsOnFailure()
        await testPolishingFallbacks()
        await testEmptyModelOutputUsesDistinctFailure()
        await testShortAudioAndCancellation()
        await testRapidCancelThenRestart()
        await testTranscriptionTeardownBeforeRestart()
        await testPolishingTeardownBeforeRestart()
        await testWatchdogAndLocalizedErrors()
        print("dictation-regression-pass")
    }

    static func testModelDownloadPolicy() {
        assertCondition(
            DictationModelRequest.settingsDownload.allowsDownload,
            "the settings button should be allowed to download the speech model"
        )
        assertCondition(
            !DictationModelRequest.transcription.allowsDownload,
            "starting dictation must never download a speech model"
        )
    }

    static func testVocabularyPolicy() {
        let duplicateID = UUID()
        let sanitized = DictationVocabularyPolicy.sanitized([
            DictationVocabularyEntry(id: duplicateID, spoken: "  srushti  ", replacement: " Srushti "),
            DictationVocabularyEntry(spoken: "SRUSHTI", replacement: "Wrong duplicate"),
            DictationVocabularyEntry(spoken: "", replacement: "ignored"),
        ])
        assertEqual(sanitized.count, 1, "vocabulary should trim entries and reject blank or duplicate phrases")
        assertEqual(sanitized.first?.id, duplicateID, "sanitizing should preserve stable entry identifiers")
        assertEqual(sanitized.first?.spoken, "srushti", "vocabulary should trim spoken phrases")
        assertEqual(sanitized.first?.replacement, "Srushti", "vocabulary should trim replacements")

        let entries = [
            DictationVocabularyEntry(
                spoken: "g p t five point six sol",
                replacement: "gpt-5.6-sol"
            ),
            DictationVocabularyEntry(spoken: "srushti", replacement: "Srushti"),
            DictationVocabularyEntry(spoken: "go", replacement: "Go"),
            DictationVocabularyEntry(spoken: "visual studio", replacement: "Visual Studio"),
            DictationVocabularyEntry(spoken: "visual studio code", replacement: "VS Code"),
        ]
        assertEqual(
            DictationVocabularyPolicy.apply(
                entries,
                to: "ask srushti about G P T FIVE POINT SIX SOL in golang, then go. open visual studio code"
            ),
            "ask Srushti about gpt-5.6-sol in golang, then Go. open VS Code",
            "vocabulary should be case-insensitive, boundary-aware, and prefer the longest phrase"
        )
        assertEqual(
            DictationVocabularyPolicy.apply([
                DictationVocabularyEntry(spoken: "foo", replacement: "bar"),
                DictationVocabularyEntry(spoken: "bar", replacement: "baz"),
            ], to: "foo bar"),
            "bar baz",
            "vocabulary replacements should not cascade into one another"
        )
        assertEqual(
            DictationVocabularyPolicy.apply([
                DictationVocabularyEntry(spoken: "gpt-5.6-sol", replacement: "gpt-5.6-sol"),
            ], to: "GPT-5.6-SOL"),
            "gpt-5.6-sol",
            "a canonical vocabulary pass should restore exact code-term casing"
        )
        let cascadingEntries = [
            DictationVocabularyEntry(spoken: "foo", replacement: "bar"),
            DictationVocabularyEntry(spoken: "bar", replacement: "baz"),
        ]
        let correctedRaw = S1MiniVocabularyPipeline.prepare(
            transcript: "foo",
            vocabulary: cascadingEntries
        )
        assertEqual(correctedRaw, "bar", "the pre-inference pass should apply one replacement")
        assertEqual(
            S1MiniVocabularyPipeline.finalize(
                correctedRawTranscript: correctedRaw,
                polishedTranscript: "bar",
                vocabulary: cascadingEntries
            ),
            "bar",
            "the post-inference pass must not cascade a canonical replacement"
        )
        assertEqual(
            DictationVocabularyPolicy.sanitized([
                DictationVocabularyEntry(spoken: "cafe", replacement: "Cafe"),
                DictationVocabularyEntry(spoken: "café", replacement: "Café"),
            ]).count,
            2,
            "diacritic-distinct spoken phrases should remain independently matchable"
        )
    }

    static func testS1MiniContract() {
        assertEqual(S1MiniModel.downloadSize, 484_219_808, "S1-mini should verify the pinned Q4_K_M byte size")
        assertEqual(
            S1MiniModel.sha256,
            "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634",
            "S1-mini should verify the official GGUF SHA-256"
        )
        let prompt = S1MiniModel.prompt(transcript: "um hello there", style: .punctuated)
        assertCondition(
            prompt.hasPrefix("<|im_start|>system\n\(S1MiniModel.systemPrompt)<|im_end|>"),
            "S1-mini should receive its exact required system prompt"
        )
        assertCondition(
            prompt.contains("[Styling: semi-casual] [Structure: prose] [Context: general]\num hello there"),
            "conversational style should map to S1-mini's trained semi-casual control value"
        )
        assertCondition(
            prompt.hasSuffix("<|im_start|>assistant\n<think>\n\n</think>\n\n"),
            "S1-mini should receive the required empty non-thinking assistant prefix"
        )
        assertEqual(
            DictationWritingStyle.casual.s1MiniStyle,
            "semi-casual",
            "casual style should use a trained S1-mini control value"
        )
        assertEqual(
            DictationWritingStyle.punctuated.label,
            "Conversational",
            "the standard spoken-English style should be presented as Conversational"
        )
        assertEqual(
            DictationWritingStyle.punctuated.s1MiniStyle,
            "semi-casual",
            "conversational style should use S1-mini's conversational control value"
        )
        assertEqual(
            DictationWritingStyle.casual.applyOutputConventions(to: "Hey Sarah, I'm Ready."),
            "hey sarah, i'm ready.",
            "casual cleanup should deterministically produce lowercase text"
        )
        assertEqual(
            DictationWritingStyle.punctuated.applyOutputConventions(to: "Hey Sarah, I'm Ready."),
            "Hey Sarah, I'm Ready.",
            "conversational cleanup should preserve standard capitalization"
        )
        assertEqual(
            DictationWritingStyle.formal.s1MiniStyle,
            "formal",
            "formal style should use a trained S1-mini control value"
        )
        assertCondition(
            S1MiniOutputPolicy.isSafe(
                rawTranscript: "ask Srushti about gpt-5.6-sol",
                polishedTranscript: "Ask Srushti about gpt-5.6-sol.",
                protectedTerms: ["Srushti", "gpt-5.6-sol"]
            ),
            "safe S1-mini output should preserve vocabulary-protected terms"
        )
        assertCondition(
            !S1MiniOutputPolicy.isSafe(
                rawTranscript: "ask Srushti about gpt-5.6-sol",
                polishedTranscript: "Ask Shrishti about GPT 5.6.",
                protectedTerms: ["Srushti", "gpt-5.6-sol"]
            ),
            "S1-mini output that damages a protected term should fall back"
        )
        assertCondition(
            !S1MiniOutputPolicy.isSafe(
                rawTranscript: "hello",
                polishedTranscript: "<think>hello</think>",
                protectedTerms: []
            ),
            "S1-mini control-token leakage should fall back"
        )
        assertCondition(
            !S1MiniOutputPolicy.isSafe(
                rawTranscript: "hello",
                polishedTranscript: String(repeating: "invented ", count: 80),
                protectedTerms: []
            ),
            "disproportionately long S1-mini output should fall back"
        )
    }

    static func testWarmupSequencerRunsSpeechBeforeCleanup() async {
        let log = EventLog()
        let sequencer = DictationWarmupSequencer()

        await sequencer.startSpeechThenCleanup(
            generation: 1,
            prepareSpeech: {
                await log.append("speech-start")
                try? await Task.sleep(for: .milliseconds(20))
                await log.append("speech-end")
            },
            speechReady: { generation in
                await log.append("speech-ready-\(generation)")
            },
            shouldRunCleanup: { generation in
                await log.append("cleanup-check-\(generation)")
                return true
            },
            prepareCleanup: {
                await log.append("cleanup-start")
            }
        )

        for _ in 0..<100 where !(await log.snapshot()).contains("cleanup-start") {
            try? await Task.sleep(for: .milliseconds(2))
        }

        let values = await log.snapshot()
        assertEqual(
            values,
            ["speech-start", "speech-end", "speech-ready-1", "cleanup-check-1", "cleanup-start"],
            "warmup should finish speech and publish readiness before cleanup model preparation"
        )
    }

    static func testWarmupSequencerDeduplicatesCleanup() async {
        let log = EventLog()
        let sequencer = DictationWarmupSequencer()

        await sequencer.startCleanupAfterCurrentSpeech(
            generation: 2,
            shouldRunCleanup: { _ in true },
            prepareCleanup: {
                await log.append("cleanup")
                try? await Task.sleep(for: .milliseconds(25))
            }
        )
        await sequencer.startCleanupAfterCurrentSpeech(
            generation: 2,
            shouldRunCleanup: { _ in true },
            prepareCleanup: {
                await log.append("cleanup")
            }
        )

        try? await Task.sleep(for: .milliseconds(60))
        assertEqual(
            await log.count(of: "cleanup"),
            1,
            "warmup should not start a second cleanup preparation while one is active"
        )
    }

    static func testSpeechWarmupWaitsForActiveCleanup() async {
        let log = EventLog()
        let sequencer = DictationWarmupSequencer()

        await sequencer.startCleanupAfterCurrentSpeech(
            generation: 1,
            shouldRunCleanup: { _ in true },
            prepareCleanup: {
                await log.append("cleanup-start")
                try? await Task.sleep(for: .milliseconds(30))
                await log.append("cleanup-end")
            }
        )
        for _ in 0..<100 where !(await log.snapshot()).contains("cleanup-start") {
            try? await Task.sleep(for: .milliseconds(2))
        }

        await sequencer.startSpeechThenCleanup(
            generation: 2,
            prepareSpeech: {
                await log.append("speech-start")
            },
            speechReady: { _ in },
            shouldRunCleanup: { _ in false },
            prepareCleanup: {}
        )

        for _ in 0..<100 where !(await log.snapshot()).contains("speech-start") {
            try? await Task.sleep(for: .milliseconds(2))
        }
        assertEqual(
            await log.snapshot(),
            ["cleanup-start", "cleanup-end", "speech-start"],
            "a new speech-model warmup must wait for active cleanup-model preparation"
        )
    }

    static func testModelStorageRemoval() {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let repositoryRoot = temporaryRoot.appendingPathComponent("repository", isDirectory: true)
        let metadataRoot = repositoryRoot
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)

        do {
            try fileManager.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryRoot) }

            let modelDirectory = repositoryRoot.appendingPathComponent("model", isDirectory: true)
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try "weights".write(
                to: modelDirectory.appendingPathComponent("weights.bin"),
                atomically: true,
                encoding: .utf8
            )
            let modelMetadata = metadataRoot.appendingPathComponent("model", isDirectory: true)
            try fileManager.createDirectory(at: modelMetadata, withIntermediateDirectories: true)
            try "metadata".write(
                to: modelMetadata.appendingPathComponent("download.json"),
                atomically: true,
                encoding: .utf8
            )
            let sentinel = repositoryRoot.appendingPathComponent("keep.txt")
            let metadataSentinel = metadataRoot.appendingPathComponent("keep.txt")
            try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
            try "keep metadata".write(to: metadataSentinel, atomically: true, encoding: .utf8)

            try DictationModelStorage.removeAllowlistedItems(
                from: repositoryRoot,
                topLevelItems: ["model"]
            )

            assertCondition(
                !fileManager.fileExists(atPath: modelDirectory.path),
                "model removal should delete the allowlisted repository item"
            )
            assertCondition(
                !fileManager.fileExists(atPath: modelMetadata.path),
                "model removal should delete matching download metadata"
            )
            assertCondition(
                fileManager.fileExists(atPath: sentinel.path),
                "model removal should preserve unrelated repository files"
            )
            assertCondition(
                fileManager.fileExists(atPath: metadataSentinel.path),
                "model removal should preserve unrelated download metadata"
            )

            let outsideSentinel = temporaryRoot.appendingPathComponent("outside-sentinel.txt")
            try "still here".write(to: outsideSentinel, atomically: true, encoding: .utf8)
            for unsafeName in ["", ".", "..", "../outside-sentinel.txt", "nested/item", "volume:item"] {
                do {
                    try DictationModelStorage.removeAllowlistedItems(
                        from: repositoryRoot,
                        topLevelItems: [unsafeName]
                    )
                    assertCondition(false, "model removal should reject unsafe item name \(unsafeName)")
                } catch DictationModelStorageError.unsafeRemovalTarget {
                    assertCondition(
                        fileManager.fileExists(atPath: outsideSentinel.path),
                        "rejecting an unsafe item should not escape the repository root"
                    )
                } catch {
                    assertCondition(false, "unsafe item rejection returned the wrong error: \(error)")
                }
            }

            let safeVictim = repositoryRoot.appendingPathComponent("safe-victim.txt")
            try "preserve me".write(to: safeVictim, atomically: true, encoding: .utf8)
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: repositoryRoot,
                    topLevelItems: ["safe-victim.txt", "../outside-sentinel.txt"]
                )
                assertCondition(false, "model removal should reject a list containing an unsafe item")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: safeVictim.path),
                    "model removal should validate the full allowlist before deleting anything"
                )
                assertCondition(
                    fileManager.fileExists(atPath: outsideSentinel.path),
                    "mixed safe and unsafe names should preserve files outside the repository"
                )
            } catch {
                assertCondition(false, "mixed item rejection returned the wrong error: \(error)")
            }

            let externalTarget = temporaryRoot.appendingPathComponent("external-model.bin")
            let modelLink = repositoryRoot.appendingPathComponent("model-link")
            try "external weights".write(to: externalTarget, atomically: true, encoding: .utf8)
            try fileManager.createSymbolicLink(
                atPath: modelLink.path,
                withDestinationPath: externalTarget.path
            )

            try DictationModelStorage.removeAllowlistedItems(
                from: repositoryRoot,
                topLevelItems: ["model-link"]
            )

            assertCondition(
                (try? fileManager.destinationOfSymbolicLink(atPath: modelLink.path)) == nil,
                "model removal should unlink an allowlisted symbolic link"
            )
            assertCondition(
                fileManager.fileExists(atPath: externalTarget.path),
                "unlinking a model layout should not delete its target"
            )
            assertEqual(
                try String(contentsOf: externalTarget, encoding: .utf8),
                "external weights",
                "unlinking a model layout should preserve target contents"
            )

            let externalMetadata = temporaryRoot.appendingPathComponent(
                "external-download-metadata",
                isDirectory: true
            )
            try fileManager.createDirectory(at: externalMetadata, withIntermediateDirectories: true)
            let externalMetadataModel = externalMetadata.appendingPathComponent(
                "model",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: externalMetadataModel,
                withIntermediateDirectories: true
            )
            let externalMetadataSentinel = externalMetadataModel.appendingPathComponent("keep.json")
            try "external metadata".write(
                to: externalMetadataSentinel,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.removeItem(at: metadataRoot)
            try fileManager.createSymbolicLink(
                atPath: metadataRoot.path,
                withDestinationPath: externalMetadata.path
            )
            let modelBeforeUnsafeMetadata = repositoryRoot.appendingPathComponent(
                "model-before-unsafe-metadata",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: modelBeforeUnsafeMetadata,
                withIntermediateDirectories: true
            )
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: repositoryRoot,
                    topLevelItems: ["model-before-unsafe-metadata"]
                )
                assertCondition(false, "model removal should reject a symlinked metadata directory")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: modelBeforeUnsafeMetadata.path),
                    "metadata validation should happen before deleting the model"
                )
                assertCondition(
                    fileManager.fileExists(atPath: externalMetadataSentinel.path),
                    "rejecting symlinked metadata should preserve external files"
                )
            } catch {
                assertCondition(false, "symlinked metadata rejection returned the wrong error: \(error)")
            }

            let symlinkedRepository = temporaryRoot.appendingPathComponent("linked-repository")
            try fileManager.createSymbolicLink(
                atPath: symlinkedRepository.path,
                withDestinationPath: repositoryRoot.path
            )
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: symlinkedRepository,
                    topLevelItems: ["keep.txt"]
                )
                assertCondition(false, "model removal should reject a symlinked repository root")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: sentinel.path),
                    "rejecting a symlinked repository should preserve its target files"
                )
            } catch {
                assertCondition(false, "symlinked repository rejection returned the wrong error: \(error)")
            }

            do {
                try DictationModelStorage.removeAllowlistedTopLevelItems(
                    from: symlinkedRepository,
                    topLevelItems: ["keep.txt"]
                )
                assertCondition(false, "layout removal should reject a symlinked root")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: sentinel.path),
                    "rejecting a symlinked layout root should preserve its target files"
                )
            } catch {
                assertCondition(false, "symlinked layout rejection returned the wrong error: \(error)")
            }
        } catch {
            fputs("Assertion failed: model storage removal threw \(error)\n", stderr)
            exit(1)
        }
    }

    static func testWhisperModelCatalog() {
        let models = DictationModelDescriptor.all
        assertEqual(models.count, 4, "the local catalog should contain Whisper and Parakeet choices")
        assertEqual(
            models.first?.id,
            .parakeetUnifiedEnglish,
            "the recommended speech model should appear first"
        )
        assertEqual(
            Set(models.map(\.id)).count,
            models.count,
            "every speech model should have a unique persisted identifier"
        )
        assertEqual(
            DictationModelID.whisperSmallEnglish.engine,
            .whisperKit,
            "Whisper models should use the WhisperKit adapter"
        )
        assertEqual(
            DictationModelID.parakeetUnifiedEnglish.engine,
            .fluidAudio,
            "Parakeet models should use the FluidAudio adapter"
        )
        assertEqual(
            DictationModelOperation.installing(.parakeetUnifiedEnglish).model,
            .parakeetUnifiedEnglish,
            "model operations should retain their one active model"
        )
        assertEqual(
            DictationModelOperation.selecting(.whisperLargeV3).model,
            .whisperLargeV3,
            "model selection should expose its active model"
        )
        assertEqual(
            DictationModelOperation.removing(.parakeetV3Multilingual).model,
            .parakeetV3Multilingual,
            "model removal should expose its active model"
        )
        assertEqual(
            DictationModelID.resolveSelection(nil),
            .whisperSmallEnglish,
            "a new install should keep the lightweight model selected"
        )
        assertEqual(
            DictationModelID.resolveSelection("not-a-model"),
            .whisperSmallEnglish,
            "an obsolete saved model should fall back safely"
        )
        assertEqual(
            DictationModelID.resolveSelection(WhisperDictationModel.largeV3.rawValue),
            .whisperLargeV3,
            "a legacy Large v3 selection should migrate without a download"
        )
        assertEqual(
            DictationModelDescriptor.descriptor(for: .parakeetUnifiedEnglish).downloadSizeLabel,
            "614 MB",
            "settings should show the verified Parakeet download size"
        )
        assertCondition(
            DictationModelDescriptor.descriptor(for: .parakeetUnifiedEnglish).isRecommended,
            "Parakeet Unified should be presented as the English quality option"
        )
        assertEqual(
            DictationModelDescriptor.descriptor(for: .parakeetV3Multilingual).downloadSizeLabel,
            "483 MB",
            "Parakeet v3 should disclose its verified INT8 download size"
        )
    }

    static func testReducerPolicy() {
        var machine = DictationSessionStateMachine()
        assertEqual(machine.handle(.hotKeyUp), .none, "an unmatched key-up should be ignored")
        assertEqual(machine.state, .idle, "an unmatched key-up should preserve idle")

        assertEqual(machine.handle(.hotKeyDown), .beginRequest, "the first key-down should begin a request")
        assertEqual(machine.state, .requestingPermission, "the request state should be observable")
        assertEqual(machine.handle(.hotKeyDown), .none, "repeated key-down should be ignored")
        assertEqual(machine.handle(.captureStarted), .none, "capture startup should not emit another command")
        assertEqual(machine.state, .listening, "successful capture startup should enter listening")
        assertEqual(machine.handle(.hotKeyUp), .finishCapture, "key-up should finish the active capture")
        assertEqual(machine.state, .transcribing, "key-up should enter transcribing")
        assertEqual(machine.handle(.transcriptionCompleted("hello")), .insert, "transcription should request insertion")
        assertEqual(machine.state, .inserting, "completed transcription should enter inserting")
        assertEqual(machine.handle(.insertionCompleted("hello")), .none, "insertion completion needs no follow-up action")
        assertEqual(machine.state, .succeeded("hello"), "successful insertion should retain the transcript")
        assertEqual(
            DictationSettingsStatus.title(for: .succeeded("hello")),
            "Ready",
            "settings should show readiness after a completed dictation"
        )
        assertEqual(
            DictationSettingsStatus.title(for: .listening),
            "Listening",
            "settings should still expose active dictation work"
        )

        let policy = DictationAudioPolicy(minimumDuration: 0.10)
        assertCondition(!policy.shouldTranscribe(DictationAudio(samples: [])), "zero audio should be ignored")
        assertCondition(
            !policy.shouldTranscribe(DictationAudio(samples: Array(repeating: 0, count: 1_599))),
            "sub-threshold audio should be ignored"
        )
        assertCondition(
            policy.shouldTranscribe(DictationAudio(samples: Array(repeating: 0, count: 1_600))),
            "threshold-length audio should be transcribed"
        )
        assertEqual(
            DictationTranscriptPolicy.normalize("  Go-jo   local dictation  "),
            "Gojo local dictation",
            "transcript policy should collapse whitespace and correct the product name"
        )
    }

    static func testAudioNormalization() {
        let sourceSampleRate = 48_000.0
        let source = (0..<48_000).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sourceSampleRate))
        }
        do {
            let normalized = try AVAudioEngineCaptureService.normalize(
                samples: source,
                from: sourceSampleRate
            )
            assertEqual(
                normalized.sampleRate,
                DictationAudio.transcriptionSampleRate,
                "capture output should use the transcription sample rate"
            )
            assertCondition(
                abs(normalized.samples.count - 16_000) <= 32,
                "one second of 48 kHz input should normalize to about 16,000 samples"
            )
            assertCondition(
                abs(normalized.duration - 1) < 0.003,
                "sample-rate conversion should preserve duration"
            )
        } catch {
            fputs("Assertion failed: audio normalization threw \(error)\n", stderr)
            exit(1)
        }
    }

    static func testAudioLevelMeter() {
        var silentMeter = DictationAudioLevelMeter()
        let silent = silentMeter.consume(
            sumOfSquares: 0,
            peak: 0,
            sampleCount: 2_048,
            timestamp: 1
        )
        assertEqual(silent, 0, "silence should produce a zero audio level")

        var speechMeter = DictationAudioLevelMeter()
        let speech = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 1
        )
        assertCondition((speech ?? 0) > 0.4, "speech energy should produce a visible audio level")
        assertCondition((speech ?? 2) <= 1, "the audio level should remain normalized")

        let throttled = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 20_000_000
        )
        assertEqual(throttled, nil, "the meter should publish no faster than 25 Hz")
        let next = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 40_000_001
        )
        assertCondition(next != nil, "the meter should publish again after 40 milliseconds")

        speechMeter.reset()
        let reset = speechMeter.consume(
            sumOfSquares: 0,
            peak: 0,
            sampleCount: 2_048,
            timestamp: 40_000_002
        )
        assertEqual(reset, 0, "reset should clear smoothing and throttling state")
    }

    static func testModifierOnlyShortcutPolicy() {
        // Activation mode regression coverage begins here.
        func flags(
            exact: Bool,
            anyTriggerDown: Bool,
            disallowed: Bool = false
        ) -> DictationModifierShortcutStateMachine.Event {
            .flagsChanged(
                isExactChord: exact,
                anyTriggerModifierDown: anyTriggerDown,
                hasDisallowedModifiers: disallowed
            )
        }

        var shortcut = DictationModifierShortcutStateMachine(mode: .holdToTalk)

        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "pressing only one trigger modifier should not arm dictation"
        )
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .scheduleActivation,
            "Control-Option should arm modifier-only dictation"
        )
        assertEqual(
            shortcut.handle(.keyDown),
            .cancelScheduledActivation,
            "a normal key should disqualify a Control-Option window shortcut"
        )
        assertEqual(shortcut.state, .blocked, "the chord should stay blocked until both modifiers are released")
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "a blocked chord must not re-arm while the modifiers remain held"
        )
        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: false)),
            .none,
            "releasing both modifiers should reset the chord"
        )

        var quickRelease = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = quickRelease.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            quickRelease.handle(flags(exact: false, anyTriggerDown: false)),
            .cancelScheduledActivation,
            "releasing the chord before the delay should cancel activation"
        )
        assertEqual(
            quickRelease.handle(.activationDelayElapsed),
            .none,
            "a canceled activation timer must not start dictation later"
        )
        assertEqual(quickRelease.state, .idle, "a quick release should return to idle")

        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .scheduleActivation,
            "a fresh Control-Option hold should arm"
        )
        assertEqual(
            shortcut.handle(.activationDelayElapsed),
            .beginDictation,
            "holding the chord through the activation delay should start dictation"
        )
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "repeated modifier events must not restart an active session"
        )
        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: true)),
            .finishDictation,
            "releasing either trigger modifier should finish dictation"
        )
        assertEqual(shortcut.state, .blocked, "a partial release should prevent accidental immediate restart")
        _ = shortcut.handle(flags(exact: false, anyTriggerDown: false))

        _ = shortcut.handle(flags(exact: true, anyTriggerDown: true))
        _ = shortcut.handle(.activationDelayElapsed)
        assertEqual(
            shortcut.handle(.keyDown),
            .cancelDictation,
            "typing another key while dictating should cancel instead of colliding with an existing shortcut"
        )

        var disallowedHold = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        assertEqual(
            disallowedHold.handle(flags(exact: false, anyTriggerDown: true, disallowed: true)),
            .none,
            "an extra modifier should block a hold gesture"
        )
        assertEqual(disallowedHold.state, .blocked, "a disallowed modifier should block until every modifier is up")
        _ = disallowedHold.handle(flags(exact: false, anyTriggerDown: false))

        var armingReset = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = armingReset.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            armingReset.reset(),
            .cancelScheduledActivation,
            "resetting a disabled event tap should cancel a pending activation"
        )
        assertEqual(armingReset.state, .idle, "a reset pending chord should return to idle")

        var activeReset = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = activeReset.handle(flags(exact: true, anyTriggerDown: true))
        _ = activeReset.handle(.activationDelayElapsed)
        assertEqual(
            activeReset.reset(),
            .cancelDictation,
            "resetting a disabled event tap should cancel an active dictation session"
        )
        assertEqual(activeReset.state, .idle, "a reset active chord should return to idle")

        var blockedReset = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = blockedReset.handle(flags(exact: true, anyTriggerDown: true))
        _ = blockedReset.handle(.keyDown)
        assertEqual(blockedReset.state, .blocked, "a lost release can leave the shortcut blocked")
        assertEqual(
            blockedReset.reset(),
            .none,
            "lifecycle recovery should clear a blocked shortcut without emitting a session event"
        )
        assertEqual(
            blockedReset.state,
            .idle,
            "lifecycle recovery should make the next shortcut usable after a lost release"
        )

        var tap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "tap mode should wait for a complete press and release cycle"
        )
        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "duplicate flags must not start tap mode twice"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "releasing the first modifier should not start tap mode"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: false)),
            .beginDictation,
            "releasing both modifiers should start tap mode"
        )
        assertEqual(tap.state, .active, "tap mode should stay active after the first clean tap")

        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "the second tap should wait for release before stopping"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "a partial release should not stop tap mode"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: false)),
            .finishDictation,
            "a second clean tap should stop dictation"
        )
        assertEqual(tap.state, .idle, "a completed stop tap should return to idle")

        var dirtyTap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = dirtyTap.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            dirtyTap.handle(.keyDown),
            .none,
            "a normal key should disqualify a pending tap without starting dictation"
        )
        assertEqual(dirtyTap.state, .blocked, "a dirty tap should stay blocked through release")
        _ = dirtyTap.handle(flags(exact: false, anyTriggerDown: false))

        var activeTap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = activeTap.handle(flags(exact: true, anyTriggerDown: true))
        _ = activeTap.handle(flags(exact: false, anyTriggerDown: false))
        assertEqual(
            activeTap.handle(flags(exact: false, anyTriggerDown: false, disallowed: true)),
            .cancelDictation,
            "an extra modifier should cancel an active tap session"
        )
        assertEqual(activeTap.state, .blocked, "a canceled tap session should remain blocked until modifiers clear")

        var modeChange = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = modeChange.handle(flags(exact: true, anyTriggerDown: true))
        _ = modeChange.handle(.activationDelayElapsed)
        assertEqual(
            modeChange.setMode(.tapToTalk),
            .cancelDictation,
            "changing modes should cancel an active session exactly once"
        )
        assertEqual(
            modeChange.setMode(.tapToTalk),
            .none,
            "setting the same mode again should be idempotent"
        )
        assertEqual(modeChange.state, .idle, "mode changes should reset shortcut state")

        let suiteName = "DictationActivationModeRegression.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("Assertion failed: could not create activation mode test defaults\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        assertEqual(
            DictationActivationMode.saved(in: defaults),
            .holdToTalk,
            "hold to talk should be the default activation mode"
        )
        DictationActivationMode.tapToTalk.save(in: defaults)
        assertEqual(
            DictationActivationMode.saved(in: defaults),
            .tapToTalk,
            "the selected activation mode should persist"
        )
        // Activation mode regression coverage ends here.
    }

    static func testEventTapRecoveryPolicy() {
        var policy = DictationEventTapRecoveryPolicy()
        let staleAttempt = policy.beginStartAttempt()
        let latestAttempt = policy.beginStartAttempt()
        assertCondition(
            !policy.ownsStartAttempt(staleAttempt),
            "a newer start should supersede an in-flight authorization check"
        )
        assertCondition(
            policy.ownsStartAttempt(latestAttempt),
            "the latest authorization check should be allowed to create the tap"
        )
        policy.invalidateStartAttempts()
        assertCondition(
            !policy.ownsStartAttempt(latestAttempt),
            "stopping the monitor should invalidate an in-flight start"
        )

        let expectedBackoff = [250, 500, 1_000, 2_000, 5_000, 5_000]
        let actualBackoff = expectedBackoff.map { _ in
            policy.nextRetryDelayMilliseconds()
        }
        assertEqual(
            actualBackoff,
            expectedBackoff,
            "event-tap recovery should retry quickly, back off, and never give up permanently"
        )
        assertEqual(
            policy.consecutiveFailures,
            5,
            "the retry policy should cap its failure counter with its maximum delay"
        )

        policy.recordSuccess()
        assertEqual(
            policy.consecutiveFailures,
            0,
            "a healthy tap should clear accumulated failures"
        )
        assertEqual(
            policy.nextRetryDelayMilliseconds(),
            250,
            "a later failure should retry promptly after recovery"
        )
    }

    static func testEventTapStartRequestPolicy() {
        var requests = DictationEventTapStartRequestPolicy()
        assertCondition(
            requests.enqueue(promptIfNeeded: false),
            "the first event-tap start request should own the start loop"
        )
        assertEqual(
            requests.nextRequest(),
            false,
            "a background recovery should initially remain nonprompting"
        )
        assertCondition(
            !requests.enqueue(promptIfNeeded: true),
            "an overlapping start should be coalesced into the active loop"
        )
        assertEqual(
            requests.nextRequest(),
            true,
            "an overlapping permission prompt must not be downgraded by recovery"
        )
        assertEqual(
            requests.nextRequest(),
            nil,
            "the coalescer should drain all pending start requests"
        )
        assertCondition(!requests.isRunning, "the start loop should become idle after draining")

        assertCondition(
            requests.enqueue(promptIfNeeded: true),
            "a later start should be able to own a fresh loop"
        )
        requests.cancelPendingRequests()
        assertEqual(
            requests.nextRequest(),
            nil,
            "stopping the monitor should discard queued starts"
        )
    }

    static func testShortcutSessionGate() {
        var gate = DictationShortcutSessionGate()
        assertCondition(
            !gate.consumeKeyUp(),
            "an unmatched release must not stop an unrelated dictation session"
        )
        gate.acceptKeyDown()
        assertCondition(
            gate.consumeKeyUp(),
            "an admitted shortcut press should allow exactly one matching release"
        )
        assertCondition(
            !gate.consumeKeyUp(),
            "duplicate releases should be ignored"
        )
        gate.acceptKeyDown()
        gate.reset()
        assertCondition(
            !gate.consumeKeyUp(),
            "cancellation should invalidate the pending shortcut release"
        )

        func flags(
            exact: Bool,
            anyTriggerDown: Bool
        ) -> DictationModifierShortcutStateMachine.Event {
            .flagsChanged(
                isExactChord: exact,
                anyTriggerModifierDown: anyTriggerDown,
                hasDisallowedModifiers: false
            )
        }
        var rejectedTap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = rejectedTap.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            rejectedTap.handle(flags(exact: false, anyTriggerDown: false)),
            .beginDictation,
            "a completed tap should request a dictation session"
        )
        rejectedTap.rejectDictationStart()
        _ = rejectedTap.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            rejectedTap.handle(flags(exact: false, anyTriggerDown: false)),
            .beginDictation,
            "a rejected tap should re-arm immediately instead of consuming the next tap"
        )
    }

    static func testSuccessfulControllerFlow() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let polisher = FakePolisher(log: log, behavior: .polish("  polished dictation  "))
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            polisher: polisher,
            inserter: inserter,
            audioPolicy: DictationAudioPolicy(minimumDuration: 0.10)
        )

        await controller.hotKeyUp()
        assertEqual(await controller.state, .idle, "controller should ignore unmatched key-up")

        await controller.hotKeyDown()
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "controller should begin listening")
        assertEqual(await target.captures, 1, "repeated key-down must not recapture a target")
        assertEqual(await audio.starts, 1, "repeated key-down must not restart audio")
        assertEqual(
            Array((await log.snapshot()).prefix(3)),
            ["target", "permission", "start"],
            "the text target must be captured before permission and audio startup"
        )

        await controller.hotKeyUp()
        await waitForState(
            .succeeded("polished dictation"),
            controller: controller,
            message: "the full dictation pipeline should succeed"
        )
        assertEqual(await transcriber.calls, 1, "normal audio should be transcribed once")
        assertEqual(await polisher.calls, 1, "normal audio should be polished once")
        assertEqual(await inserter.insertionCount(), 1, "the transcript should be inserted once")
        assertEqual(
            await log.snapshot(),
            ["target", "permission", "start", "stop", "transcribe", "polish", "insert"],
            "polishing must run after transcription and before insertion"
        )
    }

    static func testStartupReleaseFinishesAfterCaptureStarts() async {
        let log = EventLog()
        let audio = GatedAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let polisher = FakePolisher(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: polisher,
            inserter: inserter
        )

        await controller.hotKeyDown()
        for _ in 0..<100 where !(await audio.isWaiting()) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let audioIsWaiting = await audio.isWaiting()
        assertCondition(audioIsWaiting, "audio startup should be gated before key-up")
        await controller.hotKeyUp()
        assertEqual(
            await controller.state,
            .requestingPermission,
            "startup key-up should be latched without cancelling the pending session"
        )

        await audio.releaseStart()
        await waitForState(
            .succeeded("locally transcribed"),
            controller: controller,
            message: "latched startup release should finish after capture starts"
        )
        assertEqual(await audio.starts, 1, "latched startup release must not restart capture")
        assertEqual(await audio.stops, 1, "latched startup release should stop capture exactly once")
        assertEqual(await transcriber.calls, 1, "latched startup release should transcribe exactly once")
        assertEqual(await inserter.insertionCount(), 1, "latched startup release should insert exactly once")
        assertEqual(
            await log.snapshot(),
            ["target", "permission", "start-waiting", "start", "stop", "transcribe", "polish", "insert"],
            "latched startup release should replay through the normal finish pipeline once"
        )
    }

    static func testStartupReleaseLatchResetsOnCancel() async {
        let log = EventLog()
        let audio = GatedAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: FakePolisher(log: log),
            inserter: inserter
        )

        await controller.hotKeyDown()
        for _ in 0..<100 where !(await audio.isWaiting()) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        await controller.hotKeyUp()
        await controller.cancel()
        await audio.releaseStart()
        await waitForState(.idle, controller: controller, message: "cancelled startup release should return idle")
        for _ in 0..<100 where await audio.cancellations == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        assertEqual(await audio.stops, 0, "cancelled startup release must not stop as a finished recording")
        assertEqual(await transcriber.calls, 0, "cancelled startup release must not transcribe")
        assertEqual(await inserter.insertionCount(), 0, "cancelled startup release must not insert")

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "new session should not inherit old latch")
        assertEqual(await audio.stops, 0, "new session should remain listening until its own key-up")
        await controller.hotKeyUp()
        await waitForState(
            .succeeded("locally transcribed"),
            controller: controller,
            message: "new session should finish normally after its own release"
        )
        assertEqual(await audio.stops, 1, "only the new session should stop")
        assertEqual(await transcriber.calls, 1, "only the new session should transcribe")
    }

    static func testStartupReleaseLatchResetsOnFailure() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FailingTargetProvider(),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: FakePolisher(log: log),
            inserter: inserter
        )

        await controller.hotKeyDown()
        await controller.hotKeyUp()
        await waitForState(
            .error(.targetUnavailable("Enable the required permission in System Settings.")),
            controller: controller,
            message: "startup failure should still surface the target error"
        )
        assertEqual(await audio.starts, 0, "failed startup should not begin capture")
        assertEqual(await transcriber.calls, 0, "failed startup should not consume the latched release")
        assertEqual(await inserter.insertionCount(), 0, "failed startup should not insert")
    }

    static func testPolishingFallbacks() async {
        for (behavior, label) in [
            (FakePolisher.Behavior.fail, "an unavailable polisher"),
            (FakePolisher.Behavior.polish("   "), "an empty polisher result"),
        ] {
            let log = EventLog()
            let inserter = FakeInserter(log: log)
            let controller = DictationController(
                targetProvider: FakeTargetProvider(log: log),
                audioCapture: FakeAudioCapture(log: log),
                transcriber: FakeTranscriber(log: log),
                polisher: FakePolisher(log: log, behavior: behavior),
                inserter: inserter
            )

            await controller.hotKeyDown()
            await waitForState(.listening, controller: controller, message: "\(label) should begin listening")
            await controller.hotKeyUp()
            await waitForState(
                .succeeded("locally transcribed"),
                controller: controller,
                message: "\(label) should preserve the normalized raw transcript"
            )
            assertEqual(
                await inserter.insertionCount(),
                1,
                "\(label) should still insert text"
            )
        }
    }

    static func testEmptyModelOutputUsesDistinctFailure() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log, behavior: .fixed(" \n\t "))
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: FakePolisher(log: log),
            inserter: inserter,
            audioPolicy: DictationAudioPolicy(minimumDuration: 0.10)
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "empty-output session should listen")
        await controller.hotKeyUp()
        await waitForState(
            .error(.transcriptionReturnedNoText),
            controller: controller,
            message: "empty model output should be distinct from short or missing audio"
        )
        assertEqual(await transcriber.calls, 1, "policy-approved audio should still call the transcriber")
        assertEqual(await inserter.insertionCount(), 0, "empty model output must not insert text")
        let events = await log.snapshot()
        assertCondition(
            events.contains("transcribe"),
            "empty model output failure should happen after transcription"
        )
    }

    static func testShortcutEventOrdering() async {
        let log = EventLog()
        let queue = DictationShortcutEventQueue { event in
            if case .keyDown = event {
                try? await Task.sleep(for: .milliseconds(20))
                await log.append("down")
            } else if case .keyUp = event {
                await log.append("up")
            }
        }
        queue.send(.keyDown)
        queue.send(.keyUp)
        await queue.drain()
        assertEqual(
            await log.snapshot(),
            ["down", "up"],
            "the production shortcut adapter must preserve a rapid down/up sequence"
        )
    }

    static func testTargetCapturedBeforeHUDStatePublication() async {
        let log = EventLog()
        let target = GatedTargetProvider()
        let recorder = StateRecorder()
        let controller = DictationController(
            targetProvider: target,
            audioCapture: FakeAudioCapture(log: log),
            transcriber: FakeTranscriber(log: log),
            polisher: FakePolisher(log: log),
            inserter: FakeInserter(log: log),
            stateObserver: { recorder.record($0) }
        )

        await controller.hotKeyDown()
        for _ in 0..<100 where !(await target.isWaiting()) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let targetIsWaiting = await target.isWaiting()
        assertCondition(targetIsWaiting, "target capture should be in flight")
        assertEqual(
            await controller.state,
            .requestingPermission,
            "the reducer should track the pending request internally"
        )
        assertCondition(
            recorder.snapshot().isEmpty,
            "the HUD observer must not run before the focused destination is captured"
        )

        await target.release()
        await waitForState(.listening, controller: controller, message: "capture should continue after target resolution")
        assertEqual(
            recorder.snapshot().first,
            .requestingPermission,
            "the checking-permissions HUD may appear once the target is safe"
        )
        await controller.cancel()
    }

    static func testShortAudioAndCancellation() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let polisher = FakePolisher(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            polisher: polisher,
            inserter: inserter,
            audioPolicy: DictationAudioPolicy(minimumDuration: 0.10)
        )

        await audio.setAudio(DictationAudio(samples: Array(repeating: 0, count: 800)))
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "short-audio session should listen")
        await controller.hotKeyUp()
        await waitForState(.idle, controller: controller, message: "short audio should return to idle")
        assertEqual(await transcriber.calls, 0, "short audio must not invoke the model")
        assertEqual(await inserter.insertionCount(), 0, "short audio must not insert text")

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "second session should listen")
        await controller.terminate()
        await waitForState(.idle, controller: controller, message: "termination should return to idle")
        for _ in 0..<100 {
            if await audio.cancellations > 0, await polisher.cancellations > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let cancellationCount = await audio.cancellations
        let polisherCancellationCount = await polisher.cancellations
        assertCondition(cancellationCount > 0, "termination should cancel active audio")
        assertCondition(
            polisherCancellationCount > 0,
            "termination should cancel the polisher alongside audio and transcription"
        )
    }

    static func testRapidCancelThenRestart() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let polisher = FakePolisher(log: log)
        let inserter = FakeInserter(log: log)
        await audio.setCancellationDelay(.milliseconds(60))
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            polisher: polisher,
            inserter: inserter
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "first rapid-restart session should listen")
        await controller.cancel()
        await controller.hotKeyDown()
        try? await Task.sleep(for: .milliseconds(15))
        assertEqual(await audio.starts, 1, "a replacement session must wait for prior teardown")
        assertEqual(await controller.state, .requestingPermission, "replacement should remain queued during teardown")
        await waitForState(.listening, controller: controller, message: "replacement should start after teardown")
        assertEqual(await audio.starts, 2, "replacement capture should start exactly once")
        await controller.cancel()
    }

    static func testTranscriptionTeardownBeforeRestart() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = TeardownAwareTranscriber()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: FakePolisher(log: log),
            inserter: FakeInserter(log: log)
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "first teardown session should listen")
        await controller.hotKeyUp()
        for _ in 0..<100 where await transcriber.activeCount() == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        assertEqual(await transcriber.activeCount(), 1, "first inference should be active before cancellation")

        await controller.cancel()
        await controller.hotKeyDown()
        await waitForState(
            .listening,
            controller: controller,
            message: "replacement capture should start while the old inference unwinds"
        )
        assertEqual(await audio.starts, 2, "replacement capture must not wait for inference teardown")
        await controller.hotKeyUp()
        await waitForState(
            .succeeded("replacement transcript"),
            controller: controller,
            message: "replacement should transcribe after teardown"
        )
        assertEqual(
            await transcriber.maximumConcurrentCount(),
            1,
            "cancel and immediate restart must never overlap inference"
        )
    }

    static func testPolishingTeardownBeforeRestart() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let polisher = TeardownAwarePolisher()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: FakeTranscriber(log: log),
            polisher: polisher,
            inserter: FakeInserter(log: log)
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "first polishing session should listen")
        await controller.hotKeyUp()
        for _ in 0..<100 where await polisher.activeCount() == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        assertEqual(await polisher.activeCount(), 1, "first polish should be active before cancellation")

        await controller.cancel()
        await controller.hotKeyDown()
        await waitForState(
            .listening,
            controller: controller,
            message: "replacement capture should start while the old polish unwinds"
        )
        assertEqual(await audio.starts, 2, "replacement capture must not wait for polish teardown")
        var polisherCancellationCount = await polisher.cancellationCount()
        for _ in 0..<100 where polisherCancellationCount == 0 {
            try? await Task.sleep(for: .milliseconds(2))
            polisherCancellationCount = await polisher.cancellationCount()
        }
        assertCondition(
            polisherCancellationCount > 0,
            "cancellation cleanup must cancel the active polisher"
        )
        await controller.hotKeyUp()
        await waitForState(
            .succeeded("replacement polished transcript"),
            controller: controller,
            message: "replacement should polish only after the previous request exits"
        )
        assertEqual(
            await polisher.maximumConcurrentCount(),
            1,
            "cancel and immediate restart must never overlap polishing requests"
        )
    }

    static func testWatchdogAndLocalizedErrors() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let polisher = FakePolisher(log: log)
        let inserter = FakeInserter(log: log)
        let watchdogController = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            polisher: polisher,
            inserter: inserter,
            maximumCaptureDuration: .milliseconds(25)
        )
        await watchdogController.hotKeyDown()
        await waitForState(.listening, controller: watchdogController, message: "watchdog session should listen")
        await waitForState(.idle, controller: watchdogController, message: "watchdog should stop a lost-key-up session")
        for _ in 0..<100 where await audio.cancellations == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let watchdogCancellations = await audio.cancellations
        assertCondition(watchdogCancellations > 0, "watchdog expiry should tear down microphone capture")

        let failingController = DictationController(
            targetProvider: FailingTargetProvider(),
            audioCapture: FakeAudioCapture(log: EventLog()),
            transcriber: FakeTranscriber(log: EventLog()),
            polisher: FakePolisher(log: EventLog()),
            inserter: FakeInserter(log: EventLog())
        )
        await failingController.hotKeyDown()
        await waitForState(
            .error(.targetUnavailable("Enable the required permission in System Settings.")),
            controller: failingController,
            message: "localized target errors should reach the HUD verbatim"
        )
    }
}
