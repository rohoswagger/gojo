import Combine
import Foundation
import os

private let dictationPipelineLogger = Logger(subsystem: "gojo.tests", category: "pipeline")

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private actor PreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor LocalDictationTranscriber {
    private let failures: Set<Int>
    private let gates: [Int: PreparationGate]
    private(set) var preparations = 0

    init(failures: Set<Int> = [], gates: [Int: PreparationGate] = [:]) {
        self.failures = failures
        self.gates = gates
    }

    func prepare(request: DictationRecognitionRequest) async throws {
        preparations += 1
        let attempt = preparations
        if let gate = gates[attempt] { await gate.wait() }
        if failures.contains(attempt) {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))
        }
    }
}

private actor S1MiniDictationPolisher {
    private(set) var preparations = 0

    func prepareIfInstalled() { preparations += 1 }
}

private enum DictationProvider { case local, openRouter }
private enum DictationFeedbackEvent { case ready }
private enum DictationFeedback { static func play(_ event: DictationFeedbackEvent) {} }
private actor CaptureStub { var currentInputDevice: DictationInputDevice? { nil } }


@MainActor
private final class DictationModifierHotKeyMonitor {
    static let shared = DictationModifierHotKeyMonitor()
    func rejectCurrentDictationStart() {}
}

extension DictationFailure: LocalizedError {
    var errorDescription: String? { String(describing: self) }
}

@MainActor
private final class GojoDictationService {
    private let modelResidency = DictationModelResidency {}
    private var activeSessionID: UUID?
    private var readyCueSessionID: UUID?
    private var activeSessionCues = false
    private var cuesEnabled = false
    private var activeIntent: DictationSessionIntent?
    private var activePracticeFieldID: UUID?
    private var currentInputName: String?
    private var audioCapture: CaptureStub?
    private func makeRecognitionRequest() throws -> DictationRecognitionRequest {
        .local(try DictationLocalRecognition(model: selectedModel))
    }
    private let localTranscriber: LocalDictationTranscriber
    private let polisher: S1MiniDictationPolisher
    private let warmupSequencer = DictationWarmupSequencer()
    private var transcriberWarmGeneration: UInt = 0
    var selectedProvider = DictationProvider.local
    var selectedModel = DictationModelID.whisperSmallEnglish
    var installedModels: Set<DictationModelID> = [.whisperSmallEnglish, .whisperLargeV3]
    var cleanupEnabled = true
    var s1MiniInstalled = true
    @Published private(set) var isPreparingTranscriber = false
    @Published var modelErrors: [DictationModelID: String] = [:]
    @Published private(set) var state: DictationState = .idle
    private var awaitingControllerStart = false
    private var shortcutPreflighting = false
    private var shortcutSessionGate = DictationShortcutSessionGate()
    private var audioLevel: Float = 0

    init(localTranscriber: LocalDictationTranscriber, polisher: S1MiniDictationPolisher) {
        self.localTranscriber = localTranscriber
        self.polisher = polisher
    }

    private func loadInitialModelStatusIfNeeded() async {}
    func warm() { warmSelectedTranscriber() }
    func publish(_ state: DictationState) { receive(state) }

    // __PRODUCTION_SERVICE_MEMBERS__
}

@main
private struct DictationModelPreparationServiceRegression {
    @MainActor
    static func main() async {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            fputs("Model preparation service regression timed out\n", stderr)
            exit(1)
        }
        defer { timeout.cancel() }
        await failurePublishesStorageGuidanceAndSkipsCleanup()
        await successfulPreparationClearsOnlyItsModelError()
        await staleFailureCannotFollowSelectionChanges()
        await staleGenerationCannotFinishReplacementWarmup()
        successClearsOnlyTheSelectedLocalModelError()
        print("Dictation model preparation service regression passed")
    }

    @MainActor
    private static func waitUntil(_ message: String, _ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) {
            require(ContinuousClock.now < deadline, message)
            await Task.yield()
        }
    }

    @MainActor
    private static func failurePublishesStorageGuidanceAndSkipsCleanup() async {
        let transcriber = LocalDictationTranscriber(failures: [1])
        let polisher = S1MiniDictationPolisher()
        let service = GojoDictationService(localTranscriber: transcriber, polisher: polisher)
        service.warm()
        require(service.isPreparingTranscriber, "warmup must show preparation while loading")
        await waitUntil("failed preparation should stop the spinner and publish a model error") {
            !service.isPreparingTranscriber && service.modelErrors[.whisperSmallEnglish] != nil
        }
        let detail = service.modelErrors[.whisperSmallEnglish] ?? ""
        require(detail.localizedCaseInsensitiveContains("free disk space"), "the model row should name the storage problem")
        require(detail.contains("1 GB") && detail.localizedCaseInsensitiveContains("try again"),
                "the model row should explain how much space to free before retrying")
        try? await Task.sleep(for: .milliseconds(30))
        let cleanups = await polisher.preparations
        require(cleanups == 0, "failed speech preparation must not start cleanup model preparation")
        require(service.state == .idle, "background warmup should report through the model row")
    }

    @MainActor
    private static func successfulPreparationClearsOnlyItsModelError() async {
        let gate = PreparationGate()
        let transcriber = LocalDictationTranscriber(gates: [1: gate])
        let polisher = S1MiniDictationPolisher()
        let service = GojoDictationService(localTranscriber: transcriber, polisher: polisher)
        service.modelErrors = [.whisperSmallEnglish: "previous preparation failed", .whisperLargeV3: "other model failed"]
        service.warm()
        await waitUntil("speech preparation should reach its controlled load") { await gate.arrivals == 1 }
        require(service.isPreparingTranscriber, "a pending load must retain its spinner")
        await gate.release()
        await waitUntil("successful preparation should clear its old model error and stop the spinner") {
            !service.isPreparingTranscriber && service.modelErrors[.whisperSmallEnglish] == nil
        }
        await waitUntil("successful speech preparation should permit cleanup warmup") { await polisher.preparations == 1 }
        require(service.modelErrors[.whisperLargeV3] == "other model failed", "successful warmup must preserve other model errors")
    }

    @MainActor
    private static func staleFailureCannotFollowSelectionChanges() async {
        for changesProvider in [false, true] {
            let gate = PreparationGate()
            let transcriber = LocalDictationTranscriber(failures: [1], gates: [1: gate])
            let service = GojoDictationService(localTranscriber: transcriber, polisher: S1MiniDictationPolisher())
            service.cleanupEnabled = false
            service.modelErrors = [.whisperSmallEnglish: "original row", .whisperLargeV3: "replacement row"]
            service.warm()
            await waitUntil("old selection preparation should be in flight") { await gate.arrivals == 1 }
            if changesProvider {
                service.selectedProvider = .openRouter
            } else {
                service.selectedModel = .whisperLargeV3
            }
            await gate.release()
            await waitUntil("the completed old warmup should release its spinner") { !service.isPreparingTranscriber }
            require(service.modelErrors[.whisperSmallEnglish] == "original row",
                    "late failure must not alter the old row after a model or provider change")
            require(service.modelErrors[.whisperLargeV3] == "replacement row",
                    "late failure must not alter the replacement row")
        }
    }

    @MainActor
    private static func staleGenerationCannotFinishReplacementWarmup() async {
        let first = PreparationGate()
        let second = PreparationGate()
        let transcriber = LocalDictationTranscriber(failures: [1], gates: [1: first, 2: second])
        let service = GojoDictationService(localTranscriber: transcriber, polisher: S1MiniDictationPolisher())
        service.cleanupEnabled = false
        service.warm()
        await waitUntil("first generation should be preparing") { await first.arrivals == 1 }
        service.warm()
        await first.release()
        await waitUntil("replacement generation should start after the old load returns") { await second.arrivals == 1 }
        require(service.isPreparingTranscriber, "the old generation must not stop the replacement spinner")
        require(service.modelErrors[.whisperSmallEnglish] == nil, "the old generation must not publish its failure")
        await second.release()
        await waitUntil("the current generation should finish preparation") { !service.isPreparingTranscriber }
        require(service.modelErrors[.whisperSmallEnglish] == nil, "successful replacement should retain a clear model row")
    }

    @MainActor
    private static func successClearsOnlyTheSelectedLocalModelError() {
        let service = GojoDictationService(localTranscriber: LocalDictationTranscriber(), polisher: S1MiniDictationPolisher())
        service.modelErrors = [.whisperSmallEnglish: "selected row", .whisperLargeV3: "other row"]
        service.publish(.succeeded("recognized speech"))
        require(service.modelErrors[.whisperSmallEnglish] == nil, "successful dictation should clear the selected model error")
        require(service.modelErrors[.whisperLargeV3] == "other row", "successful dictation should preserve another model's error")
        service.modelErrors[.whisperSmallEnglish] = "local preparation failed"
        service.selectedProvider = .openRouter
        service.publish(.succeeded("cloud speech"))
        require(service.modelErrors[.whisperSmallEnglish] == "local preparation failed", "cloud success must preserve local preparation errors")
    }
}
