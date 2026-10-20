import Combine
import Foundation
import os

private let dictationShortcutLogger = Logger(subsystem: "gojo.tests", category: "shortcut")
private let dictationPipelineLogger = Logger(subsystem: "gojo.tests", category: "pipeline")

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
private final class ManualGate {
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

@MainActor
private final class EventLog {
    var events: [String] = []
}

@MainActor
private final class AVAudioEngineCaptureService {
    let completion = ManualGate()
    let log: EventLog
    var completesImmediately = true
    private(set) var starts = 0
    private(set) var cancellationObserved = false

    init(log: EventLog) { self.log = log }

    func runMicrophoneDiagnostic() async throws {
        starts += 1
        log.events.append("diagnostic start")
        defer { log.events.append("diagnostic cleanup") }
        guard !completesImmediately else { return }
        try await withTaskCancellationHandler {
            await completion.wait()
            try Task.checkCancellation()
        } onCancel: {
            Task { @MainActor in
                self.cancellationObserved = true
                self.log.events.append("diagnostic cancel")
            }
        }
    }
}

@MainActor
private final class Controller {
    let log: EventLog
    var stateReadGate: ManualGate?
    var acceptsShortcut = true
    private var currentState: DictationState = .idle
    private(set) var starts = 0
    var isVoiceModeActive: Bool { get async { false } }
    var state: DictationState {
        get async {
            if let stateReadGate { await stateReadGate.wait() }
            return currentState
        }
    }

    init(log: EventLog) { self.log = log }

    func hotKeyDown(mode: DictationCaptureMode, pauseDuration: TimeInterval,
                    targetPolicy: DictationTargetPolicy) async -> Bool {
        guard acceptsShortcut else { return false }
        starts += 1
        currentState = .requestingPermission
        log.events.append("shortcut start")
        return true
    }

    func cancelIfTranscribing() async -> Bool { false }
    func hotKeyUp() async {}
    func lockVoiceMode(pauseDuration: TimeInterval) async -> Bool { false }
    func pauseVoiceMode() async {}
    func resumeVoiceMode() async {}
    func finishVoiceMode() async {}
    func clearRecoveryText() async {}
    func cancel() async { currentState = .idle }
}

@MainActor
private final class DictationModifierHotKeyMonitor {
    static let shared = DictationModifierHotKeyMonitor()
    func adoptVoiceModeSession() {}
    func rejectCurrentDictationStart() {}
}

@MainActor
private final class DictationPanelController {
    static let shared = DictationPanelController()
    func show() {}
}

@MainActor
private final class DictationModelDownloadPromptController {
    static let shared = DictationModelDownloadPromptController()
    func present(title: String = "", message: String = "") {}
}

private enum DictationProvider { case local, openRouter }
private struct OpenRouterModelStub {
    let id: String
    let supportsTranscription: Bool
}

extension DictationFailure: LocalizedError {
    var errorDescription: String? { String(describing: self) }
}

@MainActor
private final class GojoDictationService {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var microphoneTestState: DictationMicrophoneDiagnosticState = .idle
    private var microphoneTestTask: Task<Void, Never>?
    private var controller: Controller?
    private var audioCapture: AVAudioEngineCaptureService?
    private var modelOperation: Int?
    private var selectedProvider = DictationProvider.local
    private var selectedModel = DictationModelID.whisperSmallEnglish
    private var installedModels: Set<DictationModelID> = [.whisperSmallEnglish]
    private var hasOpenRouterAPIKey = false
    private var hasVerifiedOpenRouterModel = false
    private var availableOpenRouterModels: [OpenRouterModelStub] = []
    private var selectedOpenRouterModelID = ""
    private var sessionDisplayID: Int?
    private var targetApplicationName: String?
    private var shortcutGeneration: UInt = 0
    private var shortcutSessionGate = DictationShortcutSessionGate()
    private var audioLevel: Float = 0
    let modelScan = ManualGate()
    var blocksModelScan = false

    init(controller: Controller, audioCapture: AVAudioEngineCaptureService) {
        self.controller = controller
        self.audioCapture = audioCapture
    }

    private func loadInitialModelStatusIfNeeded() async {
        if blocksModelScan { await modelScan.wait() }
    }

    func process(_ event: DictationShortcutEvent) async { await processShortcutEvent(event) }
    func publish(_ state: DictationState) { receive(state) }

    // __PRODUCTION_SERVICE_MEMBERS__
}

@main
private struct DictationMicrophoneDiagnosticServiceRegression {
    @MainActor
    static func main() async {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            fputs("Microphone diagnostic service regression timed out\n", stderr)
            exit(1)
        }
        defer { timeout.cancel() }
        await diagnosticWaitsForShortcutPreflight()
        await diagnosticWaitsForControllerPublication()
        await idleDiagnosticRunsAndCanRunAgain()
        await rejectedShortcutReleasesDiagnosticAdmission()
        await shortcutAwaitsDiagnosticCleanup()
        print("Dictation microphone diagnostic service regression passed")
    }

    @MainActor
    private static func waitUntil(_ message: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            require(ContinuousClock.now < deadline, message)
            await Task.yield()
        }
    }

    @MainActor
    private static func diagnosticWaitsForShortcutPreflight() async {
        let log = EventLog()
        let audio = AVAudioEngineCaptureService(log: log)
        let controller = Controller(log: log)
        let service = GojoDictationService(controller: controller, audioCapture: audio)
        service.blocksModelScan = true
        let shortcut = Task { await service.process(.keyDown) }
        await waitUntil("shortcut should suspend in model preflight") { service.modelScan.arrivals == 1 }
        require(service.state == .idle, "preflight must reproduce the stale idle UI state")
        service.testMicrophone()
        require(service.microphoneTestState == .idle, "a microphone test must not enter during shortcut preflight")
        service.modelScan.release()
        await shortcut.value
        require(audio.starts == 0 && controller.starts == 1,
                "accepted shortcut preflight must exclude diagnostic capture")
    }

    @MainActor
    private static func diagnosticWaitsForControllerPublication() async {
        let log = EventLog()
        let audio = AVAudioEngineCaptureService(log: log)
        let controller = Controller(log: log)
        let stateRead = ManualGate()
        controller.stateReadGate = stateRead
        let service = GojoDictationService(controller: controller, audioCapture: audio)
        let shortcut = Task { await service.process(.keyDown) }
        await waitUntil("accepted shortcut should await controller state") { stateRead.arrivals == 1 }
        require(controller.starts == 1 && service.state == .idle,
                "accepted target startup must reproduce the idle publication window")
        service.testMicrophone()
        require(service.microphoneTestState == .idle,
                "a microphone test must wait until accepted controller startup is published")
        stateRead.release()
        await shortcut.value
        require(service.state == .idle, "admission must preserve target capture before state publication")
        service.testMicrophone()
        require(service.microphoneTestState == .idle,
                "accepted startup must exclude diagnostics until the controller publishes")
        require(audio.starts == 0, "pending target capture must exclude diagnostic capture")
        service.publish(.idle)
        service.testMicrophone()
        await waitUntil("returning to idle should release diagnostic admission") { service.microphoneTestState == .passed }
        require(audio.starts == 1, "published idle must permit a real diagnostic")
    }

    @MainActor
    private static func idleDiagnosticRunsAndCanRunAgain() async {
        let log = EventLog()
        let audio = AVAudioEngineCaptureService(log: log)
        let service = GojoDictationService(controller: Controller(log: log), audioCapture: audio)
        for expectedStarts in 1...2 {
            service.testMicrophone()
            await waitUntil("an idle microphone test should complete") { service.microphoneTestState == .passed }
            require(audio.starts == expectedStarts, "the diagnostic action must run capture and release its completed task")
        }
    }

    @MainActor
    private static func rejectedShortcutReleasesDiagnosticAdmission() async {
        let log = EventLog()
        let audio = AVAudioEngineCaptureService(log: log)
        let controller = Controller(log: log)
        controller.acceptsShortcut = false
        let service = GojoDictationService(controller: controller, audioCapture: audio)
        await service.process(.keyDown)
        service.testMicrophone()
        await waitUntil("rejected shortcut must release diagnostic admission") { service.microphoneTestState == .passed }
        require(audio.starts == 1 && controller.starts == 0,
                "rejection must restore diagnostic availability without starting dictation")
    }

    @MainActor
    private static func shortcutAwaitsDiagnosticCleanup() async {
        let log = EventLog()
        let audio = AVAudioEngineCaptureService(log: log)
        audio.completesImmediately = false
        let controller = Controller(log: log)
        let service = GojoDictationService(controller: controller, audioCapture: audio)
        service.testMicrophone()
        await waitUntil("diagnostic should own capture") { audio.completion.arrivals == 1 }
        let shortcut = Task { await service.process(.keyDown) }
        await waitUntil("shortcut should cancel the diagnostic") { audio.cancellationObserved }
        require(controller.starts == 0, "shortcut must await diagnostic cleanup before starting")
        audio.completion.release()
        await shortcut.value
        require(log.events == ["diagnostic start", "diagnostic cancel", "diagnostic cleanup", "shortcut start"],
                "diagnostic cleanup must finish before accepted shortcut capture")
        require(service.microphoneTestState == .idle, "canceled diagnostic must clear its testing state")
    }
}
