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
    private let provider: @Sendable () -> DictationProvider

    init(
        local: LocalDictationTranscriber,
        openRouter: OpenRouterDictationTranscriber,
        provider: @escaping @Sendable () -> DictationProvider
    ) {
        self.local = local
        self.openRouter = openRouter
        self.provider = provider
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        switch provider() {
        case .local:
            return try await local.transcribe(audio)
        case .openRouter:
            return try await openRouter.transcribe(audio)
        }
    }

    func prepare() async {
        guard provider() == .local else { return }
        await local.prepare()
    }

    func cancelTranscription() async {
        async let cancelLocal: Void = local.cancelTranscription()
        async let cancelOpenRouter: Void = openRouter.cancelTranscription()
        await cancelLocal
        await cancelOpenRouter
    }
}

private struct XPCTargetProvider: DictationTargetCapturing {
    func captureTarget() async throws -> String {
        let result = await XPCHelperClient.shared.captureFocusedTextTarget(promptIfNeeded: true)
        guard (result["success"] as? NSNumber)?.boolValue == true,
              let token = result["token"] as? String else {
            let code = result["error"] as? String ?? "targetUnavailable"
            dictationTargetLogger.error("capture success=false error=\(code, privacy: .public)")
            throw DictationXPCError(code: code)
        }
        let displayID = (result["displayID"] as? NSNumber).map {
            CGDirectDisplayID($0.uint32Value)
        }
        await MainActor.run {
            GojoDictationService.shared.setSessionDisplayID(displayID)
        }
        dictationTargetLogger.notice("capture success=true")
        return token
    }
}

private struct XPCTextInserter: DictationTextInserting {
    func insert(_ text: String, into target: String) async throws {
        let result = await XPCHelperClient.shared.insertText(text, token: target)
        guard (result["success"] as? NSNumber)?.boolValue == true else {
            let code = result["error"] as? String ?? "insertionFailed"
            dictationTargetLogger.error("insert success=false error=\(code, privacy: .public)")
            throw DictationXPCError(code: code)
        }
    }
}

private struct DictationXPCError: LocalizedError {
    let code: String

    var errorDescription: String? {
        switch code {
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
    @Published private(set) var s1MiniInstalled = false
    @Published private(set) var s1MiniOperation: S1MiniModelOperation?
    @Published private(set) var s1MiniError: String?
    @Published private(set) var installedModels: Set<DictationModelID> = []
    @Published private(set) var modelOperation: DictationModelOperation?
    @Published private(set) var modelErrors: [DictationModelID: String] = [:]
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var sessionDisplayID: CGDirectDisplayID?

    private let localTranscriber: LocalDictationTranscriber
    private let pipelineTranscriber: DictationTranscriberRouter
    private let polisher: S1MiniDictationPolisher
    private let openRouterClient: OpenRouterAPIClient
    private var controller: Controller?
    private var initialModelStatusTask: Task<Set<DictationModelID>, Never>?
    private var s1MiniOperationTask: Task<Void, Never>?
    private var s1MiniOperationID: UUID?
    private var hasLoadedInitialModelStatus = false
    private var shortcutPreflighting = false
    private var shortcutSessionGate = DictationShortcutSessionGate()

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
        if let data = UserDefaults.standard.data(forKey: DictationVocabularyPolicy.defaultsKey),
           let savedVocabulary = try? JSONDecoder().decode(
               [DictationVocabularyEntry].self,
               from: data
           ) {
            vocabulary = DictationVocabularyPolicy.sanitized(savedVocabulary)
        } else {
            vocabulary = []
        }

        let localTranscriber = LocalDictationTranscriber(selectedModel: initialModel)
        let openRouterClient = OpenRouterAPIClient()
        let openRouterTranscriber = OpenRouterDictationTranscriber(client: openRouterClient)
        let pipelineTranscriber = DictationTranscriberRouter(
            local: localTranscriber,
            openRouter: openRouterTranscriber,
            provider: {
                DictationProvider(
                    rawValue: UserDefaults.standard.string(forKey: DictationProvider.defaultsKey) ?? ""
                ) ?? .local
            }
        )
        let polisher = S1MiniDictationPolisher()
        self.localTranscriber = localTranscriber
        self.openRouterClient = openRouterClient
        self.pipelineTranscriber = pipelineTranscriber
        self.polisher = polisher
        let observer: Controller.StateObserver = { [weak self] state in
            Task { @MainActor in
                self?.receive(state)
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
            stateObserver: observer
        )
        Task { await audioCapture.prepareForCaptureIfAuthorized() }
        initialModelStatusTask = Task { [localTranscriber] in
            await Self.scanInstalledModels(using: localTranscriber)
        }
        Task { [weak self] in
            await self?.loadInitialModelStatusIfNeeded()
        }
        Task { [weak self, polisher] in
            let installed = await polisher.isModelInstalled()
            guard let self else { return }
            s1MiniInstalled = installed
            if installed, cleanupEnabled {
                await polisher.prepareIfInstalled()
            } else if !installed, cleanupEnabled {
                setCleanupEnabled(false)
            }
        }
        if selectedProvider == .openRouter {
            refreshOpenRouterModels()
        }
        warmSelectedTranscriber()
    }

    /// Loads the selected local speech model in the background so the first
    /// dictation of a session does not stall in `.transcribing` while multiple
    /// hundred megabytes of CoreML weights load. The transcriber caches the
    /// loaded manager, so this is a one-time cost per model per launch.
    private func warmSelectedTranscriber() {
        guard selectedProvider == .local else { return }
        Task { [weak self, localTranscriber] in
            await self?.loadInitialModelStatusIfNeeded()
            guard let self, self.installedModels.contains(self.selectedModel) else { return }
            self.isPreparingTranscriber = true
            #if DEBUG
            let warmStart = ProcessInfo.processInfo.systemUptime
            #endif
            await localTranscriber.prepare()
            #if DEBUG
            dictationLatencyLogger.notice(
                "stage=transcriberWarm ms=\(Int(((ProcessInfo.processInfo.systemUptime - warmStart) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            self.isPreparingTranscriber = false
        }
    }

    var stateDetail: String? {
        guard case .error(let failure) = state else { return nil }
        return failure.localizedDescription
    }

    var isModelReady: Bool {
        installedModels.contains(selectedModel)
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
        guard modelOperation == nil, !shortcutPreflighting else {
            return false
        }
        switch state {
        case .requestingPermission, .listening, .transcribing, .inserting:
            return false
        case .idle, .succeeded, .error:
            return true
        }
    }

    var canChangeCleanupModel: Bool {
        guard s1MiniOperation == nil else { return false }
        switch state {
        case .requestingPermission, .listening, .transcribing, .inserting:
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

    private func processShortcutEvent(_ event: DictationShortcutEvent) async {
        guard let controller else { return }
        switch event {
        case .keyDown:
            if state == .transcribing, modelOperation == nil {
                // A stuck or slow transcription must never hold the shortcut
                // hostage: pressing it again abandons the in-flight session so
                // a fresh one can start immediately. The controller publishes
                // .idle asynchronously, so mirror it here before the guards run.
                dictationShortcutLogger.notice("keyDown canceled in-flight transcription")
                shortcutSessionGate.reset()
                await controller.cancel()
                receive(.idle)
            }
            guard canChangeModel else {
                let stateName: String
                switch state {
                case .idle: stateName = "idle"
                case .requestingPermission: stateName = "requestingPermission"
                case .listening: stateName = "listening"
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
            #if DEBUG
            let shortcutStartTime = ProcessInfo.processInfo.systemUptime
            #endif
            shortcutPreflighting = true
            defer { shortcutPreflighting = false }
            if selectedProvider == .local {
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
            switch selectedProvider {
            case .local:
                guard installedModels.contains(selectedModel) else {
                    receive(.error(.modelNotInstalled))
                    rejectShortcutStart()
                    DictationModelDownloadPromptController.shared.present()
                    return
                }
            case .openRouter:
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
                          $0.id == selectedOpenRouterModelID && $0.supportsTranscription
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
            if await controller.hotKeyDown() {
                shortcutSessionGate.acceptKeyDown()
            } else {
                rejectShortcutStart()
            }
        case .keyUp:
            guard shortcutSessionGate.consumeKeyUp() else {
                dictationShortcutLogger.warning("ignored unmatched keyUp")
                return
            }
            await controller.hotKeyUp()
        case .cancel:
            shortcutSessionGate.reset()
            await controller.cancel()
        }
    }

    private func rejectShortcutStart() {
        shortcutSessionGate.reset()
        DictationModifierHotKeyMonitor.shared.rejectCurrentDictationStart()
    }

    func cancel() {
        Self.sendShortcutEvent(.cancel)
    }

    func terminate() {
        guard let controller else { return }
        Task { await controller.terminate() }
    }

    #if DEBUG
    func transcribeE2E(_ audio: DictationAudio) async throws -> String {
        try await localTranscriber.transcribe(audio)
    }
    #endif

    func downloadModel(_ model: DictationModelID) {
        guard canChangeModel, !installedModels.contains(model) else { return }
        let operation = DictationModelOperation.installing(model)
        modelOperation = operation
        modelErrors[model] = nil
        Task {
            do {
                try await localTranscriber.install(model)
                installedModels.insert(model)
            } catch {
                modelErrors[model] = "Could not download this model. Check your connection and try again."
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
                try await localTranscriber.selectModel(model)
                selectedModel = model
                UserDefaults.standard.set(model.rawValue, forKey: Self.selectedModelKey)
                warmSelectedTranscriber()
            } catch {
                modelErrors[model] = "Gojo could not switch models. Try again."
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
                try await localTranscriber.removeModel(model)
            } catch {
                removalError = "Gojo could not remove this model. Try again."
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
            task = Task { [localTranscriber] in
                await Self.scanInstalledModels(using: localTranscriber)
            }
            initialModelStatusTask = task
        }
        installedModels = await task.value
        hasLoadedInitialModelStatus = true
        initialModelStatusTask = nil
    }

    private func receive(_ newState: DictationState) {
        state = newState
        if newState != .listening {
            audioLevel = 0
        }
        if case .error(let failure) = newState {
            let reason = failure.errorDescription ?? String(describing: failure)
            dictationPipelineLogger.error("state=error reason=\(reason, privacy: .public)")
        } else if case .succeeded = newState {
            dictationPipelineLogger.notice("state=succeeded")
        }
    }

    func setProvider(_ provider: DictationProvider) {
        guard canChangeModel else { return }
        selectedProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: DictationProvider.defaultsKey)
        switch provider {
        case .local:
            hasVerifiedOpenRouterModel = false
            warmSelectedTranscriber()
        case .openRouter:
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
            Task { [polisher] in await polisher.prepareIfInstalled() }
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
        let task = Task { [weak self, polisher] in
            defer {
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
        let task = Task { [weak self, polisher] in
            defer {
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
        let cleanSpoken = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSpoken.isEmpty, !cleanReplacement.isEmpty else {
            return "Enter both the spoken phrase and its replacement."
        }
        guard cleanSpoken.count <= DictationVocabularyEntry.maximumSpokenLength else {
            return "The spoken phrase must be \(DictationVocabularyEntry.maximumSpokenLength) characters or fewer."
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
            return "Enter both the spoken phrase and its replacement."
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

    func removeVocabularyEntry(_ id: UUID) {
        vocabulary.removeAll { $0.id == id }
        persistVocabulary()
    }

    private func persistVocabulary() {
        vocabulary = DictationVocabularyPolicy.sanitized(vocabulary)
        if let data = try? JSONEncoder().encode(vocabulary) {
            UserDefaults.standard.set(data, forKey: DictationVocabularyPolicy.defaultsKey)
        }
    }

    fileprivate func setSessionDisplayID(_ displayID: CGDirectDisplayID?) {
        sessionDisplayID = displayID
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
        case .targetUnavailable(let detail):
            return detail
        case .captureFailed:
            return "Gojo could not use the microphone. Check your microphone and try again."
        case .transcriptionFailed(let detail):
            return detail
        case .emptyTranscript:
            return "Gojo did not hear anything."
        case .insertionFailed(let detail):
            return detail
        }
    }
}
