import Foundation
import AVFoundation

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

actor FailingPreparationTranscriber: LocalDictationTranscribing {
    func prepare() async throws {
        throw DictationModelPreparationError.insufficientStorage
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        throw DictationModelPreparationError.insufficientStorage
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

actor FollowingTargetProvider: DictationTargetCapturing {
    typealias Target = String
    private let phrases: [String?]
    private let failures: [Int: DictationFailure]
    private var gateOrdinal: Int?
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var captures = 0
    private(set) var additionalCaptures = 0

    init(_ phrases: [String?], gateOrdinal: Int? = nil, failures: [Int: DictationFailure] = [:]) {
        self.phrases = phrases
        self.gateOrdinal = gateOrdinal
        self.failures = failures
    }

    func captureTarget() async throws -> String {
        captures += 1
        return "initial-field"
    }

    func captureAdditionalTarget() async throws -> String {
        additionalCaptures += 1
        let ordinal = additionalCaptures
        if ordinal == gateOrdinal {
            await withCheckedContinuation { gate = $0 }
        }
        if let failure = failures[ordinal] { throw failure }
        guard let target = phrases[ordinal - 1] else { throw FriendlyTargetError() }
        return target
    }

    nonisolated func destinationIdentifier(for target: String) -> String? {
        String(target.split(separator: "#")[0])
    }

    func isWaiting() -> Bool { gate != nil }
    func releaseCapture() {
        gate?.resume()
        gate = nil
        gateOrdinal = nil
    }
}

final class RecoveryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func record(_ text: String) { lock.withLock { self.text = text } }
    func snapshot() -> String { lock.withLock { text } }
}

actor ContinuousAudioCapture: DictationAudioCapturing {
    private var continuation: AsyncThrowingStream<DictationAudio, Error>.Continuation?
    private var startupContinuation: CheckedContinuation<Void, Never>?
    private var startupIsGated = false
    private var promotionIsGated = false
    private var promotionContinuation: CheckedContinuation<Void, Never>?
    private var tail: DictationAudio?
    private var permissionGranted = true
    private var permissionFailure: DictationMicrophoneAuthorizationFailure?
    private var permissionGate: CheckedContinuation<Void, Never>?
    private var permissionIsGated = false
    private(set) var permissionRequests = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancellations = 0
    private(set) var pauseDuration: TimeInterval?

    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        if permissionIsGated { await withCheckedContinuation { permissionGate = $0 } }
        if let permissionFailure { throw permissionFailure }
        return permissionGranted
    }
    func setPermission(_ granted: Bool) { permissionGranted = granted }
    func setPermissionFailure(_ failure: DictationMicrophoneAuthorizationFailure?) { permissionFailure = failure }
    func gatePermission() { permissionIsGated = true }
    func permissionWaiting() -> Bool { permissionGate != nil }
    func releasePermission() {
        permissionIsGated = false
        permissionGate?.resume()
        permissionGate = nil
    }
    func startCapture() async throws { starts += 1 }
    func stopCapture() async throws -> DictationAudio { Self.audio(2) }

    func startContinuousCapture(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        starts += 1
        self.pauseDuration = pauseDuration
        let stream = AsyncThrowingStream<DictationAudio, Error> { continuation = $0 }
        if startupIsGated {
            await withCheckedContinuation { startupContinuation = $0 }
        }
        return stream
    }

    func promoteCaptureToContinuous(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        self.pauseDuration = pauseDuration
        let stream = AsyncThrowingStream<DictationAudio, Error> { continuation = $0 }
        if promotionIsGated {
            await withCheckedContinuation { promotionContinuation = $0 }
        }
        return stream
    }

    func gatePromotion() { promotionIsGated = true }
    func isPromotionWaiting() -> Bool { promotionContinuation != nil }
    func releasePromotion() {
        promotionContinuation?.resume()
        promotionContinuation = nil
    }

    func stopContinuousCapture() async throws {
        stops += 1
        if let tail {
            continuation?.yield(tail)
            self.tail = nil
        }
        continuation?.finish()
        continuation = nil
    }

    func cancelCapture() async {
        cancellations += 1
        continuation?.finish()
        continuation = nil
        tail = nil
    }

    func emit(_ ordinal: Int) { continuation?.yield(Self.audio(ordinal)) }
    func emit(_ audio: DictationAudio) { continuation?.yield(audio) }
    func fail() { continuation?.finish(throwing: DictationContinuousCaptureError.bufferOverflow) }
    func setTail(_ ordinal: Int) { tail = Self.audio(ordinal) }
    func setTail(_ audio: DictationAudio) { tail = audio }
    func gateStartup() { startupIsGated = true }
    func startupWaiting() -> Bool { startupContinuation != nil }
    func releaseStartup() {
        startupIsGated = false
        startupContinuation?.resume()
        startupContinuation = nil
    }

    static func audio(_ ordinal: Int) -> DictationAudio {
        DictationAudio(samples: Array(repeating: Float(ordinal), count: 3_200))
    }
}

actor ContinuousTranscriber: LocalDictationTranscribing {
    private var gate: CheckedContinuation<Void, Never>?
    private var shouldGateFirst: Bool
    private var firstReleased = false
    private var transcripts: [String]
    private(set) var ordinals: [Int] = []
    private(set) var cancellations = 0
    private var active = 0
    private(set) var maximumActive = 0

    init(_ transcripts: [String], gateFirst: Bool = false) {
        self.transcripts = transcripts
        shouldGateFirst = gateFirst
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        let ordinal = Int(audio.samples.first ?? 0)
        ordinals.append(ordinal)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if ordinals.count == 1, shouldGateFirst, !firstReleased {
            await withCheckedContinuation { gate = $0 }
        }
        return transcripts[ordinal - 1]
    }

    func cancelTranscription() async {
        cancellations += 1
        while active > 0 { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func isWaiting() -> Bool { gate != nil }
    func releaseFirst() {
        firstReleased = true
        gate?.resume()
        gate = nil
    }
}

actor RetainedInserter: DictationTextInserting {
    typealias Target = String
    private(set) var chunks: [String] = []
    private(set) var targets: [String] = []
    private(set) var retainedInsertions = 0
    private(set) var releases: [String] = []
    private var failInsertion = false
    private var rejectedTargets: Set<String> = []
    private var releaseIsGated = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func insert(_ text: String, into target: String) async throws {
        if failInsertion || rejectedTargets.contains(target) { throw FriendlyTargetError() }
        chunks.append(text)
        targets.append(target)
    }

    func insertRetainingTarget(_ text: String, into target: String) async throws {
        retainedInsertions += 1
        try await insert(text, into: target)
    }

    func releaseTarget(_ target: String) async {
        releases.append(target)
        if releaseIsGated {
            releaseIsGated = false
            await withCheckedContinuation { releaseContinuation = $0 }
        }
    }
    func gateRelease() { releaseIsGated = true }
    func isReleaseWaiting() -> Bool { releaseContinuation != nil }
    func releaseAcknowledgement() {
        releaseIsGated = false
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
    func setFailure() { failInsertion = true }
    func rejectTarget(_ target: String) { rejectedTargets.insert(target) }
}

func waitForCondition(_ message: String, _ condition: @escaping () async -> Bool) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    fputs("Assertion failed: \(message)\n", stderr)
    exit(1)
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
        testShortcutSessionRearming()
        testEventTapRecoveryPolicy()
        testEventTapStartRequestPolicy()
        testShortcutSessionGate()
        testAudioNormalization()
        testAudioLevelMeter()
        await testShortcutEventOrdering()
        await testTargetCapturedBeforeHUDStatePublication()
        await testSuccessfulControllerFlow()
        await testModelPreparationFailureMessage()
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
        testVoiceLockPreservesBufferedAudio()
        await testVoiceLockDoesNotWaitForTargetRelease()
        await testQueuedCommandsDuringVoiceLockPromotion()
        await testFinishDuringVoiceLockPromotion()
        await testFailedPendingVoiceLockCanRestart()
        await testDuplicateVoiceStartDuringTargetCapture()
        await testVoiceLockDuringStartup()
        await testHoldToVoiceLockPromotion()
        await testContinuousOrderedChunksAndStopTail()
        await testFloatingFinishForSingleUtterance()
        await testContinuousForcedSplitTail()
        await testContinuousSpacingAndPolishingFallback()
        await testContinuousCancellationAndCrossModeRestart()
        await testContinuousOverflowAndFailureTeardown()
        await testContinuousStartupStopAndCancel()
        await testContinuousSessionLimit()
        await testVoicePauseResumeAndFinish()
        await testRevokedMicrophoneBlocksVoiceResume()
        await testCanceledPendingPermissionCannotStartCapture()
        await testPermissionFailurePreservesRepairAction()
        await testVoiceStartupIntents()
        await testFollowFocusCapturesBeforeInferenceAndSpacesPerField()
        await testFollowFocusCancellationReleasesAllTargets()
        await testFollowFocusLateTargetCancellation()
        await testFollowFocusRecoveryKeepsListening()
        await testSecurePhraseStopsBeforeInference()
        await testSecurePhraseDrainsAcceptedSafeJobs()
        await testRecoveryBudgetFinishesAndDrains()
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
        DictationActivationMode.voiceMode.save(in: defaults)
        let savedVoiceMode = DictationActivationMode.saved(in: defaults)
        var voice = DictationModifierShortcutStateMachine(mode: savedVoiceMode)
        assertEqual(voice.handle(flags(exact: true, anyTriggerDown: true)), .none, "saved Voice mode should wait for chord release")
        assertEqual(voice.handle(flags(exact: false, anyTriggerDown: false)), .beginDictation, "saved Voice mode should activate on a clean tap")
        assertEqual(voice.state, .active, "Voice mode should keep recording after chord release")
        assertEqual(voice.handle(.keyDown), .none, "typing must keep persistent voice mode active")
        assertEqual(voice.handle(flags(exact: false, anyTriggerDown: false, disallowed: true)), .none, "Shift must not cancel voice mode")
        assertEqual(voice.recoverGesture(), .none, "event tap recovery must retain persistent voice mode")
        assertEqual(voice.state, .active, "event tap recovery must preserve the Stop gesture")
        _ = voice.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(voice.handle(.keyDown), .none, "typing a Control Option shortcut must disqualify Stop without cancelling voice")
        assertEqual(voice.handle(flags(exact: false, anyTriggerDown: false)), .none, "a contaminated Stop tap must leave voice active")
        _ = voice.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(voice.handle(flags(exact: false, anyTriggerDown: false)), .finishDictation, "Voice mode should Stop on a second clean tap")
        var adopted = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        adopted.adoptVoiceModeSession()
        _ = adopted.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(adopted.handle(flags(exact: false, anyTriggerDown: false)), .none, "releasing modifiers must preserve a workspace-started locked session")
        assertEqual(adopted.toggleVoiceLock(), .finishDictation, "Space on the held chord must finish a workspace-started session")
        var rejectedLock = DictationModifierShortcutStateMachine()
        _ = rejectedLock.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(rejectedLock.toggleVoiceLock(), .beginVoiceMode, "fast Space must request a locked start")
        rejectedLock.rejectDictationStart()
        assertEqual(rejectedLock.isVoiceLocked, false, "a rejected voice start must clear the phantom lock")
        _ = rejectedLock.handle(flags(exact: false, anyTriggerDown: false))
        assertEqual(rejectedLock.handle(flags(exact: true, anyTriggerDown: true)), .scheduleActivation, "a rejected lock must allow the next push-to-talk gesture")
        var lock = DictationModifierShortcutStateMachine()
        assertEqual(lock.handle(flags(exact: true, anyTriggerDown: true)), .scheduleActivation, "holding the chord must arm push to talk")
        assertEqual(lock.toggleVoiceLock(), .beginVoiceMode, "Space before activation must start locked voice mode directly")
        assertEqual(lock.handle(flags(exact: false, anyTriggerDown: false)), .none, "locked voice must survive modifier release")
        assertEqual(lock.handle(.keyDown), .none, "typing must not cancel locked voice")
        assertEqual(lock.recoverGesture(), .none, "event tap recovery must preserve voice lock")
        _ = lock.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(lock.toggleVoiceLock(), .finishDictation, "repeating the lock chord must finish")
        _ = lock.handle(flags(exact: false, anyTriggerDown: false))
        _ = lock.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(lock.handle(.activationDelayElapsed), .beginDictation, "the next plain hold must remain push to talk")
        assertEqual(lock.toggleVoiceLock(), .lockVoiceMode, "Space during a live hold must promote the current capture")
        assertEqual(lock.handle(flags(exact: false, anyTriggerDown: false)), .none, "promotion must suppress push-to-talk release")
        _ = lock.reset()
        assertEqual(lock.isVoiceLocked, false, "cancel must clear the lock")
        assertEqual(DictationShortcutStatePolicy.shouldRearm(after: .paused), false, "pause must retain the active Stop gesture")
        assertEqual(DictationShortcutStatePolicy.shouldRearm(after: .pausing), false, "pause drain must retain the active Stop gesture")
        assertEqual(DictationPauseDuration.saved(in: defaults).seconds, 0.9, "missing pause preference should use natural pauses")
        defaults.set("relaxed", forKey: DictationPauseDuration.defaultsKey)
        assertEqual(DictationPauseDuration.saved(in: defaults).seconds, 1.5, "pause duration should read the saved preference")
    }

    static func testShortcutSessionRearming() {
        let down = DictationModifierShortcutStateMachine.Event.flagsChanged(
            isExactChord: true, anyTriggerModifierDown: true, hasDisallowedModifiers: false
        )
        let up = DictationModifierShortcutStateMachine.Event.flagsChanged(
            isExactChord: false, anyTriggerModifierDown: false, hasDisallowedModifiers: false
        )
        for mode in DictationActivationMode.allCases {
            var shortcut = DictationModifierShortcutStateMachine(mode: mode)
            _ = shortcut.handle(down)
            let start = shortcut.handle(mode == .holdToTalk ? .activationDelayElapsed : up)
            assertEqual(start, .beginDictation, "replacement gesture must begin a session")
            if DictationShortcutStatePolicy.shouldRearm(after: .idle, isStartingShortcut: true) {
                shortcut.rejectDictationStart()
            }
            if mode != .holdToTalk { _ = shortcut.handle(down) }
            assertEqual(shortcut.handle(up), .finishDictation, "restart's idle notification must preserve the replacement Stop gesture")

            for terminal in [DictationState.idle, .error(.transcriptionReturnedNoText), .succeeded("finished")] {
                _ = shortcut.handle(down)
                _ = shortcut.handle(mode == .holdToTalk ? .activationDelayElapsed : up)
                if DictationShortcutStatePolicy.shouldRearm(after: terminal) {
                    shortcut.rejectDictationStart()
                }
                assertEqual(shortcut.state, .idle, "terminal failure and success must rearm the shortcut")
                _ = shortcut.handle(down)
                assertEqual(shortcut.handle(mode == .holdToTalk ? .activationDelayElapsed : up), .beginDictation, "a fresh gesture must start after a terminal result")
                _ = shortcut.reset()
            }
        }
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

    static func testModelPreparationFailureMessage() async {
        let log = EventLog()
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: FakeAudioCapture(log: log),
            transcriber: FailingPreparationTranscriber(),
            polisher: FakePolisher(log: log),
            inserter: inserter
        )
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "recording should retain its normal lifecycle")
        await controller.hotKeyUp()
        let message = DictationModelPreparationError.insufficientStorage.localizedDescription
        await waitForState(.error(.transcriptionFailed(message)), controller: controller,
                           message: "the existing recording error state should show the model storage failure")
        assertEqual(await inserter.insertionCount(), 0, "a failed model must never insert text")
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
            switch event {
            case .keyDown:
                try? await Task.sleep(for: .milliseconds(20))
                await log.append("down")
            case .keyUp: await log.append("up")
            case .startVoiceMode: await log.append("start voice")
            case .lockVoiceMode: await log.append("lock voice")
            case .pauseVoiceMode: await log.append("pause")
            case .resumeVoiceMode: await log.append("resume")
            case .finishVoiceMode: await log.append("finish")
            case .clearRecoveryText: await log.append("discard")
            case .cancel: await log.append("cancel")
            }
        }
        queue.send(.keyDown)
        queue.send(.keyUp)
        queue.send(.startVoiceMode)
        queue.send(.lockVoiceMode)
        queue.send(.pauseVoiceMode)
        queue.send(.resumeVoiceMode)
        queue.send(.finishVoiceMode)
        queue.send(.clearRecoveryText)
        queue.send(.cancel) { await log.append("cancel complete") }
        await queue.drain()
        assertEqual(
            await log.snapshot(),
            ["down", "up", "start voice", "lock voice", "pause", "resume", "finish", "discard", "cancel", "cancel complete"],
            "shortcut and workspace controls must preserve one ordered command sequence"
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
        await controller.cancel()
        await waitForState(.idle, controller: controller, message: "cancellation should return to idle")
        for _ in 0..<100 {
            if await audio.cancellations > 0, await polisher.cancellations > 0 {
                break
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let cancellationCount = await audio.cancellations
        let polisherCancellationCount = await polisher.cancellations
        assertCondition(cancellationCount > 0, "cancellation should cancel active audio")
        assertCondition(
            polisherCancellationCount > 0,
            "cancellation should cancel the polisher alongside audio and transcription"
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

        struct DeniedTarget: DictationTargetCapturing {
            func captureTarget() async throws -> String { throw DictationFailure.accessibilityPermissionDenied }
        }
        let deniedAudio = FakeAudioCapture(log: log)
        let deniedController = DictationController(
            targetProvider: DeniedTarget(), audioCapture: deniedAudio,
            transcriber: transcriber, polisher: polisher, inserter: inserter
        )
        await deniedController.hotKeyDown()
        await waitForState(.error(.accessibilityPermissionDenied), controller: deniedController, message: "permission failures must retain their type for the correct repair action")
        assertEqual(await deniedAudio.starts, 0, "denied Accessibility must fail before microphone capture")
    }
    static func testFloatingFinishForSingleUtterance() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log), audioCapture: audio,
            transcriber: FakeTranscriber(log: log), polisher: FakePolisher(log: log), inserter: inserter
        )
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "single-utterance session must listen")
        await controller.finishVoiceMode()
        await waitForState(.succeeded("locally transcribed"), controller: controller, message: "floating Finish must stop a single-utterance session")
        await controller.hotKeyUp()
        assertEqual(await audio.stops, 1, "a later physical release must not stop capture twice")
        assertEqual(await inserter.insertions.map { $0.0 }, ["locally transcribed"], "floating Finish must insert the batch transcript once")
    }

    static func testVoiceLockPreservesBufferedAudio() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
        buffer.frameLength = 4_800
        let held = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        let locked = LockedContinuousSampleAccumulator(
            channelCount: 1,
            segmenter: try! DictationUtteranceSegmenter(sampleRate: 48_000, pauseDuration: 0.9),
            levelObserver: { _ in }
        )
        buffer.floatChannelData![0].initialize(repeating: 0.1, count: 4_800)
        held.append(buffer)
        try! held.promote(to: locked)
        buffer.floatChannelData![0].update(repeating: 0.2, count: 4_800)
        held.append(buffer)
        let preserved = try! locked.finish().flatMap { $0 }
        assertEqual(preserved, Array(repeating: Float(0.1), count: 4_800) + Array(repeating: Float(0.2), count: 4_800), "promotion must preserve all buffered audio and route later buffers in order")
        assertCondition(held.drain().isEmpty, "promotion must transfer ownership of the held audio")
        let pausedHold = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        let pausedLock = LockedContinuousSampleAccumulator(
            channelCount: 1,
            segmenter: try! DictationUtteranceSegmenter(sampleRate: 48_000, pauseDuration: 0.1),
            levelObserver: { _ in }
        )
        for _ in 0..<6 {
            buffer.floatChannelData![0].update(repeating: 0.1, count: 4_800)
            pausedHold.append(buffer)
            pausedHold.append(buffer)
            buffer.floatChannelData![0].update(repeating: 0, count: 4_800)
            pausedHold.append(buffer)
        }
        try! pausedHold.promote(to: pausedLock)
        let priorPhrases = try! pausedLock.finish().flatMap { $0 }
        assertEqual(priorPhrases.filter { $0 == 0.1 }.count, 6 * 9_600, "locking after many paused phrases must not overflow or lose prior speech")
    }

    static func testVoiceLockDoesNotWaitForTargetRelease() async {
        let audio = ContinuousAudioCapture()
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: ContinuousTranscriber(["tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await inserter.gateRelease()
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "hold must start before slow target release")
        _ = await controller.lockVoiceMode(pauseDuration: 0.9)
        await waitForCondition("initial target release must be waiting") { await inserter.isReleaseWaiting() }
        await audio.setTail(1)
        await controller.finishVoiceMode()
        await waitForState(.succeeded("tail"), controller: controller, message: "Finish must not wait for an obsolete target release acknowledgement")
        assertEqual(await audio.stops, 1, "slow lease cleanup must not keep the microphone running")
        await inserter.releaseAcknowledgement()
    }

    static func testQueuedCommandsDuringVoiceLockPromotion() async {
        for shouldCancel in [true, false] {
            let audio = ContinuousAudioCapture()
            let inserter = RetainedInserter()
            let log = EventLog()
            let controller = DictationController(
                targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
                transcriber: ContinuousTranscriber(["tail"]),
                polisher: FakePolisher(log: EventLog()), inserter: inserter
            )
            await audio.gatePromotion()
            await controller.hotKeyDown()
            await waitForState(.listening, controller: controller, message: "hold must start before queued lock")
            let queue = DictationShortcutEventQueue { event in
                switch event {
                case .lockVoiceMode: _ = await controller.lockVoiceMode(pauseDuration: 0.9)
                case .cancel:
                    await controller.cancel()
                    await log.append("cancel accepted")
                case .finishVoiceMode:
                    await controller.finishVoiceMode()
                    await log.append("finish accepted")
                default: break
                }
            }
            queue.send(.lockVoiceMode)
            await waitForCondition("queued lock must begin promotion") { await audio.isPromotionWaiting() }
            await audio.setTail(1)
            queue.send(shouldCancel ? .cancel : .finishVoiceMode)
            await waitForCondition("Cancel and Finish must be admitted while promotion is suspended") {
                !(await log.snapshot()).isEmpty
            }
            if shouldCancel {
                assertEqual(await controller.state, .idle, "queued Cancel must immediately clear the old session")
            }
            await queue.drain()
            await audio.releasePromotion()
            if shouldCancel {
                await waitForCondition("cancelled promotion must clean up the microphone") { await audio.cancellations == 1 }
                assertEqual(await inserter.chunks, [], "cancelled promotion must not insert stale audio")
            } else {
                await waitForState(.succeeded("tail"), controller: controller, message: "queued Finish must drain after promotion settles")
                assertEqual(await audio.stops, 1, "queued Finish must stop the microphone once")
            }
        }
    }

    static func testFinishDuringVoiceLockPromotion() async {
        let audio = ContinuousAudioCapture()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: ContinuousTranscriber(["tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: RetainedInserter()
        )
        await audio.gatePromotion()
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "hold must start before gated promotion")
        let promotion = Task { await controller.lockVoiceMode(pauseDuration: 0.9) }
        await waitForCondition("promotion must be gated") { await audio.isPromotionWaiting() }
        await audio.setTail(1)
        await controller.finishVoiceMode()
        assertEqual(await audio.stops, 0, "Finish must wait for promotion to settle before stopping")
        await audio.releasePromotion()
        assertEqual(await promotion.value, true, "promotion must retain the pending Finish intent")
        await waitForState(.succeeded("tail"), controller: controller, message: "Finish during promotion must drain successfully")
        assertEqual(await audio.stops, 1, "pending Finish must stop continuous capture exactly once")
    }

    static func testFailedPendingVoiceLockCanRestart() async {
        let target = GatedTargetProvider()
        let audio = ContinuousAudioCapture()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber(["tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: RetainedInserter()
        )
        await audio.setPermission(false)
        await controller.hotKeyDown()
        await waitForCondition("failed pending-lock target must be gated") { await target.isWaiting() }
        _ = await controller.lockVoiceMode(pauseDuration: 0.9)
        await target.release()
        await waitForState(.error(.microphonePermissionDenied), controller: controller, message: "pending lock must surface permission denial")
        assertEqual(await controller.isVoiceModeActive, false, "failed startup must clear pending voice intent")
        await audio.setPermission(true)
        assertEqual(await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus), true, "a failed pending lock must admit a fresh session")
        await waitForState(.listening, controller: controller, message: "fresh voice session must actually start")
        assertEqual(await audio.starts, 1, "restart must create its microphone instead of adopting stale intent")
        await controller.cancel()
    }

    static func testDuplicateVoiceStartDuringTargetCapture() async {
        for startsAsHold in [false, true] {
            let target = GatedTargetProvider()
            let audio = ContinuousAudioCapture()
            let inserter = RetainedInserter()
            let controller = DictationController(
                targetProvider: target, audioCapture: audio,
                transcriber: ContinuousTranscriber(["tail"]),
                polisher: FakePolisher(log: EventLog()), inserter: inserter
            )
            assertEqual(await controller.hotKeyDown(mode: startsAsHold ? .singleUtterance : .continuous, targetPolicy: .followFocus), true, "first start must be admitted")
            await waitForCondition("initial target must still be pending") { await target.isWaiting() }
            if startsAsHold {
                assertEqual(await controller.lockVoiceMode(pauseDuration: 0.9), true, "Space must admit a pending voice lock")
                assertEqual(await controller.isVoiceModeActive, true, "a pending hold-to-voice lock is an admitted voice session")
            }
            assertEqual(await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus), true, "duplicate voice Start must preserve the already admitted session")
            assertEqual(await audio.starts, 0, "duplicate admission must not start a second microphone")
            await target.release()
            await waitForState(.listening, controller: controller, message: "the original voice start must complete")
            await audio.setTail(1)
            await controller.hotKeyUp()
            await waitForState(.succeeded("tail"), controller: controller, message: "the accepted finish gesture must still stop the original session")
            assertEqual(await audio.starts, 1, "idempotent voice Start must open only one capture")
            assertEqual(await audio.stops, 1, "idempotent voice Start must retain one finish")
        }
    }

    static func testVoiceLockDuringStartup() async {
        for cancelDuringStartup in [false, true] {
            let target = GatedTargetProvider()
            let audio = ContinuousAudioCapture()
            let inserter = RetainedInserter()
            let controller = DictationController(
                targetProvider: target, audioCapture: audio,
                transcriber: ContinuousTranscriber(["pending lock"]),
                polisher: FakePolisher(log: EventLog()), inserter: inserter
            )
            await controller.hotKeyDown()
            await waitForCondition("target startup must be gated") { await target.isWaiting() }
            let queue = DictationShortcutEventQueue { event in
                if case .lockVoiceMode = event { _ = await controller.lockVoiceMode(pauseDuration: 0.9) }
                if case .cancel = event { await controller.cancel() }
            }
            queue.send(.lockVoiceMode)
            if cancelDuringStartup {
                queue.send(.cancel)
                await waitForCondition("Cancel must not wait behind pending lock startup") { await controller.state == .idle }
                await target.release()
                await queue.drain()
                assertEqual(await audio.starts, 0, "cancelled startup lock must never start the microphone")
            } else {
                await queue.drain()
                await target.release()
                await waitForCondition("pending lock must promote after startup") { await audio.pauseDuration == 0.9 }
                await audio.emit(1)
                await waitForCondition("pending lock must insert while continuing to listen") { await inserter.chunks == ["pending lock"] }
                assertEqual(await controller.state, .listening, "pending lock must stay active")
                await controller.cancel()
            }
        }
    }

    static func testHoldToVoiceLockPromotion() async {
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["locked phrase", "tail"])
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: transcriber, polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "push to talk must begin capture")
        assertEqual(await controller.isVoiceModeActive, false, "a batch hold must not be mistaken for an existing voice lock")
        assertEqual(await controller.lockVoiceMode(pauseDuration: 0.6), true, "a live hold must promote to continuous voice")
        assertEqual(await controller.isVoiceModeActive, true, "busy-start admission must preserve a live continuous session")
        await waitForCondition("accepted voice lock must complete audio promotion") { await audio.pauseDuration == 0.6 }
        assertEqual(await audio.starts, 1, "locking must not restart the microphone")
        await audio.emit(1)
        await waitForCondition("locked speech should insert between phrases") { await inserter.chunks.count == 1 }
        assertEqual(await controller.state, .listening, "locked voice must remain listening after insertion")
        await audio.setTail(2)
        await controller.finishVoiceMode()
        await waitForState(.succeeded("tail"), controller: controller, message: "finish must drain locked speech")
        assertEqual(await audio.stops, 1, "finishing a locked hold must stop capture exactly once")
        assertEqual(await inserter.chunks, ["locked phrase", "tail"], "locking must preserve ordered phrase insertion without assuming field identity")
    }

    static func testContinuousOrderedChunksAndStopTail() async {
        let target = FakeTargetProvider(log: EventLog())
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber([" first phrase ", "second phrase", "tail phrase"], gateFirst: true)
        let inserter = RetainedInserter()
        let recorder = StateRecorder()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter,
            stateObserver: { recorder.record($0) }
        )
        await controller.hotKeyDown(mode: .continuous, pauseDuration: 1.5)
        await waitForState(.listening, controller: controller, message: "continuous session should listen")
        await audio.emit(1)
        await waitForCondition("first continuous inference should be gated") { await transcriber.isWaiting() }
        await audio.emit(2)
        assertEqual(await controller.state, .listening, "live microphone must remain listening during inference")
        assertEqual(await controller.cancelIfTranscribing(), false, "batch transcription cancellation must ignore a live continuous session")
        await audio.setTail(3)
        await controller.hotKeyUp()
        await controller.hotKeyUp()
        await waitForCondition("Stop should flush capture once") { await audio.stops == 1 }
        assertEqual(await controller.state, .transcribing, "Stop must show processing until queued utterances drain")
        assertEqual(await controller.cancelIfTranscribing(), false, "batch cancellation must also ignore a draining continuous session")
        await transcriber.releaseFirst()
        await waitForState(.succeeded("tail phrase"), controller: controller, message: "Stop should drain every ordered chunk")
        assertEqual(await transcriber.ordinals, [1, 2, 3], "inference must preserve capture order including tail")
        assertEqual(await inserter.chunks, ["first phrase", " second phrase", " tail phrase"], "insertion must preserve literal ordered text with one separator")
        assertEqual(await inserter.targets, ["focused-field", "focused-field", "focused-field"], "every chunk must use the original destination")
        assertEqual(await inserter.retainedInsertions, 3, "continuous chunks must retain their target")
        assertEqual(await inserter.releases, ["focused-field"], "successful drain must release its destination once")
        assertEqual(await target.captures, 1, "continuous pauses must not recapture focus")
        assertEqual(await audio.pauseDuration, 1.5, "the selected pause duration must reach capture")
        assertEqual(await audio.stops, 1, "duplicate Stop must not flush the tail twice")
        assertEqual(await transcriber.maximumActive, 1, "continuous inference must be serial")
        assertCondition(!recorder.snapshot().contains(.succeeded("first phrase")), "a completed live chunk must not publish terminal success")
    }

    static func testContinuousForcedSplitTail() async {
        var segmenter = try! DictationUtteranceSegmenter(sampleRate: 16_000)
        let first = segmenter.append(samples: Array(repeating: Float(1), count: 320_000))
        assertEqual(first.map(\.count), [320_000], "sustained speech must split at the duration limit")
        assertEqual(segmenter.append(samples: Array(repeating: Float(2), count: 800)), [], "the short continuation must wait for Stop")
        let tail = segmenter.finish()
        assertEqual(tail.map(\.count), [800], "qualified speech must retain its short final continuation")
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["long phrase", "final word"])
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: transcriber, polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "forced-split session must listen")
        await audio.emit(DictationAudio(samples: first[0]))
        await audio.setTail(DictationAudio(samples: tail[0]))
        await controller.hotKeyUp()
        await waitForState(.succeeded("final word"), controller: controller, message: "Stop must transcribe the short continuation after the duration split")
        assertEqual(await transcriber.ordinals, [1, 2], "every qualified segment must reach transcription")
        assertEqual(await inserter.chunks, ["long phrase", " final word"], "duration splitting must preserve the last word")
    }

    static func testContinuousSpacingAndPolishingFallback() async {
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["Hello.", "Next", ", please", "你好", "世界", "Again"])
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: transcriber, polisher: FakePolisher(log: EventLog(), behavior: .fail),
            inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "spacing session should listen")
        for ordinal in 1...6 {
            await audio.emit(ordinal)
            await waitForCondition("spacing chunk should insert before next input") { await inserter.chunks.count == ordinal }
            assertEqual(await controller.state, .listening, "best-effort polish failure must keep the microphone live")
        }
        await controller.hotKeyUp()
        await waitForState(.succeeded("Again"), controller: controller, message: "spacing session should finish")
        assertEqual(await inserter.chunks, ["Hello.", " Next", ", please", "你好", "世界", "Again"], "punctuation and CJK boundaries must not gain an unwanted space")
        assertEqual(await inserter.releases, ["focused-field"], "spacing session should release its destination")
    }

    static func testContinuousCancellationAndCrossModeRestart() async {
        for initialMode in [DictationCaptureMode.continuous, .singleUtterance] {
            let audio = ContinuousAudioCapture()
            let transcriber = ContinuousTranscriber(["obsolete", "replacement"], gateFirst: true)
            let inserter = RetainedInserter()
            let controller = DictationController(
                targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
                transcriber: transcriber, polisher: FakePolisher(log: EventLog()), inserter: inserter
            )
            await controller.hotKeyDown(mode: initialMode)
            await waitForState(.listening, controller: controller, message: "old cross-mode session should listen")
            if initialMode == .continuous { await audio.emit(1) } else { await controller.hotKeyUp() }
            await waitForCondition("old cross-mode inference should block") { await transcriber.isWaiting() }
            await controller.cancel()
            let replacementMode: DictationCaptureMode = initialMode == .continuous ? .singleUtterance : .continuous
            await controller.hotKeyDown(mode: replacementMode)
            await waitForState(.listening, controller: controller, message: "replacement capture must start while old inference unwinds")
            assertEqual(await audio.starts, 2, "cross-mode replacement must begin capture before blocked inference exits")
            if replacementMode == .continuous { await audio.emit(2) }
            await controller.hotKeyUp()
            await waitForCondition("old inference cleanup should run before replacement inference") { await transcriber.cancellations == 1 }
            assertEqual(await transcriber.ordinals.count, 1, "replacement inference must wait for old cleanup")
            await transcriber.releaseFirst()
            await waitForState(.succeeded("replacement"), controller: controller, message: "replacement should insert after old cleanup exits")
            assertEqual(await inserter.chunks, ["replacement"], "cancellation must discard stale inference without affecting replacement")
            assertEqual(await transcriber.maximumActive, 1, "cross-mode restarts must not overlap inference")
            assertEqual(await audio.cancellations, 1, "obsolete cleanup must not cancel replacement capture")
            assertEqual(await inserter.releases, ["focused-field"], "the retained target must release once across cross-mode restart")
        }
    }

    static func testContinuousOverflowAndFailureTeardown() async {
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["one", "two", "three", "four", "five"], gateFirst: true)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: transcriber, polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "overflow session should listen")
        await audio.emit(1)
        await waitForCondition("overflow test should block first inference") { await transcriber.isWaiting() }
        for ordinal in 2...5 { await audio.emit(ordinal) }
        await waitForState(.error(.captureFailed("Dictation could not keep up. Stop and start again.")), controller: controller, message: "four pending chunks must fail the bounded queue")
        await waitForCondition("overflow must cancel microphone and release destination") {
            let cancellations = await audio.cancellations
            let releases = await inserter.releases
            return cancellations == 1 && releases == ["focused-field"]
        }
        await transcriber.releaseFirst()
        await waitForCondition("overflow should finish inference cleanup") { await transcriber.cancellations == 1 }
        assertEqual(await transcriber.ordinals, [1], "overflow must discard pending inference")
        assertEqual(await inserter.chunks, [], "overflow must discard the obsolete in-flight transcript")

        for failureKind in 0...2 {
            let failedAudio = ContinuousAudioCapture()
            let failedInserter = RetainedInserter()
            if failureKind == 1 { await failedInserter.setFailure() }
            let failedController = DictationController(
                targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: failedAudio,
                transcriber: ContinuousTranscriber([failureKind == 2 ? "  " : "word"]),
                polisher: FakePolisher(log: EventLog()), inserter: failedInserter
            )
            await failedController.hotKeyDown(mode: .continuous)
            await waitForState(.listening, controller: failedController, message: "failure session should listen")
            if failureKind == 0 { await failedAudio.fail() } else { await failedAudio.emit(1) }
            let expected: DictationState
            switch failureKind {
            case 0: expected = .error(.captureFailed("Dictation could not keep up. Stop and start again."))
            case 1: expected = .error(.insertionFailed("Enable the required permission in System Settings."))
            default: expected = .error(.transcriptionReturnedNoText)
            }
            await waitForState(expected, controller: failedController, message: "continuous failure must preserve its specific error")
            await waitForCondition("continuous failure must tear down capture and release target") {
                let cancellations = await failedAudio.cancellations
                let releases = await failedInserter.releases
                return cancellations == 1 && releases == ["focused-field"]
            }
            assertEqual(await failedInserter.chunks, [], "failed continuous chunks must not insert text")
        }
    }

    static func testContinuousStartupStopAndCancel() async {
        let audio = ContinuousAudioCapture()
        await audio.gateStartup()
        await audio.setTail(1)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: ContinuousTranscriber(["startup tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForCondition("continuous startup should be gated") { await audio.startupWaiting() }
        await controller.hotKeyUp()
        await controller.hotKeyUp()
        assertEqual(await controller.state, .requestingPermission, "startup Stop must latch until capture begins")
        await audio.releaseStartup()
        await waitForState(.succeeded("startup tail"), controller: controller, message: "startup Stop should flush the final phrase")
        assertEqual(await audio.stops, 1, "startup Stop must flush once")
        assertEqual(await inserter.chunks, ["startup tail"], "startup Stop must insert its tail once")
        assertEqual(await inserter.releases, ["focused-field"], "startup Stop must release the destination")

        let cancelledAudio = ContinuousAudioCapture()
        await cancelledAudio.gateStartup()
        let cancelledInserter = RetainedInserter()
        let cancelledController = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: cancelledAudio,
            transcriber: ContinuousTranscriber(["obsolete", "new"]),
            polisher: FakePolisher(log: EventLog()), inserter: cancelledInserter
        )
        await cancelledController.hotKeyDown(mode: .continuous)
        await waitForCondition("cancelled continuous startup should be gated") { await cancelledAudio.startupWaiting() }
        await cancelledController.hotKeyUp()
        await cancelledController.cancel()
        await cancelledController.hotKeyDown(mode: .continuous)
        assertEqual(await cancelledAudio.starts, 1, "replacement must wait for cancelled startup to unwind")
        await cancelledAudio.releaseStartup()
        await waitForState(.listening, controller: cancelledController, message: "replacement should start after cancelled startup teardown")
        await cancelledAudio.emit(2)
        await cancelledController.hotKeyUp()
        await waitForState(.succeeded("new"), controller: cancelledController, message: "old startup latch must not stop replacement capture")
        assertEqual(await cancelledAudio.cancellations, 1, "late startup cleanup must finish before replacement capture")
        assertEqual(await cancelledAudio.stops, 1, "cancelled startup must not flush as a completed phrase")
        assertEqual(await cancelledInserter.chunks, ["new"], "cancelled startup must not insert obsolete tail")
        assertEqual(await cancelledInserter.releases, ["focused-field", "focused-field"], "cancel and replacement drain must each release one target")

        let lateTarget = GatedTargetProvider()
        let lateInserter = RetainedInserter()
        let lateAudio = ContinuousAudioCapture()
        let lateController = DictationController(
            targetProvider: lateTarget, audioCapture: lateAudio,
            transcriber: ContinuousTranscriber(["unused"]),
            polisher: FakePolisher(log: EventLog()), inserter: lateInserter
        )
        await lateController.hotKeyDown(mode: .continuous)
        await waitForCondition("target capture should be gated before cancellation") { await lateTarget.isWaiting() }
        await lateController.cancel()
        await lateTarget.release()
        await waitForCondition("late cancelled target must be released") { await lateInserter.releases == ["focused-before-hud"] }
        assertEqual(await lateAudio.starts, 0, "cancel during target capture must prevent microphone startup")
        assertEqual(await lateController.state, .idle, "late target must not revive cancelled state")
    }

    static func testContinuousSessionLimit() async {
        let audio = ContinuousAudioCapture()
        await audio.setTail(1)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
            transcriber: ContinuousTranscriber(["limit tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter,
            maximumCaptureDuration: .milliseconds(1),
            maximumContinuousSessionDuration: .milliseconds(80)
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "continuous watchdog session should listen")
        try? await Task.sleep(for: .milliseconds(10))
        assertEqual(await controller.state, .listening, "continuous sessions must not use the shorter batch watchdog")
        await waitForState(.succeeded("limit tail"), controller: controller, message: "continuous session limit must flush and drain final speech")
        assertEqual(await audio.stops, 1, "continuous session limit must flush capture once")
        assertEqual(await audio.cancellations, 0, "continuous session limit must finish accepted speech")
        assertEqual(await inserter.chunks, ["limit tail"], "continuous session limit must preserve the final phrase")
        assertEqual(await inserter.releases, ["focused-field"], "continuous session limit must release its destination")
    }

    static func testVoicePauseResumeAndFinish() async {
        let target = FakeTargetProvider(log: EventLog())
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["pause tail", "resumed phrase"], gateFirst: true)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "voice mode should listen")
        await audio.setTail(1)
        await controller.pauseVoiceMode()
        await controller.resumeVoiceMode()
        await waitForCondition("pause tail should reach blocked inference") { await transcriber.isWaiting() }
        assertEqual(await controller.state, .pausing, "pause must wait for accepted text before offering resume")
        assertEqual(await audio.stops, 1, "pause must stop the microphone exactly once")
        assertEqual(await audio.starts, 1, "resume must wait for the pause drain")
        assertEqual(await inserter.releases, [], "pause must retain its original field")
        await transcriber.releaseFirst()
        await waitForState(.paused, controller: controller, message: "pause should drain into a retained session")
        assertEqual(await inserter.chunks, ["pause tail"], "pause must insert the final spoken phrase")
        await controller.resumeVoiceMode()
        await waitForState(.listening, controller: controller, message: "resume should restart the microphone")
        assertEqual(await target.captures, 1, "fixed target resume must keep the original capture")
        await audio.setTail(2)
        await controller.pauseVoiceMode()
        await waitForState(.paused, controller: controller, message: "second pause should preserve resumed text")
        assertEqual(await inserter.chunks, ["pause tail", " resumed phrase"], "resume must preserve separators in its original field")
        await controller.finishVoiceMode()
        await waitForState(.succeeded("resumed phrase"), controller: controller, message: "finish while paused must complete the retained session")
        assertEqual(await audio.starts, 2, "finish while paused must not restart the microphone")
        assertEqual(await audio.stops, 2, "finish while paused must not flush capture again")
        assertEqual(await inserter.releases, ["focused-field"], "finish while paused must release the retained field")
    }

    static func testRevokedMicrophoneBlocksVoiceResume() async {
        let audio = ContinuousAudioCapture()
        let target = FakeTargetProvider(log: EventLog())
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber([]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForState(.listening, controller: controller, message: "voice should start with microphone access")
        await controller.pauseVoiceMode()
        await waitForState(.paused, controller: controller, message: "voice should pause before revocation")
        await audio.setPermissionFailure(.denied)
        await controller.resumeVoiceMode()
        await waitForState(.error(.microphonePermissionDenied), controller: controller,
                           message: "revoked microphone must preserve the Settings repair action on resume")
        assertEqual(await audio.starts, 1, "revoked resume must not start another microphone engine")
        assertEqual(await audio.permissionRequests, 2, "resume must recheck authorization")
        assertEqual(await target.captures, 1, "authorization checks must preserve the existing target")
        await waitForCondition("failed resume must release its target") { await inserter.releases == ["focused-field"] }
    }

    static func testCanceledPendingPermissionCannotStartCapture() async {
        let audio = ContinuousAudioCapture()
        await audio.gatePermission()
        let target = FakeTargetProvider(log: EventLog())
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber([]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous)
        await waitForCondition("the OS microphone request should remain pending") { await audio.permissionWaiting() }
        assertEqual(await target.captures, 1, "the target must be captured before the permission prompt")
        assertEqual(await audio.starts, 0, "pending authorization must not start audio")
        await controller.cancel()
        await audio.releasePermission()
        await waitForCondition("canceling the pending prompt must release the original target") {
            await inserter.releases == ["focused-field"]
        }
        assertEqual(await controller.state, .idle, "a late grant must preserve session cancellation")
        assertEqual(await audio.starts, 0, "a late grant must not restart a canceled session")
        assertEqual(await inserter.chunks, [], "a canceled permission request must not insert text")
    }

    static func testPermissionFailurePreservesRepairAction() async {
        for failure in [DictationMicrophoneAuthorizationFailure.denied, .restricted, .unknown(923)] {
            let audio = ContinuousAudioCapture()
            await audio.setPermissionFailure(failure)
            let controller = DictationController(
                targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
                transcriber: ContinuousTranscriber([]),
                polisher: FakePolisher(log: EventLog()), inserter: RetainedInserter()
            )
            await controller.hotKeyDown(mode: .continuous)
            let expected: DictationFailure = failure == .denied
                ? .microphonePermissionDenied : .captureFailed(failure.localizedDescription)
            await waitForState(.error(expected), controller: controller,
                               message: "permission failures must preserve their own recovery guidance")
            assertEqual(await audio.starts, 0, "refused authorization must not start capture")
        }
    }

    static func testVoiceStartupIntents() async {
        for finish in [false, true] {
            let audio = ContinuousAudioCapture()
            await audio.gateStartup()
            await audio.setTail(1)
            let inserter = RetainedInserter()
            let controller = DictationController(
                targetProvider: FakeTargetProvider(log: EventLog()), audioCapture: audio,
                transcriber: ContinuousTranscriber(["startup phrase"]),
                polisher: FakePolisher(log: EventLog()), inserter: inserter
            )
            await controller.hotKeyDown(mode: .continuous)
            await waitForCondition("voice startup must be gated") { await audio.startupWaiting() }
            await controller.pauseVoiceMode()
            if finish { await controller.finishVoiceMode() }
            await audio.releaseStartup()
            await waitForState(finish ? .succeeded("startup phrase") : .paused, controller: controller, message: "startup must honor its latest stop intent")
            assertEqual(await inserter.chunks, ["startup phrase"], "startup intent must preserve accepted tail")
            assertEqual(await audio.stops, 1, "startup pause or finish must flush only once")
            if !finish {
                await audio.gateStartup()
                await controller.resumeVoiceMode()
                await waitForCondition("resume startup should be gated") { await audio.startupWaiting() }
                await controller.pauseVoiceMode()
                await controller.cancel()
                await audio.releaseStartup()
                await waitForCondition("cancelled resume must release its target") { await inserter.releases == ["focused-field"] }
                assertEqual(await controller.state, .idle, "cancel must discard a pending startup pause")
            }
        }
    }

    static func testFollowFocusCapturesBeforeInferenceAndSpacesPerField() async {
        let target = FollowingTargetProvider(["editor#1", "editor#2", "chat#1"])
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["First phrase.", "Second phrase.", "New field."], gateFirst: true)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "follow focus should listen")
        await audio.emit(1)
        await waitForCondition("follow focus first inference should block") { await transcriber.isWaiting() }
        await audio.emit(2)
        await audio.emit(3)
        await waitForCondition("later phrase destinations must capture before earlier inference returns") { await target.additionalCaptures == 3 }
        assertEqual(await transcriber.ordinals, [1], "capture must proceed independently of inference")
        await controller.finishVoiceMode()
        await transcriber.releaseFirst()
        await waitForState(.succeeded("New field."), controller: controller, message: "follow focus finish should drain pinned destinations")
        assertEqual(await inserter.targets, ["editor#1", "editor#2", "chat#1"], "each phrase must use the target captured before its inference")
        assertEqual(await inserter.chunks, ["First phrase.", " Second phrase.", "New field."], "only consecutive phrases in the same field should gain a separator")
        assertEqual(await inserter.releases, ["initial-field", "editor#1", "editor#2", "chat#1"], "follow focus must release validation and phrase leases")
        assertEqual(await target.captures, 1, "follow focus startup must validate only once")
    }

    static func testFollowFocusCancellationReleasesAllTargets() async {
        let target = FollowingTargetProvider(["editor#1", "chat#1"])
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["obsolete", "queued"], gateFirst: true)
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "cancel test should listen")
        await audio.emit(1)
        await waitForCondition("cancel test inference must block") { await transcriber.isWaiting() }
        await audio.emit(2)
        await waitForCondition("queued target must be captured") { await target.additionalCaptures == 2 }
        await controller.cancel()
        await waitForCondition("cancel must release in-flight and queued targets before inference returns") { await inserter.releases.count == 3 }
        assertEqual(Set(await inserter.releases), Set(["initial-field", "editor#1", "chat#1"]), "cancel must release each captured lease")
        await transcriber.releaseFirst()
        await waitForCondition("cancelled inference must unwind") { await transcriber.cancellations == 1 }
        assertEqual(await inserter.chunks, [], "cancel must suppress obsolete transcripts")
        assertEqual(await controller.state, .idle, "cancelled target cleanup must not revive voice mode")
    }

    static func testFollowFocusLateTargetCancellation() async {
        let target = FollowingTargetProvider(["late-field#1"], gateOrdinal: 1)
        let audio = ContinuousAudioCapture()
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber(["obsolete"]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "late target test should listen")
        await audio.emit(1)
        await waitForCondition("phrase target capture must suspend") { await target.isWaiting() }
        await controller.cancel()
        await target.releaseCapture()
        await waitForCondition("late phrase lease must release after cancellation") { await inserter.releases == ["initial-field", "late-field#1"] }
        assertEqual(await inserter.chunks, [], "late captured target must not insert obsolete audio")
        assertEqual(await controller.state, .idle, "late target must leave the cancelled state idle")
    }

    static func testFollowFocusRecoveryKeepsListening() async {
        let target = FollowingTargetProvider([nil, "moved-field#1", "editor#1"])
        let audio = ContinuousAudioCapture()
        let inserter = RetainedInserter()
        await inserter.rejectTarget("moved-field#1")
        let recovery = RecoveryRecorder()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber(["No field.", "Focus changed.", "Inserted next."]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter,
            recoveryObserver: { text, _ in recovery.record(text) }
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "recovery test should listen")
        await audio.emit(1)
        await waitForCondition("missing destination must retain transcript") { recovery.snapshot() == "No field." }
        assertEqual(await controller.state, .listening, "missing field must keep voice mode available")
        await audio.emit(2)
        await waitForCondition("focus failure must append recoverable text in order") { recovery.snapshot() == "No field. Focus changed." }
        assertEqual(await controller.state, .listening, "insertion failure must keep microphone listening")
        await audio.emit(3)
        await waitForCondition("next focused phrase should insert") { await inserter.chunks == ["Inserted next."] }
        await controller.finishVoiceMode()
        await waitForState(.succeeded("Inserted next."), controller: controller, message: "recovery session must finish normally")
        assertEqual(recovery.snapshot(), "No field. Focus changed.", "successful future phrases must not discard saved text")
        assertEqual(await inserter.releases, ["initial-field", "moved-field#1", "editor#1"], "failed and successful phrase targets must both release")
        await controller.clearRecoveryText()
        assertEqual(recovery.snapshot(), "", "discard must clear the recoverable transcript")
    }

    static func testSecurePhraseStopsBeforeInference() async {
        let target = FollowingTargetProvider([nil, "tail-field#1"], failures: [1: .secureTextTarget])
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(["Sensitive phrase.", "Sensitive tail."])
        let inserter = RetainedInserter()
        let recovery = RecoveryRecorder()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter,
            recoveryObserver: { text, _ in recovery.record(text) }
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "secure phrase session should listen")
        await audio.setTail(2)
        await audio.emit(1)
        await waitForState(.error(.secureTextTarget), controller: controller, message: "secure phrase must stop voice mode with a typed refusal")
        assertEqual(await transcriber.ordinals, [], "secure phrase and stop tail must never reach inference")
        assertEqual(recovery.snapshot(), "", "secure audio must not become saved text")
        assertEqual(await controller.recoveryText, "", "secure audio must not enter controller recovery")
        assertEqual(await audio.stops, 1, "secure refusal must stop microphone capture once")
        assertEqual(await audio.cancellations, 0, "secure refusal should finish its capture cleanly")
        assertEqual(await target.additionalCaptures, 1, "secure refusal must discard the stop tail before target capture")
        assertEqual(await inserter.chunks, [], "secure refusal must not insert text")
        assertEqual(await controller.isVoiceModeActive, false, "secure refusal must close voice mode")
    }

    static func testSecurePhraseDrainsAcceptedSafeJobs() async {
        let target = FollowingTargetProvider(
            [nil, "editor#1", nil, "tail-field#1"], failures: [3: .secureTextTarget]
        )
        let audio = ContinuousAudioCapture()
        let transcriber = ContinuousTranscriber(
            ["Safe recovery.", "Safe insertion.", "Sensitive phrase.", "Sensitive tail."], gateFirst: true
        )
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio, transcriber: transcriber,
            polisher: FakePolisher(log: EventLog()), inserter: inserter
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "secure drain session should listen")
        await audio.emit(1)
        await waitForCondition("safe inference should remain in flight") { await transcriber.isWaiting() }
        await audio.emit(2)
        await waitForCondition("second safe phrase must be accepted before secure refusal") { await target.additionalCaptures == 2 }
        await audio.setTail(4)
        await audio.emit(3)
        await waitForCondition("secure refusal must stop capture while safe inference is blocked") { await audio.stops == 1 }
        assertEqual(await controller.recoveryText, "", "secure refusal must leave saved text unchanged before safe jobs drain")
        assertEqual(await transcriber.ordinals, [1], "secure refusal must preserve only the in-flight safe inference")
        await transcriber.releaseFirst()
        await waitForState(.error(.secureTextTarget), controller: controller, message: "secure refusal must remain visible after safe jobs drain")
        assertEqual(await transcriber.ordinals, [1, 2], "only accepted safe phrases may reach inference")
        assertEqual(await controller.recoveryText, "Safe recovery.", "only the accepted unavailable-field phrase may enter recovery")
        assertEqual(await inserter.chunks, ["Safe insertion."], "accepted safe insertion must finish exactly once")
        assertEqual(await inserter.targets, ["editor#1"], "safe jobs must retain their original target")
        assertEqual(await inserter.releases, ["initial-field", "editor#1"], "secure stop must release accepted safe leases")
        assertEqual(await target.additionalCaptures, 3, "secure stop tail must not capture a new target")
        assertEqual(await audio.stops, 1, "safe drain must not stop capture twice")
        assertEqual(await audio.cancellations, 0, "secure stop must preserve accepted safe work")
    }

    static func testRecoveryBudgetFinishesAndDrains() async {
        let target = FollowingTargetProvider([nil, nil])
        let audio = ContinuousAudioCapture()
        let inserter = RetainedInserter()
        let controller = DictationController(
            targetProvider: target, audioCapture: audio,
            transcriber: ContinuousTranscriber(["Saved phrase", "Accepted tail"]),
            polisher: FakePolisher(log: EventLog()), inserter: inserter,
            maximumRecoveryTextBytes: 8
        )
        await controller.hotKeyDown(mode: .continuous, targetPolicy: .followFocus)
        await waitForState(.listening, controller: controller, message: "recovery budget session should listen")
        await audio.setTail(2)
        await audio.emit(1)
        await waitForState(.succeeded("Accepted tail"), controller: controller, message: "full saved text must finish and drain the accepted tail")
        assertEqual(await controller.recoveryText, "Saved phrase Accepted tail", "budget stop must preserve already accepted phrases without truncating")
        assertEqual(await controller.recoveryMessage, "Voice mode finished because saved text is full. Copy or discard the saved text before continuing.", "budget stop must explain why listening ended")
        assertEqual(await audio.stops, 1, "recovery budget must stop the microphone once")
    }

}
