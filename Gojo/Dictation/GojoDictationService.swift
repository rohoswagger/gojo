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

    func present() {
        guard !isShowing else { return }
        isShowing = true
        defer { isShowing = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Download a voice model"
        alert.informativeText = "Gojo needs a voice model before dictation can start. Choose one in Local Dictation settings."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsWindowController.shared.showWindow(tab: "Dictation")
        }
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
        LocalDictationTranscriber,
        XPCTextInserter
    >

    static let shared = GojoDictationService()
    private static let selectedModelKey = "gojo.dictation.selectedModelID"
    nonisolated private static let shortcutEventQueue = DictationShortcutEventQueue { event in
        await GojoDictationService.shared.processShortcutEvent(event)
    }

    @Published private(set) var state: DictationState = .idle
    @Published private(set) var selectedModel: DictationModelID
    @Published private(set) var installedModels: Set<DictationModelID> = []
    @Published private(set) var preparingModel: DictationModelID?
    @Published private(set) var switchingModel: DictationModelID?
    @Published private(set) var removingModel: DictationModelID?
    @Published private(set) var shortcutStarting = false
    @Published private(set) var modelErrors: [DictationModelID: String] = [:]
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var sessionDisplayID: CGDirectDisplayID?

    private let transcriber: LocalDictationTranscriber
    private var controller: Controller?
    private var initialModelStatusTask: Task<Set<DictationModelID>, Never>?
    private var hasLoadedInitialModelStatus = false
    private var shortcutPreflighting = false

    private init() {
        let savedSelection = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        let initialModel = DictationModelID.resolveSelection(savedSelection)
        selectedModel = initialModel
        transcriber = LocalDictationTranscriber(selectedModel: initialModel)
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
            transcriber: transcriber,
            inserter: XPCTextInserter(),
            stateObserver: observer
        )
        Task { await audioCapture.prepareForCaptureIfAuthorized() }
        initialModelStatusTask = Task { [transcriber] in
            await Self.scanInstalledModels(using: transcriber)
        }
        Task { [weak self] in
            await self?.loadInitialModelStatusIfNeeded()
        }
    }

    var stateTitle: String {
        switch state {
        case .idle: return "Ready"
        case .requestingPermission: return "Getting ready"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        case .inserting: return "Adding text"
        case .succeeded: return "Done"
        case .error: return "Could not dictate"
        }
    }

    var stateDetail: String? {
        guard case .error(let failure) = state else { return nil }
        return failure.localizedDescription
    }

    var isModelReady: Bool {
        installedModels.contains(selectedModel)
    }

    var isPreparingModel: Bool {
        preparingModel != nil
    }

    var canChangeModel: Bool {
        guard preparingModel == nil,
              switchingModel == nil,
              removingModel == nil,
              !shortcutPreflighting,
              !shortcutStarting else {
            return false
        }
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
            guard canChangeModel else { return }
            sessionDisplayID = nil
            #if DEBUG
            let shortcutStartTime = ProcessInfo.processInfo.systemUptime
            #endif
            shortcutPreflighting = true
            // The launch scan performs the full integrity checks once. Normal
            // shortcut activation uses that cached result instead of hashing
            // hundreds of megabytes before the microphone can start.
            await loadInitialModelStatusIfNeeded()
            #if DEBUG
            let modelMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - shortcutStartTime) * 1_000).rounded()
            )
            dictationLatencyLogger.notice(
                "stage=modelPreflight ms=\(modelMilliseconds, privacy: .public)"
            )
            #endif
            guard installedModels.contains(selectedModel) else {
                shortcutPreflighting = false
                shortcutStarting = false
                receive(.error(.modelNotInstalled))
                DictationModelDownloadPromptController.shared.present()
                return
            }
            await controller.hotKeyDown()
            shortcutPreflighting = false
        case .keyUp:
            await controller.hotKeyUp()
        case .cancel:
            await controller.cancel()
        }
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
        try await transcriber.transcribe(audio)
    }
    #endif

    func downloadModel(_ model: DictationModelID) {
        guard canChangeModel, !installedModels.contains(model) else { return }
        preparingModel = model
        modelErrors[model] = nil
        Task {
            do {
                try await transcriber.install(model)
                installedModels.insert(model)
            } catch {
                modelErrors[model] = "Could not download this model. Check your connection and try again."
            }
            if preparingModel == model {
                preparingModel = nil
            }
        }
    }

    func selectModel(_ model: DictationModelID) {
        guard canChangeModel,
              model != selectedModel,
              installedModels.contains(model) else { return }
        switchingModel = model
        modelErrors[model] = nil
        Task {
            do {
                try await transcriber.selectModel(model)
                selectedModel = model
                UserDefaults.standard.set(model.rawValue, forKey: Self.selectedModelKey)
            } catch {
                modelErrors[model] = "Gojo could not switch models. Try again."
            }
            if switchingModel == model {
                switchingModel = nil
            }
        }
    }

    func removeModel(_ model: DictationModelID) {
        guard canChangeModel, installedModels.contains(model) else { return }
        removingModel = model
        modelErrors[model] = nil
        Task {
            var removalError: String?
            do {
                try await transcriber.removeModel(model)
            } catch {
                removalError = "Gojo could not remove this model. Try again."
            }
            let isStillInstalled = await transcriber.isModelInstalled(model)
            if isStillInstalled {
                installedModels.insert(model)
            } else {
                installedModels.remove(model)
            }
            modelErrors[model] = removalError
            if removingModel == model {
                removingModel = nil
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
            task = Task { [transcriber] in
                await Self.scanInstalledModels(using: transcriber)
            }
            initialModelStatusTask = task
        }
        installedModels = await task.value
        hasLoadedInitialModelStatus = true
        initialModelStatusTask = nil
    }

    private func receive(_ newState: DictationState) {
        shortcutStarting = false
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

    fileprivate func setSessionDisplayID(_ displayID: CGDirectDisplayID?) {
        sessionDisplayID = displayID
    }
}

extension DictationFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Download a voice model in Gojo Settings first."
        case .microphonePermissionDenied:
            return "Allow Gojo to use the microphone in System Settings, then try again."
        case .targetUnavailable(let detail):
            return detail
        case .captureFailed:
            return "Gojo could not use the microphone. Check your microphone and try again."
        case .transcriptionFailed:
            return "Gojo could not transcribe that recording. Try again."
        case .emptyTranscript:
            return "Gojo did not hear anything."
        case .insertionFailed(let detail):
            return detail
        }
    }
}
