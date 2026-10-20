import CoreGraphics
import Combine
import Foundation
import os

private let dictationTargetLogger = Logger(subsystem: "gojo.tests", category: "target")
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
    var currentInputDevice: DictationInputDevice? { get async { nil } }
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
    private(set) var plans: [DictationSessionPlan] = []
    var isVoiceModeActive: Bool { get async { false } }
    var state: DictationState {
        get async {
            if let stateReadGate { await stateReadGate.wait() }
            return currentState
        }
    }

    init(log: EventLog) { self.log = log }

    func hotKeyDown(plan: DictationSessionPlan) async -> Bool {
        guard acceptsShortcut else { return false }
        starts += 1
        plans.append(plan)
        currentState = .requestingPermission
        log.events.append("shortcut start")
        return true
    }

    func cancelIfTranscribing() async -> Bool { false }
    func hotKeyUp() async {}
    func lockVoiceMode() async -> Bool { false }
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
private enum DictationFeedbackEvent: Equatable { case ready, empty, delivered, savedForCopying, cancelled, failed }
@MainActor private enum DictationFeedback {
    static var events: [DictationFeedbackEvent] = []
    static func play(_ event: DictationFeedbackEvent) { events.append(event) }
}
@MainActor private final class XPCHelperClient {
    static let shared = XPCHelperClient()
    let replyGate = ManualGate()
    private(set) var observations = 0
    private(set) var cancellations = 0
    private(set) var externalCaptures = 0
    func captureFocusedTextTarget(promptIfNeeded: Bool) async -> NSDictionary {
        externalCaptures += 1
        return ["success": true, "token": "external-token", "targetIdentity": "external-field"]
    }
    func captureAdditionalFocusedTextTarget(promptIfNeeded: Bool) async -> NSDictionary {
        await captureFocusedTextTarget(promptIfNeeded: promptIfNeeded)
    }
    func observeDictationCorrection(_ text: String, targetIdentity: String) async -> NSDictionary {
        observations += 1
        await replyGate.wait()
        return ["original": text, "edited": "corrected"]
    }
    func cancelDictationCorrectionObservation() async { cancellations += 1 }
}
private struct DictationPracticeTarget: Sendable, Equatable { let fieldID: UUID; let generation: UUID }
@MainActor private final class DictationPracticeRegistry {
    static let shared = DictationPracticeRegistry()
    var focusedFieldID: UUID?
    private(set) var captures = 0
    func capture(fieldID: UUID) throws -> DictationPracticeTarget {
        captures += 1
        return DictationPracticeTarget(fieldID: fieldID, generation: UUID())
    }
}

// __PRODUCTION_TARGET_DECLARATIONS__

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
    private var modelErrors: [DictationModelID: String] = [:]
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
    private var nextPracticeFieldID: UUID?
    private var activeSessionID: UUID?
    private var activeSessionCues = false
    private var activeLearningSessionID: UUID?
    private var activeIntent: DictationSessionIntent?
    private var activePracticeFieldID: UUID?
    private var completionAttentionID: UUID?
    private var lastCompletion: DictationCompletion?
    private var completionSessionID: UUID?
    private var correctionLearner = DictationCorrectionLearner()
    private var correctionObservationTask: Task<Void, Never>?
    private var correctionObservationGeneration = UUID()
    private(set) var learnedCallbacks = 0
    private func finishCorrectionObservation(reply: NSDictionary, generation: UUID) { learnedCallbacks += 1 }
    func setTestCues(_ value: Bool) { cuesEnabled = value }
    func acceptTestSession(_ plan: DictationSessionPlan) { activeSessionID = plan.id; activeSessionCues = plan.cuesEnabled; activeLearningSessionID = plan.learnsCorrections ? plan.id : nil }
    func completeTestSession(_ completion: DictationCompletion, plan: DictationSessionPlan) { receiveCompletion(completion, id: plan.id, plan: plan) }
    var completionForTest: DictationCompletion? { lastCompletion }
    var completionIDForTest: UUID? { completionAttentionID }
    private var readyCueSessionID: UUID?
    private var cuesEnabled = false
    private var currentInputName: String?
    var recognitionLanguage = DictationLanguageSelection.fixed("en")
    var translatesToEnglish = false
    var usesVocabulary = true
    var vocabulary: [DictationVocabularyEntry] = []
    var cleanupEnabled = true
    var writingStyle = DictationWritingStyle.formal
    var selectedIntent = DictationSessionIntent.standard
    var spokenCommandMode = DictationSpokenCommandMode.off
    var commandLanguage = DictationCommandLanguage.english
    var selectedInput = DictationInputSelection.systemDefault
    var adaptiveSpeech = true
    var previewEnabled = false
    var learnsCorrections = true
    func planForTest() throws -> DictationSessionPlan { try makeSessionPlan(mode: .singleUtterance, purpose: .focusedField) }
    func useMultilingualModel() { selectedModel = .whisperLargeV3 }
    func changeSelectionDuringPreflight() { selectedModel = .whisperLargeV3; selectedProvider = .openRouter }
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
        await preflightUsesFrozenPlan()
        planBuilderDisablesUnsafeCleanup()
        feedbackRequiresFrozenAndCurrentConsent()
        await learningOptOutCancelsNowAndOptInWaitsForNewPlan()
        await productionTargetCaptureRespectsPurpose()
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
    private static func productionTargetCaptureRespectsPurpose() async {
        let provider = XPCTargetProvider()
        let helper = XPCHelperClient.shared
        let fieldID = UUID()
        let first = try! await provider.captureTarget(purpose: .practice(fieldID))
        let second = try! await provider.captureAdditionalTarget(purpose: .practice(fieldID))
        require(helper.externalCaptures == 0, "practice target capture must never call the real Accessibility helper")
        for resolution in [first, second] {
            guard case .captured(.practice(let target)) = resolution else { fatalError("Expected registered practice target") }
            require(target.fieldID == fieldID, "practice capture must use the frozen registered field identity")
        }
        let external = try! await provider.captureTarget(purpose: .focusedField)
        guard case .captured(.external(let token, _, _, _)) = external else { fatalError("Expected external XPC target") }
        require(token == "external-token" && helper.externalCaptures == 1, "external targets must retain existing XPC capture")
    }

    @MainActor
    private static func feedbackRequiresFrozenAndCurrentConsent() {
        DictationFeedback.events = []
        let log = EventLog()
        let service = GojoDictationService(controller: Controller(log: log), audioCapture: AVAudioEngineCaptureService(log: log))
        let disabledPlan = DictationSessionPlan(cuesEnabled: false)
        service.acceptTestSession(disabledPlan)
        service.setTestCues(true)
        service.publish(.listening)
        service.completeTestSession(.delivered, plan: disabledPlan)
        require(DictationFeedback.events.isEmpty, "enabling cues mid-take must wait for the next session")
        let revokedPlan = DictationSessionPlan(cuesEnabled: true)
        service.acceptTestSession(revokedPlan)
        service.setTestCues(false)
        service.publish(.listening)
        service.completeTestSession(.savedForCopying, plan: revokedPlan)
        require(DictationFeedback.events.isEmpty, "current cue opt-out must silence the frozen session")
        let enabledPlan = DictationSessionPlan(cuesEnabled: true)
        service.acceptTestSession(enabledPlan)
        service.setTestCues(true)
        service.publish(.listening)
        service.publish(.listening)
        service.publish(.transcribing)
        require(DictationFeedback.events == [.ready], "ready cue must play once and microphone stop must not imply success")
        service.completeTestSession(.empty(reason: .noSpeech), plan: enabledPlan)
        service.completeTestSession(.delivered, plan: enabledPlan)
        require(DictationFeedback.events == [.ready, .empty], "one real completion identity must emit one matching cue")
        require(service.completionForTest == .empty(reason: .noSpeech) && service.completionIDForTest == enabledPlan.id,
            "the typed quiet outcome must remain visible independently of microphone state")
    }

    @MainActor
    private static func learningOptOutCancelsNowAndOptInWaitsForNewPlan() async {
        let defaultsKey = DictationCorrectionLearningPolicy.defaultsKey
        let previous = UserDefaults.standard.object(forKey: defaultsKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
        }
        let log = EventLog()
        let service = GojoDictationService(controller: Controller(log: log), audioCapture: AVAudioEngineCaptureService(log: log))
        let helper = XPCHelperClient.shared
        let ineligiblePlan = DictationSessionPlan(learnsCorrections: false)
        let eligiblePlan = DictationSessionPlan(learnsCorrections: true)
        service.acceptTestSession(ineligiblePlan)
        service.observeCorrections(to: "initial", targetIdentity: "editor:accessibility", eligible: false, sessionID: ineligiblePlan.id)
        await Task.yield()
        require(helper.observations == 0, "a session that began without learning consent must not observe corrections after opt-in")
        service.acceptTestSession(eligiblePlan)
        service.observeCorrections(to: "eligible", targetIdentity: "editor:accessibility", eligible: true, sessionID: eligiblePlan.id)
        await waitUntil("eligible session must begin actual correction observation") { helper.observations == 1 }
        service.setLearnsCorrections(false)
        await waitUntil("opting out must cancel correction observation immediately") { helper.cancellations == 1 }
        helper.replyGate.release()
        await Task.yield()
        require(service.learnedCallbacks == 0, "late correction callbacks must not learn after opt-out")
        service.setLearnsCorrections(true)
        service.observeCorrections(to: "old ineligible session", targetIdentity: "editor:accessibility", eligible: false, sessionID: ineligiblePlan.id)
        await Task.yield()
        require(helper.observations == 1, "later opt-in must not grant learning eligibility to an old session")
        service.observeCorrections(to: "revoked eligible session", targetIdentity: "editor:accessibility", eligible: true, sessionID: eligiblePlan.id)
        await Task.yield()
        require(helper.observations == 1, "off then on during one take must not restore its revoked learning eligibility")
    }

    @MainActor
    private static func preflightUsesFrozenPlan() async {
        let log = EventLog()
        let controller = Controller(log: log)
        let service = GojoDictationService(controller: controller, audioCapture: AVAudioEngineCaptureService(log: log))
        service.blocksModelScan = true
        service.selectedIntent = .code
        service.spokenCommandMode = .punctuationAndCode
        service.vocabulary = [DictationVocabularyEntry(spoken: "go joe", replacement: "Gojo")]
        service.selectedInput = .deviceUID("first-input")
        service.learnsCorrections = false
        let start = Task { await service.process(.keyDown) }
        await waitUntil("frozen plan test must wait at preflight") { service.modelScan.arrivals == 1 }
        service.changeSelectionDuringPreflight()
        service.selectedIntent = .literal
        service.spokenCommandMode = .off
        service.vocabulary = []
        service.selectedInput = .systemDefault
        service.learnsCorrections = true
        service.modelScan.release()
        await start.value
        require(controller.starts == 1, "preflight must validate the frozen installed local model after current provider changes")
        guard let plan = controller.plans.first, case .local(let request) = plan.recognition else { fatalError("Expected frozen local request") }
        require(request.model == .whisperSmallEnglish && request.recognitionTerms == ["Gojo"], "recognition request must preserve model and vocabulary before preflight")
        require(plan.text.intent == .code && plan.text.commands == .punctuationAndCode, "intent and commands must freeze before preflight")
        require(plan.capture.input == .deviceUID("first-input") && !plan.learnsCorrections, "input and learning eligibility must freeze before preflight")
        require(plan.text.cleanup == .off, "Code intent must disable semantic cleanup")
    }

    @MainActor
    private static func planBuilderDisablesUnsafeCleanup() {
        let log = EventLog()
        let controller = Controller(log: log)
        let service = GojoDictationService(controller: controller, audioCapture: AVAudioEngineCaptureService(log: log))
        service.recognitionLanguage = .fixed("en")
        let english = try! service.planForTest()
        require(english.text.cleanup == .s1Mini(.formal), "Standard English must retain the existing explicit cleanup style")
        service.selectedIntent = .literal
        require(try! service.planForTest().text.cleanup == .off, "Literal must disable semantic cleanup")
        service.selectedIntent = .standard
        service.useMultilingualModel()
        service.recognitionLanguage = .automatic
        require(try! service.planForTest().text.cleanup == .off, "automatic multilingual output must not enter English-only cleanup")
        service.recognitionLanguage = .fixed("es")
        require(try! service.planForTest().text.cleanup == .off, "Spanish output must not enter English-only cleanup")
        service.translatesToEnglish = true
        require(try! service.planForTest().text.cleanup == .s1Mini(.formal), "explicit English translation may use English cleanup")
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
