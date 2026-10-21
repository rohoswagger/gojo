import AppKit
import Foundation
import os

private let dictationTargetLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "target"
)

private let dictationPipelineLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "pipeline"
)

private let dictationShortcutLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "shortcut-service"
)

#if DEBUG
private let dictationLatencyLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "latency"
)
#endif

@MainActor
private final class DictationModelDownloadPromptController {
    static let shared = DictationModelDownloadPromptController()

    private var isShowing = false

    private init() {}

    func present(
        title: String = "Download a voice model",
        message: String = "Gojo needs a voice model before dictation can start. Choose one in Dictation settings."
    ) {
        guard !isShowing else { return }
        isShowing = true
        defer { isShowing = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsWindowController.shared.showWindow(tab: "Dictation")
        }
    }
}

private actor DictationTranscriberRouter: LocalDictationTranscribing {
    private let local: LocalDictationTranscriber
    private let openRouter: OpenRouterDictationTranscriber
    init(local: LocalDictationTranscriber, openRouter: OpenRouterDictationTranscriber) {
        self.local = local
        self.openRouter = openRouter
    }

    func transcribe(_ audio: DictationAudio, request: DictationRecognitionRequest) async throws -> String {
        switch request {
        case .local: return try await local.transcribe(audio, request: request)
        case .openRouter: return try await openRouter.transcribe(audio, request: request)
        }
    }

    func prepare(request: DictationRecognitionRequest) async throws {
        switch request {
        case .local: try await local.prepare(request: request)
        case .openRouter: try await openRouter.prepare(request: request)
        }
    }

    func beginSession(_ plan: DictationSessionPlan) async throws {
        switch plan.recognition {
        case .local: try await local.beginSession(plan)
        case .openRouter: try await openRouter.beginSession(plan)
        }
    }

    func endSession(_ id: UUID) async {
        await local.endSession(id)
        await openRouter.endSession(id)
    }

    func cancelTranscription() async {
        async let cancelLocal: Void = local.cancelTranscription()
        async let cancelOpenRouter: Void = openRouter.cancelTranscription()
        await cancelLocal
        await cancelOpenRouter
    }
}

private enum DictationTextTarget: Sendable, Equatable {
    case external(token: String, identity: String?, processID: pid_t?, displayID: CGDirectDisplayID?)
    case practice(DictationPracticeTarget)

    var identity: String? {
        switch self {
        case .external(_, let identity, _, _): return identity
        case .practice(let target): return "practice-\(target.fieldID)-\(target.generation)"
        }
    }
    var processID: pid_t? {
        if case .external(_, _, let processID, _) = self { return processID }
        return nil
    }
    var displayID: CGDirectDisplayID? {
        if case .external(_, _, _, let displayID) = self { return displayID }
        return nil
    }
}

private struct XPCTargetProvider: DictationTargetCapturing {
    func captureTarget(purpose: DictationSessionPurpose) async throws -> DictationTargetResolution<DictationTextTarget> {
        if case .practice(let fieldID) = purpose {
            return try await .captured(.practice(DictationPracticeRegistry.shared.capture(fieldID: fieldID)))
        }
        let result = await XPCHelperClient.shared.captureFocusedTextTarget(promptIfNeeded: true)
        return try capturedTarget(from: result)
    }

    func captureAdditionalTarget(purpose: DictationSessionPurpose) async throws -> DictationTargetResolution<DictationTextTarget> {
        if case .practice = purpose { return try await captureTarget(purpose: purpose) }
        let result = await XPCHelperClient.shared.captureAdditionalFocusedTextTarget(promptIfNeeded: false)
        return try capturedTarget(from: result)
    }

    func destinationIdentifier(for target: DictationTextTarget) -> String? { target.identity }

    private func capturedTarget(from result: NSDictionary) throws -> DictationTargetResolution<DictationTextTarget> {
        guard (result["success"] as? NSNumber)?.boolValue == true,
              let token = result["token"] as? String else {
            let code = result["error"] as? String ?? "targetUnavailable"
            dictationTargetLogger.error("capture success=false error=\(code, privacy: .public)")
            switch code {
            case "noFocusedTextTarget": return .copyOnly(.noFocusedTextField)
            case "nonEditableTarget": return .copyOnly(.nonEditableTarget)
            case "permissionMissing": throw DictationFailure.accessibilityPermissionDenied
            case "secureTextTarget": throw DictationFailure.secureTextTarget
            default: throw DictationXPCError(code: code)
            }
        }
        dictationTargetLogger.notice("capture success=true")
        return .captured(.external(
            token: token,
            identity: result["targetIdentity"] as? String,
            processID: ((result["processID"] ?? result["pid"]) as? NSNumber).map { pid_t($0.int32Value) },
            displayID: (result["displayID"] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
        ))
    }
}

private struct XPCTextInserter: DictationTextInserting {
    func insert(_ text: String, into target: DictationTextTarget, plan: DictationSessionPlan) async throws -> DictationInsertionOutcome {
        try await insert(text, into: target, plan: plan, retaining: false)
    }

    func insertRetainingTarget(_ text: String, into target: DictationTextTarget, plan: DictationSessionPlan) async throws -> DictationInsertionOutcome {
        try await insert(text, into: target, plan: plan, retaining: true)
    }

    private func insert(_ text: String, into target: DictationTextTarget, plan: DictationSessionPlan, retaining: Bool) async throws -> DictationInsertionOutcome {
        if case .practice(let practiceTarget) = target {
            return try await DictationPracticeRegistry.shared.insert(text, target: practiceTarget)
        }
        guard case .external(let token, _, _, _) = target else { throw DictationXPCError(code: "invalidToken") }
        await GojoDictationService.shared.cancelCorrectionObservation()
        let result = retaining
            ? await XPCHelperClient.shared.insertTextRetainingTarget(text, token: token)
            : await XPCHelperClient.shared.insertText(text, token: token)
        guard (result["success"] as? NSNumber)?.boolValue == true else {
            throw DictationXPCError(code: result["error"] as? String ?? "insertionFailed")
        }
        await GojoDictationService.shared.observeCorrections(to: text, targetIdentity: target.identity, eligible: plan.learnsCorrections, sessionID: plan.id)
        return (result["verified"] as? NSNumber)?.boolValue == true ? .verified : .unverified
    }

    func releaseTarget(_ target: DictationTextTarget) async {
        if case .external(let token, _, _, _) = target { await XPCHelperClient.shared.releaseTextTarget(token) }
    }
}

private struct DictationXPCError: LocalizedError {
    let code: String

    var errorDescription: String? {
        switch code {
        case "unverifiedTextTarget":
            return "This field cannot safely receive background dictation. The text is saved for copying."
        case "permissionMissing":
            return "Allow Gojo to control your Mac in System Settings, then try again."
        case "secureTextTarget":
            return "Gojo does not dictate into password fields."
        case "nonEditableTarget", "noFocusedTextTarget", "targetUnavailable", "invalidTextTarget":
            return "Click a text field, then hold Control and Option."
        case "focusChanged", "invalidToken":
            return "You moved to another field, so Gojo did not add the text."
        case "partialInsertion":
            return "Gojo stopped before it finished adding the text."
        case "axInsertionFailed", "axInsertionNotConfirmed":
            return "This text field cannot accept dictation."
        case "pasteNotConfirmed":
            return "Gojo could not add the text. The transcript is still on your clipboard."
        case "helperUnavailable":
            return "Gojo's text helper is not available. Restart Gojo and try again."
        case "emptyText":
            return "Gojo did not hear anything."
        case "clipboardSnapshotUnavailable", "pasteEventUnavailable", "pasteboardWriteFailed", "pasteVerificationUnavailable", "insertionFailed":
            return "Gojo could not add the text. Try again."
        default:
            return "Gojo could not add the text. Try again."
        }
    }
}

@MainActor
final class GojoDictationService: ObservableObject {
    private typealias Controller = DictationController<
        XPCTargetProvider,
        AVAudioEngineCaptureService,
        DictationTranscriberRouter,
        S1MiniDictationPolisher,
        XPCTextInserter
    >

    static let shared = GojoDictationService()
    private static let selectedModelKey = "gojo.dictation.selectedModelID"
    nonisolated private static let shortcutEventQueue = DictationShortcutEventQueue { event in
        await GojoDictationService.shared.processShortcutEvent(event)
    }

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var microphoneTestState: DictationMicrophoneDiagnosticState = .idle
    @Published private(set) var selectedModel: DictationModelID
    @Published private(set) var selectedProvider: DictationProvider
    @Published private(set) var availableOpenRouterModels: [OpenRouterTranscriptionModel] = []
    @Published private(set) var selectedOpenRouterModelID: String
    @Published private(set) var hasVerifiedOpenRouterModel = false
    @Published private(set) var isRefreshingOpenRouterModels = false
    @Published private(set) var openRouterModelError: String?
    @Published private(set) var hasOpenRouterAPIKey: Bool
    @Published private(set) var isPreparingTranscriber = false
    @Published private(set) var openRouterAPIKeyHint: String?
    @Published private(set) var cleanupEnabled: Bool
    @Published private(set) var writingStyle: DictationWritingStyle
    @Published private(set) var vocabulary: [DictationVocabularyEntry]
    @Published private(set) var learnsCorrections: Bool
    @Published private(set) var s1MiniInstalled = false
    @Published private(set) var s1MiniOperation: S1MiniModelOperation?
    @Published private(set) var s1MiniError: String?
    @Published private(set) var installedModels: Set<DictationModelID> = []
    @Published private(set) var modelOperation: DictationModelOperation?
    @Published private(set) var modelErrors: [DictationModelID: String] = [:]
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var recoveryText = ""
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var targetApplicationName: String?
    @Published private(set) var sessionDisplayID: CGDirectDisplayID?

    @Published private(set) var selectedIntent = DictationSessionIntent(rawValue: UserDefaults.standard.string(forKey: "gojo.dictation.intent") ?? "") ?? .standard
    @Published private(set) var spokenCommandMode = DictationSpokenCommandMode(rawValue: UserDefaults.standard.string(forKey: "gojo.dictation.commands") ?? "") ?? .off
    @Published private(set) var commandLanguage = DictationCommandLanguage(rawValue: UserDefaults.standard.string(forKey: "gojo.dictation.commandLanguage") ?? "") ?? .english
    @Published private(set) var usesVocabulary = UserDefaults.standard.object(forKey: "gojo.dictation.usesVocabulary") as? Bool ?? true
    @Published private(set) var selectedInput = GojoDictationService.loadInputSelection()
    @Published private(set) var inputDevices: [DictationInputDevice] = []
    @Published private(set) var currentInputName: String?
    @Published private(set) var adaptiveSpeech = UserDefaults.standard.object(forKey: "gojo.dictation.adaptiveSpeech") as? Bool ?? true
    @Published private(set) var previewEnabled = UserDefaults.standard.object(forKey: "gojo.dictation.preview") as? Bool ?? false
    @Published private(set) var provisionalPreview: DictationProvisionalPreview?
    @Published private(set) var cuesEnabled = UserDefaults.standard.object(forKey: "gojo.dictation.cues") as? Bool ?? false
    @Published private(set) var completionAttentionID: UUID?
    @Published private(set) var lastCompletion: DictationCompletion?
    @Published private(set) var residencyPolicy = DictationResidencyPolicy(rawValue: UserDefaults.standard.string(forKey: "gojo.dictation.residency") ?? "") ?? .keepWarm
    @Published private(set) var activeIntent: DictationSessionIntent?
    @Published private(set) var activePracticeFieldID: UUID?
    private var nextPracticeFieldID: UUID?
    private var activeSessionID: UUID?
    private var activeSessionCues = false
    private var activeLearningSessionID: UUID?
    private var readyCueSessionID: UUID?
    private var completionSessionID: UUID?
    @Published private var sessionResourceCount = 0
    private let modelResidency: DictationModelResidency
    private let localTranscriber: LocalDictationTranscriber
    private let pipelineTranscriber: DictationTranscriberRouter
    private let polisher: S1MiniDictationPolisher
    private let openRouterClient: OpenRouterAPIClient
    private var controller: Controller?
    private var audioCapture: AVAudioEngineCaptureService?
    private var microphoneTestTask: Task<Void, Never>?
    private var initialModelStatusTask: Task<Set<DictationModelID>, Never>?
    private var s1MiniOperationTask: Task<Void, Never>?
    private var s1MiniOperationID: UUID?
    private var hasLoadedInitialModelStatus = false
    private var correctionLearner = DictationCorrectionLearner()
    private var correctionObservationTask: Task<Void, Never>?
    private var correctionObservationGeneration = UUID()
    @Published private var shortcutPreflighting = false
    @Published private var awaitingControllerStart = false
    private var shortcutGeneration: UInt = 0
    private var shortcutSessionGate = DictationShortcutSessionGate()
    private var transcriberWarmGeneration: UInt = 0
    private let warmupSequencer = DictationWarmupSequencer()

    private init() {
        let savedSelection = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        let initialModel = DictationModelID.resolveSelection(savedSelection)
        selectedModel = initialModel
        let initialProvider = DictationProvider(
            rawValue: UserDefaults.standard.string(forKey: DictationProvider.defaultsKey) ?? ""
        ) ?? .local
        selectedProvider = initialProvider
        selectedOpenRouterModelID = UserDefaults.standard.string(
            forKey: DictationOpenRouterSettings.modelDefaultsKey
        ) ?? ""
        let savedOpenRouterAPIKey = try? DictationKeychain.loadOpenRouterAPIKey()
        hasOpenRouterAPIKey = savedOpenRouterAPIKey != nil
        openRouterAPIKeyHint = Self.maskedAPIKeyHint(savedOpenRouterAPIKey)
        let savedCleanupEnabled = UserDefaults.standard.object(
            forKey: DictationOpenRouterSettings.polishingEnabledDefaultsKey
        ) as? Bool ?? false
        cleanupEnabled = savedCleanupEnabled
        writingStyle = DictationWritingStyle(
            rawValue: UserDefaults.standard.string(forKey: DictationWritingStyle.defaultsKey) ?? ""
        ) ?? .punctuated
        vocabulary = DictationVocabularyPolicy.load()
        learnsCorrections = UserDefaults.standard.object(
            forKey: DictationCorrectionLearningPolicy.defaultsKey
        ) as? Bool ?? true

        let localTranscriber = LocalDictationTranscriber(selectedModel: initialModel)
        let openRouterClient = OpenRouterAPIClient()
        let openRouterTranscriber = OpenRouterDictationTranscriber(client: openRouterClient)
        let pipelineTranscriber = DictationTranscriberRouter(local: localTranscriber, openRouter: openRouterTranscriber)
        let polisher = S1MiniDictationPolisher()
        self.localTranscriber = localTranscriber
        self.openRouterClient = openRouterClient
        self.pipelineTranscriber = pipelineTranscriber
        self.polisher = polisher
        let modelResidency = DictationModelResidency { [localTranscriber, polisher] in
            await localTranscriber.releaseModels()
            await polisher.releaseModels()
        }
        self.modelResidency = modelResidency
        Task { await modelResidency.setPolicy(residencyPolicy) }
        let observer: Controller.StateObserver = { [weak self] state in
            Task { @MainActor in
                guard let self, let controller = self.controller else { return }
                let generation = self.shortcutGeneration
                let currentState = await controller.state
                guard generation == self.shortcutGeneration, currentState == state else { return }
                self.receive(state)
            }
        }
        let audioCapture = AVAudioEngineCaptureService { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                if level == 0 || self.state == .listening {
                    self.audioLevel = min(max(level, 0), 1)
                }
            }
        }
        controller = Controller(
            targetProvider: XPCTargetProvider(),
            audioCapture: audioCapture,
            transcriber: pipelineTranscriber,
            polisher: polisher,
            inserter: XPCTextInserter(),
            stateObserver: observer,
            recoveryObserver: { [weak self] text, message in
                Task { @MainActor in
                    guard let self, let controller = self.controller,
                          await controller.recoverySnapshot == (text, message) else { return }
                    self.recoveryText = text
                    self.recoveryMessage = message
                }
            },
            targetObserver: { [weak self] target in
                Task { @MainActor in
                    guard let self, let controller = self.controller,
                          await controller.targetSnapshot == target else { return }
                    if let target { self.sessionDisplayID = target.displayID }
                    self.targetApplicationName = (target?.processID).flatMap {
                        NSRunningApplication(processIdentifier: $0)?.localizedName
                    }
                }
            },
            beforeCapture: { await MusicManager.shared.pauseForDictation() },
            acquireSessionResources: { [weak self, modelResidency] _ in
                await self?.adjustSessionResources(by: 1)
                let lease = await modelResidency.acquire()
                return { [weak self, modelResidency] in
                    await modelResidency.release(lease)
                    await self?.adjustSessionResources(by: -1)
                }
            },
            previewObserver: { [weak self] preview in
                Task { @MainActor in
                    guard let self, let controller = self.controller,
                          await controller.provisionalPreview == preview else { return }
                    self.provisionalPreview = preview
                }
            },
            completionObserver: { [weak self] id, completion, plan in
                Task { @MainActor in self?.receiveCompletion(completion, id: id, plan: plan) }
            }
        )
        self.audioCapture = audioCapture
        Task { await audioCapture.prepareForCaptureIfAuthorized() }
        initialModelStatusTask = Task(priority: .utility) { [localTranscriber] in
            await Self.scanInstalledModels(using: localTranscriber)
        }
        Task { [weak self] in
            await self?.loadInitialModelStatusIfNeeded()
        }
        Task(priority: .utility) { [weak self, polisher] in
            let installed = await polisher.isModelInstalled()
            guard let self else { return }
            s1MiniInstalled = installed
            if installed, cleanupEnabled, !isPreparingTranscriber {
                scheduleS1MiniWarmupAfterSpeech()
            } else if !installed, cleanupEnabled {
                setCleanupEnabled(false)
            }
        }
        if selectedProvider == .openRouter {
            refreshOpenRouterModels()
        }
        refreshInputDevices()
        warmSelectedTranscriber()
    }

    /// Loads the selected local speech model in the background so the first
    /// dictation of a session does not stall in `.transcribing` while multiple
    /// hundred megabytes of CoreML weights load. The transcriber caches the
    /// loaded manager, so this is a one-time cost per model per launch.
    private func warmSelectedTranscriber() {
        guard selectedProvider == .local else { return }
        transcriberWarmGeneration &+= 1
        let generation = transcriberWarmGeneration
        let model = selectedModel
        guard let request = try? makeRecognitionRequest() else { return }
        isPreparingTranscriber = true
        Task(priority: .utility) { [weak self, localTranscriber, warmupSequencer] in
            await self?.loadInitialModelStatusIfNeeded()
            guard let self else { return }
            guard generation == self.transcriberWarmGeneration,
                  self.installedModels.contains(self.selectedModel) else {
                self.finishTranscriberWarmupIfCurrent(generation: generation)
                return
            }
            await warmupSequencer.startSpeechThenCleanup(
                generation: generation,
                prepareSpeech: {
                    guard await self.shouldPrepareTranscriberWarmup(generation: generation) else { return }
                    #if DEBUG
                    let warmStart = ProcessInfo.processInfo.systemUptime
                    #endif
                    do {
                        let lease = await self.modelResidency.acquire()
                        do {
                            try await localTranscriber.prepare(request: request)
                            await self.modelResidency.release(lease)
                        } catch {
                            await self.modelResidency.release(lease)
                            throw error
                        }
                        await self.recordModelPreparationResult(nil, model: model, generation: generation)
                    } catch is CancellationError {
                        return
                    } catch {
                        let detail = DictationModelPreparationError.userFacingDetail(for: error)
                        await self.recordModelPreparationResult(detail, model: model, generation: generation)
                    }
                    #if DEBUG
                    dictationLatencyLogger.notice(
                        "stage=transcriberWarm ms=\(Int(((ProcessInfo.processInfo.systemUptime - warmStart) * 1_000).rounded()), privacy: .public)"
                    )
                    #endif
                },
                speechReady: { [self] completedGeneration in
                    await self.finishTranscriberWarmupIfCurrent(generation: completedGeneration)
                },
                shouldRunCleanup: { [self] completedGeneration in
                    await self.shouldRunS1MiniWarmup(generation: completedGeneration)
                },
                prepareCleanup: { [polisher, modelResidency] in
                    let lease = await modelResidency.acquire()
                    await polisher.prepareIfInstalled()
                    await modelResidency.release(lease)
                }
            )
        }
    }

    private func recordModelPreparationResult(_ failure: String?, model: DictationModelID, generation: UInt) {
        guard generation == transcriberWarmGeneration,
              selectedProvider == .local, selectedModel == model else { return }
        modelErrors[model] = failure
        if let failure {
            dictationPipelineLogger.error("stage=modelPreparation reason=\(failure, privacy: .public)")
        }
    }

    private func finishTranscriberWarmupIfCurrent(generation: UInt) {
        guard generation == transcriberWarmGeneration else { return }
        isPreparingTranscriber = false
    }

    private func shouldPrepareTranscriberWarmup(generation: UInt) -> Bool {
        generation == transcriberWarmGeneration
            && selectedProvider == .local
            && installedModels.contains(selectedModel)
    }

    private func shouldRunS1MiniWarmup(generation: UInt) -> Bool {
        generation == transcriberWarmGeneration
            && cleanupEnabled
            && s1MiniInstalled
            && modelErrors[selectedModel] == nil
    }

    var stateDetail: String? {
        guard case .error(let failure) = state else { return nil }
        return failure.localizedDescription
    }

    var preparingModel: DictationModelID? {
        guard case .installing(let model) = modelOperation else { return nil }
        return model
    }

    var switchingModel: DictationModelID? {
        guard case .selecting(let model) = modelOperation else { return nil }
        return model
    }

    var removingModel: DictationModelID? {
        guard case .removing(let model) = modelOperation else { return nil }
        return model
    }

    var canChangeModel: Bool {
        modelOperation == nil && sessionResourceCount == 0 && !shortcutPreflighting && !awaitingControllerStart && isDictationInactive
    }

    var canTestMicrophone: Bool {
        microphoneTestTask == nil && !shortcutPreflighting && !awaitingControllerStart && isDictationInactive
    }

    private var isDictationInactive: Bool {
        switch state {
        case .requestingPermission, .listening, .pausing, .paused, .transcribing, .inserting:
            return false
        case .idle, .succeeded, .error:
            return true
        }
    }

    var canChangeCleanupModel: Bool {
        guard s1MiniOperation == nil, sessionResourceCount == 0,
              !shortcutPreflighting, !awaitingControllerStart else { return false }
        switch state {
        case .requestingPermission, .listening, .pausing, .paused, .transcribing, .inserting:
            return false
        case .idle, .succeeded, .error:
            return true
        }
    }

    func isModelInstalled(_ model: DictationModelID) -> Bool {
        installedModels.contains(model)
    }

    nonisolated static func sendShortcutEvent(_ event: DictationShortcutEvent) {
        shortcutEventQueue.send(event)
    }

    func beginShortcut() {
        shortcutPreflighting = true
        Self.sendShortcutEvent(.keyDown)
    }

    private func processShortcutEvent(_ event: DictationShortcutEvent) async {
        guard let controller else { return }
        switch event {
        case .keyDown, .startVoiceMode:
            let requestsVoiceMode: Bool
            if case .startVoiceMode = event { requestsVoiceMode = true } else { requestsVoiceMode = false }
            let practiceID = nextPracticeFieldID ?? DictationPracticeRegistry.shared.focusedFieldID
            nextPracticeFieldID = nil
            let purpose = practiceID.map(DictationSessionPurpose.practice) ?? .focusedField
            let plan: DictationSessionPlan
            do {
                plan = try makeSessionPlan(mode: requestsVoiceMode ? .continuous : .singleUtterance, purpose: purpose)
            } catch {
                receive(.error(.transcriptionFailed(error.localizedDescription)))
                rejectShortcutStart()
                return
            }
            if let microphoneTestTask {
                microphoneTestTask.cancel()
                await microphoneTestTask.value
            }
            shortcutGeneration &+= 1
            shortcutPreflighting = true
            defer { shortcutPreflighting = false }
            if requestsVoiceMode, !isDictationInactive {
                receive(await controller.state)
                if !(await controller.isVoiceModeActive) { rejectShortcutStart() }
                return
            }
            if !requestsVoiceMode, state == .transcribing, modelOperation == nil {
                // A stuck or slow transcription must never hold the shortcut
                // hostage: pressing it again abandons the in-flight session so
                // a fresh one can start immediately. The mirrored state can lag
                // the controller (the session may already be inserting), so the
                // controller makes the call; on success, mirror .idle here
                // before the guards below run.
                if await controller.cancelIfTranscribing() {
                    dictationShortcutLogger.notice("keyDown canceled in-flight transcription")
                    shortcutSessionGate.reset()
                    receive(.idle)
                }
            }
            guard modelOperation == nil, isDictationInactive else {
                receive(await controller.state)
                let stateName: String
                switch state {
                case .idle: stateName = "idle"
                case .requestingPermission: stateName = "requestingPermission"
                case .listening: stateName = "listening"
                case .pausing: stateName = "pausing"
                case .paused: stateName = "paused"
                case .transcribing: stateName = "transcribing"
                case .inserting: stateName = "inserting"
                case .succeeded: stateName = "succeeded"
                case .error: stateName = "error"
                }
                dictationShortcutLogger.warning(
                    "ignored keyDown state=\(stateName, privacy: .public) modelOperation=\(self.modelOperation != nil, privacy: .public) preflighting=\(self.shortcutPreflighting, privacy: .public)"
                )
                rejectShortcutStart()
                return
            }
            sessionDisplayID = nil
            targetApplicationName = nil
            #if DEBUG
            let shortcutStartTime = ProcessInfo.processInfo.systemUptime
            #endif
            if case .local = plan.recognition {
                // The launch scan performs the full integrity checks once. Normal
                // shortcut activation uses that cached result instead of hashing
                // hundreds of megabytes before the microphone can start.
                await loadInitialModelStatusIfNeeded()
            }
            #if DEBUG
            let modelMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - shortcutStartTime) * 1_000).rounded()
            )
            dictationLatencyLogger.notice(
                "stage=modelPreflight ms=\(modelMilliseconds, privacy: .public)"
            )
            #endif
            switch plan.recognition {
            case .local(let request):
                guard installedModels.contains(request.model) else {
                    receive(.error(.modelNotInstalled))
                    rejectShortcutStart()
                    DictationModelDownloadPromptController.shared.present()
                    return
                }
            case .openRouter(let modelID):
                guard hasOpenRouterAPIKey else {
                    let detail = "Add an OpenRouter API key in Dictation settings."
                    receive(.error(.cloudConfigurationMissing(detail)))
                    rejectShortcutStart()
                    DictationModelDownloadPromptController.shared.present(
                        title: "Connect OpenRouter",
                        message: detail
                    )
                    return
                }
                guard hasVerifiedOpenRouterModel,
                      availableOpenRouterModels.contains(where: {
                          $0.id == modelID && $0.supportsTranscription
                      }) else {
                    let detail = "Wait for Gojo to verify an OpenRouter speech-to-text model in Dictation settings."
                    receive(.error(.cloudConfigurationMissing(detail)))
                    rejectShortcutStart()
                    DictationModelDownloadPromptController.shared.present(
                        title: "Choose a cloud voice model",
                        message: detail
                    )
                    return
                }
            }
            awaitingControllerStart = true
            activeSessionID = plan.id
            activeSessionCues = plan.cuesEnabled
            activeLearningSessionID = plan.learnsCorrections ? plan.id : nil
            activeIntent = plan.text.intent
            activePracticeFieldID = practiceID
            lastCompletion = nil
            completionAttentionID = nil
            if await controller.hotKeyDown(plan: plan) {
                if requestsVoiceMode { DictationModifierHotKeyMonitor.shared.adoptVoiceModeSession() }
                shortcutSessionGate.acceptKeyDown()
                shortcutPreflighting = false
                let currentState = await controller.state
                if DictationShortcutStatePolicy.shouldRearm(after: currentState) {
                    receive(currentState)
                }
            } else {
                receive(await controller.state)
                rejectShortcutStart()
            }
        case .keyUp:
            guard shortcutSessionGate.consumeKeyUp() else {
                dictationShortcutLogger.warning("ignored unmatched keyUp")
                return
            }
            await controller.hotKeyUp()
        case .lockVoiceMode:
            if await controller.lockVoiceMode() {
                DictationModifierHotKeyMonitor.shared.adoptVoiceModeSession()
                DictationPanelController.shared.show()
            } else {
                rejectShortcutStart()
            }
        case .pauseVoiceMode:
            await controller.pauseVoiceMode()
        case .resumeVoiceMode:
            await controller.resumeVoiceMode()
        case .finishVoiceMode:
            shortcutSessionGate.reset()
            await controller.finishVoiceMode()
        case .clearRecoveryText:
            await controller.clearRecoveryText()
        case .cancel:
            cancelMicrophoneTest()
            DictationModifierHotKeyMonitor.shared.rejectCurrentDictationStart()
            shortcutSessionGate.reset()
            await controller.cancel()
            receive(await controller.state)
        }
    }

    private func rejectShortcutStart() {
        shortcutSessionGate.reset()
        DictationModifierHotKeyMonitor.shared.rejectCurrentDictationStart()
    }

    func testMicrophone() {
        guard canTestMicrophone, let audioCapture else { return }
        microphoneTestState = .testing
        microphoneTestTask = Task { [weak self] in
            do {
                try await audioCapture.runMicrophoneDiagnostic()
                try Task.checkCancellation()
                self?.microphoneTestState = .passed
            } catch is CancellationError {
                self?.microphoneTestState = .idle
            } catch {
                self?.microphoneTestState = .failed(error.localizedDescription)
            }
            self?.microphoneTestTask = nil
        }
    }

    func cancelMicrophoneTest() {
        microphoneTestTask?.cancel()
    }

    func cancel() { Self.sendShortcutEvent(.cancel) }

    func cancel(completion: @escaping @MainActor @Sendable () -> Void) {
        Self.shortcutEventQueue.send(.cancel) { await completion() }
    }

    func startVoiceMode() {
        shortcutPreflighting = true
        Self.sendShortcutEvent(.startVoiceMode)
    }

    func pauseVoiceMode() { Self.sendShortcutEvent(.pauseVoiceMode) }
    func resumeVoiceMode() { Self.sendShortcutEvent(.resumeVoiceMode) }
    func finishVoiceMode() { Self.sendShortcutEvent(.finishVoiceMode) }
    func clearRecoveryText() { Self.sendShortcutEvent(.clearRecoveryText) }

    func terminate() {
        cancelMicrophoneTest()
        Self.sendShortcutEvent(.cancel)
    }

    /// The prewarmed capture engine binds to pre-sleep audio hardware and can
    /// start without delivering buffers after wake, so wake discards it and
    /// re-prepares after the HAL has settled.
    func handleSystemWake() {
        DictationMicrophonePermission.shared.refresh()
        guard let audioCapture else { return }
        Task {
            await audioCapture.discardPreparedCapture()
            try? await Task.sleep(for: .seconds(1))
            await audioCapture.prepareForCaptureIfAuthorized()
        }
    }

    #if DEBUG
    func transcribeE2E(_ audio: DictationAudio) async throws -> String {
        let request = DictationRecognitionRequest.local(try DictationLocalRecognition(model: selectedModel,
            language: recognitionLanguage, translateToEnglish: translatesToEnglish,
            recognitionTerms: usesVocabulary ? DictationVocabularyPolicy.recognitionTerms(vocabulary) : []))
        let lease = await modelResidency.acquire()
        do {
            let transcript = try await localTranscriber.transcribe(audio, request: request)
            await modelResidency.release(lease)
            return transcript
        } catch {
            await modelResidency.release(lease)
            throw error
        }
    }
    #endif

    private func modelOperationError(_ error: Error, fallback: String) -> String {
        let failure = DictationModelPreparationError.classify(error)
        if case .failed = failure { return fallback }
        return failure.localizedDescription
    }

    func downloadModel(_ model: DictationModelID) {
        guard canChangeModel, !installedModels.contains(model) else { return }
        let operation = DictationModelOperation.installing(model)
        modelOperation = operation
        modelErrors[model] = nil
        Task {
            do {
                let lease = await modelResidency.acquire()
                do {
                    try await localTranscriber.install(model)
                    await modelResidency.release(lease)
                } catch {
                    await modelResidency.release(lease)
                    throw error
                }
                installedModels.insert(model)
            } catch {
                modelErrors[model] = modelOperationError(error, fallback: "Could not download this model. Check your connection and try again.")
            }
            if modelOperation == operation {
                modelOperation = nil
            }
        }
    }

    func selectModel(_ model: DictationModelID) {
        guard canChangeModel,
              model != selectedModel,
              installedModels.contains(model) else { return }
        let operation = DictationModelOperation.selecting(model)
        modelOperation = operation
        modelErrors[model] = nil
        Task {
            do {
                let lease = await modelResidency.acquire()
                do {
                    try await localTranscriber.selectModel(model)
                    await modelResidency.release(lease)
                } catch {
                    await modelResidency.release(lease)
                    throw error
                }
                selectedModel = model
                UserDefaults.standard.set(model.rawValue, forKey: Self.selectedModelKey)
                warmSelectedTranscriber()
            } catch {
                modelErrors[model] = modelOperationError(error, fallback: "Gojo could not switch models. Try again.")
            }
            if modelOperation == operation {
                modelOperation = nil
            }
        }
    }

    func removeModel(_ model: DictationModelID) {
        guard canChangeModel, installedModels.contains(model) else { return }
        let operation = DictationModelOperation.removing(model)
        modelOperation = operation
        modelErrors[model] = nil
        Task {
            var removalError: String?
            do {
                let lease = await modelResidency.acquire()
                do {
                    try await localTranscriber.removeModel(model)
                    await modelResidency.release(lease)
                } catch {
                    await modelResidency.release(lease)
                    throw error
                }
            } catch {
                removalError = modelOperationError(error, fallback: "Gojo could not remove this model. Try again.")
            }
            let isStillInstalled = await localTranscriber.isModelInstalled(model)
            if isStillInstalled {
                installedModels.insert(model)
            } else {
                installedModels.remove(model)
            }
            modelErrors[model] = removalError
            if modelOperation == operation {
                modelOperation = nil
            }
        }
    }

    private nonisolated static func scanInstalledModels(
        using transcriber: LocalDictationTranscriber
    ) async -> Set<DictationModelID> {
        var installed: Set<DictationModelID> = []
        for model in DictationModelID.allCases where await transcriber.isModelInstalled(model) {
            installed.insert(model)
        }
        return installed
    }

    private func loadInitialModelStatusIfNeeded() async {
        guard !hasLoadedInitialModelStatus else { return }
        let task: Task<Set<DictationModelID>, Never>
        if let initialModelStatusTask {
            task = initialModelStatusTask
        } else {
            task = Task(priority: .utility) { [localTranscriber] in
                await Self.scanInstalledModels(using: localTranscriber)
            }
            initialModelStatusTask = task
        }
        installedModels = await task.value
        hasLoadedInitialModelStatus = true
        initialModelStatusTask = nil
    }

    private func receive(_ newState: DictationState) {
        awaitingControllerStart = false
        if DictationShortcutStatePolicy.shouldRearm(after: newState, isStartingShortcut: shortcutPreflighting) {
            shortcutSessionGate.reset()
            DictationModifierHotKeyMonitor.shared.rejectCurrentDictationStart()
        }
        state = newState
        if newState == .listening {
            if let id = activeSessionID, readyCueSessionID != id, activeSessionCues, cuesEnabled {
                readyCueSessionID = id
                DictationFeedback.play(.ready)
            }
            if let audioCapture {
                Task { [weak self] in self?.currentInputName = await audioCapture.currentInputDevice?.name }
            }
        }
        switch newState {
        case .idle, .succeeded, .error:
            activeIntent = nil
            activePracticeFieldID = nil
        default: break
        }
        if newState != .listening {
            audioLevel = 0
        }
        if case .error(let failure) = newState {
            let reason = failure.errorDescription ?? String(describing: failure)
            dictationPipelineLogger.error("state=error reason=\(reason, privacy: .public)")
        } else if case .succeeded = newState {
            if selectedProvider == .local { modelErrors[selectedModel] = nil }
            dictationPipelineLogger.notice("state=succeeded")
        }
    }

    private func adjustSessionResources(by delta: Int) {
        sessionResourceCount += delta
    }

    var currentModelCapabilities: DictationModelCapabilities? {
        selectedProvider == .local ? DictationModelDescriptor.descriptor(for: selectedModel).capabilities : nil
    }

    var recognitionLanguage: DictationLanguageSelection {
        let stored = UserDefaults.standard.string(forKey: languageKey)
        if let stored { return stored == "auto" ? .automatic : .fixed(stored) }
        return DictationModelDescriptor.descriptor(for: selectedModel).capabilities.language.defaultSelection
    }

    var translatesToEnglish: Bool { UserDefaults.standard.bool(forKey: translationKey) }
    private var languageKey: String { "gojo.dictation.language.\(selectedModel.rawValue)" }
    private var translationKey: String { "gojo.dictation.translate.\(selectedModel.rawValue)" }

    private static func loadInputSelection() -> DictationInputSelection {
        guard let data = UserDefaults.standard.data(forKey: "gojo.dictation.input"),
              let value = try? JSONDecoder().decode(DictationInputSelection.self, from: data) else { return .systemDefault }
        return value
    }

    func setIntent(_ value: DictationSessionIntent) { selectedIntent = value; UserDefaults.standard.set(value.rawValue, forKey: "gojo.dictation.intent") }
    func setSpokenCommandMode(_ value: DictationSpokenCommandMode) { spokenCommandMode = value; UserDefaults.standard.set(value.rawValue, forKey: "gojo.dictation.commands") }
    func setCommandLanguage(_ value: DictationCommandLanguage) { commandLanguage = value; UserDefaults.standard.set(value.rawValue, forKey: "gojo.dictation.commandLanguage") }
    func setUsesVocabulary(_ value: Bool) { usesVocabulary = value; UserDefaults.standard.set(value, forKey: "gojo.dictation.usesVocabulary") }
    func setRecognitionLanguage(_ value: DictationLanguageSelection) {
        guard let capabilities = currentModelCapabilities,
              (try? capabilities.validate(language: value, translateToEnglish: translatesToEnglish, model: selectedModel)) != nil else { return }
        objectWillChange.send()
        UserDefaults.standard.set(value.persistedCode, forKey: languageKey)
    }
    func setTranslatesToEnglish(_ value: Bool) {
        guard let capabilities = currentModelCapabilities,
              (try? capabilities.validate(language: recognitionLanguage, translateToEnglish: value, model: selectedModel)) != nil else { return }
        objectWillChange.send()
        UserDefaults.standard.set(value, forKey: translationKey)
    }
    func setInput(_ value: DictationInputSelection) { selectedInput = value; UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "gojo.dictation.input") }
    func refreshInputDevices() { inputDevices = (try? DictationInputDevices.inputDevices()) ?? [] }
    func setAdaptiveSpeech(_ value: Bool) { adaptiveSpeech = value; UserDefaults.standard.set(value, forKey: "gojo.dictation.adaptiveSpeech") }
    func setPreviewEnabled(_ value: Bool) { previewEnabled = value; UserDefaults.standard.set(value, forKey: "gojo.dictation.preview") }
    func setCuesEnabled(_ value: Bool) { cuesEnabled = value; UserDefaults.standard.set(value, forKey: "gojo.dictation.cues") }
    func setResidencyPolicy(_ value: DictationResidencyPolicy) {
        residencyPolicy = value
        UserDefaults.standard.set(value.rawValue, forKey: "gojo.dictation.residency")
        Task { await modelResidency.setPolicy(value) }
    }

    func beginPractice(fieldID: UUID) {
        guard isDictationInactive else { return }
        nextPracticeFieldID = fieldID
        startVoiceMode()
    }

    func cancelPractice(fieldID: UUID) {
        guard let controller else { return }
        Task { [weak self] in
            if await controller.cancelPractice(fieldID: fieldID) {
                guard let self else { return }
                self.shortcutSessionGate.reset()
                self.receive(await controller.state)
            }
        }
    }

    private func makeRecognitionRequest() throws -> DictationRecognitionRequest {
        switch selectedProvider {
        case .local:
            return .local(try DictationLocalRecognition(model: selectedModel, language: recognitionLanguage,
                translateToEnglish: translatesToEnglish,
                recognitionTerms: usesVocabulary ? DictationVocabularyPolicy.recognitionTerms(vocabulary) : []))
        case .openRouter: return .openRouter(modelID: selectedOpenRouterModelID)
        }
    }

    private func makeSessionPlan(mode: DictationCaptureMode, purpose: DictationSessionPurpose) throws -> DictationSessionPlan {
        let recognition = try makeRecognitionRequest()
        let englishOutput: Bool
        switch recognition {
        case .local(let request): englishOutput = request.language == .fixed("en") || request.translateToEnglish
        case .openRouter: englishOutput = false
        }
        let cleanup: DictationCleanupPolicy = cleanupEnabled && englishOutput ? .s1Mini(writingStyle) : .off
        let targetPolicy: DictationTargetPolicy
        if case .practice = purpose { targetPolicy = .fixed }
        else { targetPolicy = mode == .continuous ? .followFocus : .fixed }
        return DictationSessionPlan(mode: mode, pauseDuration: DictationPauseDuration.saved().seconds,
            targetPolicy: targetPolicy, purpose: purpose, recognition: recognition,
            text: DictationTextOptions(intent: selectedIntent, commands: spokenCommandMode, commandLanguage: commandLanguage,
                vocabulary: usesVocabulary ? vocabulary : [], cleanup: cleanup),
            capture: DictationCaptureConfiguration(input: selectedInput, adaptiveSpeech: adaptiveSpeech, previewEnabled: previewEnabled),
            cuesEnabled: cuesEnabled, learnsCorrections: learnsCorrections)
    }

    private func receiveCompletion(_ completion: DictationCompletion, id: UUID, plan: DictationSessionPlan) {
        guard activeSessionID == id, completionSessionID != id else { return }
        completionSessionID = id
        completionAttentionID = id
        lastCompletion = completion
        guard plan.cuesEnabled, cuesEnabled else { return }
        switch completion {
        case .empty: DictationFeedback.play(.empty)
        case .delivered: DictationFeedback.play(.delivered)
        case .savedForCopying: DictationFeedback.play(.savedForCopying)
        case .cancelled: DictationFeedback.play(.cancelled)
        case .failed: DictationFeedback.play(.failed)
        }
    }

    func setProvider(_ provider: DictationProvider) {
        guard canChangeModel else { return }
        guard provider != selectedProvider else { return }
        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: DictationProvider.defaultsKey)
        switch provider {
        case .local:
            hasVerifiedOpenRouterModel = false
            warmSelectedTranscriber()
        case .openRouter:
            transcriberWarmGeneration &+= 1
            isPreparingTranscriber = false
            refreshOpenRouterModels()
        }
    }

    @discardableResult
    func saveOpenRouterAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            openRouterModelError = "Enter an OpenRouter API key."
            return false
        }
        do {
            try DictationKeychain.saveOpenRouterAPIKey(trimmed)
            hasOpenRouterAPIKey = true
            openRouterAPIKeyHint = Self.maskedAPIKeyHint(trimmed)
            openRouterModelError = nil
            refreshOpenRouterModels()
            return true
        } catch {
            openRouterModelError = error.localizedDescription
            return false
        }
    }

    func removeOpenRouterAPIKey() {
        do {
            try DictationKeychain.deleteOpenRouterAPIKey()
            hasOpenRouterAPIKey = false
            openRouterAPIKeyHint = nil
            openRouterModelError = nil
        } catch {
            openRouterModelError = error.localizedDescription
        }
    }

    private static func maskedAPIKeyHint(_ key: String?) -> String? {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), key.count >= 12 else {
            return nil
        }
        return "\(key.prefix(5))******\(key.suffix(4))"
    }

    func refreshOpenRouterModels() {
        guard !isRefreshingOpenRouterModels, canChangeModel else { return }
        isRefreshingOpenRouterModels = true
        hasVerifiedOpenRouterModel = false
        availableOpenRouterModels = []
        openRouterModelError = nil
        let apiKey = try? DictationKeychain.loadOpenRouterAPIKey()
        Task { [weak self, openRouterClient] in
            do {
                let models = try await openRouterClient.listTranscriptionModels(apiKey: apiKey)
                    .sorted {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                guard let self else { return }
                availableOpenRouterModels = models
                if let selection = OpenRouterDictationModelSelection.select(
                    preferredModel: selectedOpenRouterModelID,
                    from: models
                ) {
                    selectOpenRouterModel(selection)
                    hasVerifiedOpenRouterModel = true
                } else {
                    selectedOpenRouterModelID = ""
                    UserDefaults.standard.removeObject(
                        forKey: DictationOpenRouterSettings.modelDefaultsKey
                    )
                    openRouterModelError = "No supported OpenRouter transcription model is available."
                }
                isRefreshingOpenRouterModels = false
            } catch {
                guard let self else { return }
                openRouterModelError = error.localizedDescription
                isRefreshingOpenRouterModels = false
            }
        }
    }

    func selectOpenRouterModel(_ modelID: String) {
        guard canChangeModel,
              availableOpenRouterModels.contains(where: {
                  $0.id == modelID && $0.supportsTranscription
              }) else { return }
        selectedOpenRouterModelID = modelID
        hasVerifiedOpenRouterModel = true
        UserDefaults.standard.set(modelID, forKey: DictationOpenRouterSettings.modelDefaultsKey)
    }

    func setCleanupEnabled(_ enabled: Bool) {
        guard s1MiniOperation == nil,
              !enabled || s1MiniInstalled else { return }
        updateCleanupEnabled(enabled)
    }

    private func updateCleanupEnabled(_ enabled: Bool) {
        cleanupEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: DictationOpenRouterSettings.polishingEnabledDefaultsKey
        )
        if enabled {
            scheduleS1MiniWarmupAfterSpeech()
        }
    }

    private func scheduleS1MiniWarmupAfterSpeech() {
        let generation = transcriberWarmGeneration
        Task { [self, warmupSequencer, polisher] in
            await warmupSequencer.startCleanupAfterCurrentSpeech(
                generation: generation,
                shouldRunCleanup: { [self] completedGeneration in
                    await self.shouldRunS1MiniWarmup(generation: completedGeneration)
                },
                prepareCleanup: { [polisher, modelResidency] in
                    let lease = await modelResidency.acquire()
                    await polisher.prepareIfInstalled()
                    await modelResidency.release(lease)
                }
            )
        }
    }

    func setWritingStyle(_ style: DictationWritingStyle) {
        writingStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: DictationWritingStyle.defaultsKey)
    }

    func downloadS1Mini() {
        guard canChangeCleanupModel, !s1MiniInstalled else { return }
        let operationID = UUID()
        s1MiniOperationID = operationID
        s1MiniOperation = .installing
        s1MiniError = nil
        let task = Task { [weak self, polisher, modelResidency] in
            let lease = await modelResidency.acquire()
            defer {
                Task { await modelResidency.release(lease) }
                if self?.s1MiniOperationID == operationID {
                    self?.s1MiniOperation = nil
                    self?.s1MiniOperationID = nil
                    self?.s1MiniOperationTask = nil
                }
            }
            do {
                try await polisher.installModel()
                guard let self else { return }
                s1MiniInstalled = true
                updateCleanupEnabled(true)
                await polisher.prepareIfInstalled()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                s1MiniInstalled = await polisher.isModelInstalled()
                s1MiniError = error.localizedDescription
            }
        }
        s1MiniOperationTask = task
    }

    func cancelS1MiniDownload() {
        guard s1MiniOperation == .installing else { return }
        s1MiniOperationTask?.cancel()
        s1MiniError = nil
    }

    func removeS1Mini() {
        guard canChangeCleanupModel, s1MiniInstalled else { return }
        let operationID = UUID()
        let wasCleanupEnabled = cleanupEnabled
        s1MiniOperationID = operationID
        s1MiniOperation = .removing
        s1MiniError = nil
        updateCleanupEnabled(false)
        let task = Task { [weak self, polisher, modelResidency] in
            let lease = await modelResidency.acquire()
            defer {
                Task { await modelResidency.release(lease) }
                if self?.s1MiniOperationID == operationID {
                    self?.s1MiniOperation = nil
                    self?.s1MiniOperationID = nil
                    self?.s1MiniOperationTask = nil
                }
            }
            do {
                try await polisher.removeModel()
                guard let self else { return }
                s1MiniInstalled = false
            } catch {
                guard let self else { return }
                s1MiniInstalled = await polisher.isModelInstalled()
                s1MiniError = error.localizedDescription
                if s1MiniInstalled, wasCleanupEnabled {
                    updateCleanupEnabled(true)
                }
            }
        }
        s1MiniOperationTask = task
    }

    @discardableResult
    func saveVocabularyEntry(id: UUID?, spoken: String, replacement: String) -> String? {
        let error = storeVocabularyEntry(id: id, spoken: spoken, replacement: replacement)
        if error == nil { resetCorrectionLearning() }
        return error
    }

    func removeVocabularyEntry(_ id: UUID) {
        vocabulary.removeAll { $0.id == id }
        persistVocabulary()
        resetCorrectionLearning()
    }

    @discardableResult
    func importVocabulary(_ document: DictationVocabularyImport.Document) -> DictationVocabularyImport.Report {
        let result = document.merging(into: vocabulary)
        if result.report.added > 0 {
            vocabulary = result.entries
            persistVocabulary()
            resetCorrectionLearning()
        }
        return result.report
    }

    func setLearnsCorrections(_ enabled: Bool) {
        guard enabled != learnsCorrections else { return }
        learnsCorrections = enabled
        if !enabled { activeLearningSessionID = nil }
        UserDefaults.standard.set(enabled, forKey: DictationCorrectionLearningPolicy.defaultsKey)
        resetCorrectionLearning()
    }

    func cancelCorrectionObservation() async {
        let wasObserving = correctionObservationTask != nil
        cancelCorrectionObservationTask()
        guard wasObserving || learnsCorrections else { return }
        await XPCHelperClient.shared.cancelDictationCorrectionObservation()
    }

    func observeCorrections(to text: String, targetIdentity: String?, eligible: Bool, sessionID: UUID) {
        cancelCorrectionObservationTask()
        guard eligible, learnsCorrections, activeLearningSessionID == sessionID,
              !text.isEmpty,
              let targetIdentity,
              targetIdentity.hasSuffix(":accessibility") else { return }
        let generation = UUID()
        correctionObservationGeneration = generation
        correctionObservationTask = Task { [weak self] in
            guard !Task.isCancelled,
                  self?.correctionObservationGeneration == generation else { return }
            let reply = await XPCHelperClient.shared.observeDictationCorrection(
                text,
                targetIdentity: targetIdentity
            )
            guard !Task.isCancelled else { return }
            self?.finishCorrectionObservation(reply: reply, generation: generation)
        }
    }

    private func finishCorrectionObservation(reply: NSDictionary, generation: UUID) {
        guard generation == correctionObservationGeneration else { return }
        correctionObservationTask = nil
        guard learnsCorrections,
              let original = reply["original"] as? String,
              let edited = reply["edited"] as? String,
              let candidate = DictationCorrectionLearningPolicy.candidate(
                  original: original,
                  edited: edited
              ) else { return }
        let foldedSpoken = Self.foldedVocabularyKey(candidate.spoken)
        guard !vocabulary.contains(where: { Self.foldedVocabularyKey($0.spoken) == foldedSpoken }),
              let learned = correctionLearner.observe(candidate) else { return }
        _ = storeVocabularyEntry(id: nil, spoken: learned.spoken, replacement: learned.replacement)
    }

    private func cancelCorrectionObservationTask() {
        correctionObservationGeneration = UUID()
        correctionObservationTask?.cancel()
        correctionObservationTask = nil
    }

    private func resetCorrectionLearning() {
        correctionLearner.reset()
        let wasObserving = correctionObservationTask != nil
        cancelCorrectionObservationTask()
        guard wasObserving else { return }
        let generation = correctionObservationGeneration
        Task { [weak self] in
            guard self?.correctionObservationGeneration == generation else { return }
            await XPCHelperClient.shared.cancelDictationCorrectionObservation()
        }
    }

    private static func foldedVocabularyKey(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func storeVocabularyEntry(id: UUID?, spoken: String, replacement: String) -> String? {
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanReplacement.isEmpty else {
            return "Enter the word or phrase you want Gojo to spell."
        }
        let trimmedSpoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSpoken = trimmedSpoken.isEmpty ? cleanReplacement : trimmedSpoken
        guard cleanSpoken.count <= DictationVocabularyEntry.maximumSpokenLength else {
            return trimmedSpoken.isEmpty
                ? "A word or phrase without a spoken alias must be \(DictationVocabularyEntry.maximumSpokenLength) characters or fewer."
                : "The spoken phrase must be \(DictationVocabularyEntry.maximumSpokenLength) characters or fewer."
        }
        guard cleanReplacement.count <= DictationVocabularyEntry.maximumReplacementLength else {
            return "The replacement must be \(DictationVocabularyEntry.maximumReplacementLength) characters or fewer."
        }
        let candidate = DictationVocabularyEntry(
            id: id ?? UUID(),
            spoken: cleanSpoken,
            replacement: cleanReplacement
        )
        guard let normalized = candidate.normalized else {
            return "Enter the word or phrase you want Gojo to spell."
        }
        let isEditingExistingEntry = id.map { candidateID in
            vocabulary.contains { $0.id == candidateID }
        } ?? false
        guard vocabulary.count < DictationVocabularyEntry.maximumEntries
                || isEditingExistingEntry else {
            return "Vocabulary is limited to \(DictationVocabularyEntry.maximumEntries) entries."
        }
        let foldedSpoken = normalized.spoken.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        guard !vocabulary.contains(where: {
            $0.id != normalized.id
                && $0.spoken.folding(
                    options: [.caseInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                ) == foldedSpoken
        }) else {
            return "That spoken phrase is already in your vocabulary."
        }

        if let index = vocabulary.firstIndex(where: { $0.id == normalized.id }) {
            vocabulary[index] = normalized
        } else {
            vocabulary.append(normalized)
        }
        persistVocabulary()
        return nil
    }

    private func persistVocabulary() {
        vocabulary = DictationVocabularyPolicy.sanitized(vocabulary)
        if let data = try? JSONEncoder().encode(vocabulary) {
            UserDefaults.standard.set(data, forKey: DictationVocabularyPolicy.defaultsKey)
        }
    }

}

extension DictationFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Download a voice model in Gojo Settings first."
        case .cloudConfigurationMissing(let detail):
            return detail
        case .microphonePermissionDenied:
            return "Allow Gojo to use the microphone in System Settings, then try again."
        case .accessibilityPermissionDenied:
            return "Enable Gojo in System Settings > Privacy & Security > Accessibility."
        case .secureTextTarget:
            return "Gojo does not dictate into password fields."
        case .targetUnavailable(let detail):
            return detail
        case .captureFailed(let detail):
            return detail
        case .transcriptionFailed(let detail):
            return detail
        case .transcriptionReturnedNoText:
            return "Gojo recorded audio but could not recognize speech. Try speaking a little longer."
        case .insertionFailed(let detail):
            return detail
        }
    }
}
