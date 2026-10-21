import AppKit
import Combine
import QuartzCore
import SwiftUI
import os

private struct DictationPanelPreferences: Codable {
    var preferredDisplayID: String?
    var positions: [String: DictationPanelSavedPosition] = [:]
}

struct DictationPanelDisplays {
    var screens: @MainActor () -> [DictationPanelScreen]
    var pointerDisplayID: @MainActor () -> String?
    var sessionDisplayID: @MainActor () -> String?

    @MainActor
    static func live(service: GojoDictationService) -> DictationPanelDisplays {
        DictationPanelDisplays(
            screens: {
                NSScreen.screens.compactMap { screen in
                    screen.displayUUID.map { DictationPanelScreen(id: $0, visibleFrame: screen.visibleFrame) }
                }
            },
            pointerDisplayID: { NSScreen.screenWithMouse?.displayUUID },
            sessionDisplayID: {
                (NSScreen.screens.first { $0.directDisplayID == service.sessionDisplayID }
                    ?? NSScreen.main ?? NSScreen.screens.first)?.displayUUID
            }
        )
    }
}

private enum DictationPanelExpiryAction: Equatable {
    case hide
    case expireRecovery(String)
    case finishSuccess
    case clearEmpty(UUID)
}

private struct DictationPanelExpiryPlan: Equatable {
    var grace: Duration
    var action: DictationPanelExpiryAction
    var state: DictationState
    var identity: String?
}

@MainActor
final class DictationPanelController {
    static let shared = DictationPanelController()
    private static let preferencesKey = "gojo.dictation.panel.placement.v1"
    private static let recoveryGrace: Duration = .seconds(10)
    private static let noticeGrace: Duration = .seconds(2)

    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias PanelFade = @MainActor (NSPanel) async -> Void

    private let service: GojoDictationService
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let displays: DictationPanelDisplays
    private let sleeper: Sleeper
    private let fade: PanelFade
    private let model = DictationPanelModel()
    private var panel: DictationFloatingPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var isObserving = false
    private var suppressUntilInactive = false
    private var explicitlyDismissed = false
    private var isPanelStartPending = false
    private var displayedOnID: String?
    private var preferences: DictationPanelPreferences
    private var lastServiceState: DictationState?

    private var isPresented = false
    private var isHiding = false
    private var presentationGeneration: UInt64 = 0
    private var expiryTask: Task<Void, Never>?
    private var armedPlan: DictationPanelExpiryPlan?
    private var pointerInside = false
    private var previewExpiry = false
    private var canonicalRecoveryText = ""
    private var consumedRecoveryText: String?
    private var handledEmptyAttentionID: UUID?

    init(
        service: GojoDictationService? = nil,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        displays: DictationPanelDisplays? = nil,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) },
        fade: PanelFade? = nil
    ) {
        let service = service ?? GojoDictationService.shared
        self.service = service
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.displays = displays ?? .live(service: service)
        self.sleeper = sleeper
        self.fade = fade ?? Self.animateFadeOut
        if let data = defaults.data(forKey: Self.preferencesKey),
           let saved = try? JSONDecoder().decode(DictationPanelPreferences.self, from: data) {
            preferences = saved
            preferences.positions = saved.positions.filter { $0.value.isValid }
        } else {
            preferences = DictationPanelPreferences()
        }
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        service.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.receive(state) }
            .store(in: &subscriptions)
        service.$audioLevel
            .throttle(for: .milliseconds(40), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] level in
                guard let self, self.panel?.isVisible == true,
                      !self.model.isPreview, self.model.state == .listening else { return }
                self.model.appendAudioLevel(level)
            }
            .store(in: &subscriptions)
        service.$targetApplicationName
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                guard let self, !self.model.isPreview else { return }
                self.model.targetApplicationName = name
            }
            .store(in: &subscriptions)
        Publishers.CombineLatest(service.$recoveryText, service.$recoveryMessage)
            .receive(on: RunLoop.main)
            .sink { [weak self] text, message in self?.receiveRecovery(text: text, message: message) }
            .store(in: &subscriptions)
        service.$provisionalPreview
            .receive(on: RunLoop.main)
            .sink { [weak self] preview in
                guard let self, !self.model.isPreview else { return }
                self.model.provisionalPreview = preview
            }
            .store(in: &subscriptions)
        service.$activeIntent
            .receive(on: RunLoop.main)
            .sink { [weak self] intent in
                guard let self, !self.model.isPreview else { return }
                self.model.activeIntent = intent
            }
            .store(in: &subscriptions)
        Publishers.CombineLatest(service.$lastCompletion, service.$completionAttentionID)
            .receive(on: RunLoop.main)
            .sink { [weak self] completion, id in self?.receiveCompletion(completion, id: id) }
            .store(in: &subscriptions)
        Publishers.CombineLatest(model.$capsuleHovered, model.$detailsHovered)
            .sink { [weak self] capsule, details in self?.hoverChanged(capsule || details) }
            .store(in: &subscriptions)
        model.$showsDetails
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shown in
                guard let self else { return }
                if !shown { self.model.detailsHovered = false }
                self.rearmExpiry()
            }
            .store(in: &subscriptions)
        notificationCenter.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)
        service.$sessionDisplayID
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reassertPanel(followSession: true) }
            .store(in: &subscriptions)
        workspaceNotificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reassertPanel() }
            .store(in: &subscriptions)
        workspaceNotificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reassertPanel() }
            .store(in: &subscriptions)
    }

    func show() {
        startObserving()
        cancelExpiry()
        suppressUntilInactive = false
        explicitlyDismissed = false
        if !model.isPreview {
            synchronizePresentation()
            if !isActive(service.state), model.recoveryText.isEmpty, model.emptyCompletion == nil {
                model.present(.idle)
            }
        }
        presentPanel(onPointerDisplay: !isActive(service.state))
        if !model.isPreview, !model.recoveryText.isEmpty { model.showsDetails = true }
    }

    func dismiss() {
        explicitlyDismissed = true
        model.emptyCompletion = nil
        model.completionAttentionID = nil
        cancelExpiry()
        if model.isPreview {
            endPreview()
        } else {
            discardRecovery(model.recoveryText)
            suppressUntilInactive = isActive(service.state) || isPanelStartPending
            isPanelStartPending = false
            service.cancel { [weak self] in
                self?.suppressUntilInactive = false
            }
        }
        hidePanelImmediately()
        model.clearWaveform()
    }

    func resetPosition() {
        preferences = DictationPanelPreferences()
        defaults.removeObject(forKey: Self.preferencesKey)
        displayedOnID = nil
        if panel?.isVisible == true { placePanel(preferredDisplayID: nil) }
    }

    #if DEBUG
    var debugFrame: CGRect? { panel?.frame }
    var debugIsKey: Bool { panel?.isKeyWindow ?? false }
    var debugPanel: NSPanel? { panel }
    var debugModel: DictationPanelModel { model }
    func debugPerform(_ command: DictationPanelCommand) { perform(command) }
    func debugCompleteDrag() { completeDrag() }

    func previewFadeOut() {
        guard !isActive(service.state) else { return }
        showPreview(state: .error(.captureFailed("Microphone unavailable. Check your input device and try again.")))
        previewExpiry = true
        rearmExpiry()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(2100))
            guard let self, self.model.isPreview, let panel = self.panel else { return }
            var values: [String] = []
            for _ in 0..<40 {
                values.append(String(format: "%.3f:%d:%d", panel.alphaValue, panel.isVisible ? 1 : 0, self.model.showsDetails ? 1 : 0))
                try? await Task.sleep(for: .milliseconds(16))
            }
            let logger = Logger(subsystem: "rohoswagger.gojo.dictation", category: "workspace")
            logger.notice("fadeTrace=\(values.joined(separator: ","), privacy: .public)")
        }
    }

    func exportPreviewImage() throws -> URL? {
        guard model.isPreview else { return nil }
        let popover = NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") }
        guard let view = (popover ?? panel)?.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gojo-dictation-panel.png")
        try data.write(to: url, options: .atomic)
        return url
    }

    func showPreview(state: DictationState, recoveryText: String = "", recoveryMessage: String? = nil) {
        guard !isActive(service.state) else { return }
        startObserving()
        cancelExpiry()
        previewExpiry = false
        explicitlyDismissed = false
        model.isPreview = true
        model.present(state)
        model.activationMode = .voiceMode
        model.targetApplicationName = "TextEdit"
        model.recoveryText = recoveryText
        model.recoveryMessage = recoveryMessage
        model.samples = (0..<80).map { index in
            Float([0.02, 0.08, 0.18, 0.42, 0.7, 0.36, 0.14, 0.05][index % 8])
        }
        presentPanel()
    }

    func endPreview() {
        previewExpiry = false
        model.leavePreview(recoveryText: service.recoveryText, recoveryMessage: service.recoveryMessage)
        synchronizePresentation()
        resizePanel()
        rearmExpiry()
    }
    #else
    private func endPreview() {}
    #endif

    private func receive(_ state: DictationState) {
        guard state == service.state else { return }
        if state == lastServiceState {
            switch state {
            case .error: break
            default: return
            }
        }
        let previousServiceState = lastServiceState
        lastServiceState = state
        if isActive(state), previousServiceState.map({ !isActive($0) }) ?? true {
            consumedRecoveryText = nil
            canonicalRecoveryText = ""
        }
        if model.isPreview {
            guard isActive(state) else { return }
            previewExpiry = false
            model.leavePreview(recoveryText: service.recoveryText, recoveryMessage: service.recoveryMessage)
        }
        cancelExpiry()
        let previousState = model.state
        let wasListening = previousState == .listening
        model.present(state)
        if state != .idle { isPanelStartPending = false }
        switch state {
        case .requestingPermission, .listening, .pausing, .paused:
            model.activationMode = DictationModifierHotKeyMonitor.shared.activationMode
        default: break
        }
        model.targetApplicationName = service.targetApplicationName
        if state != .listening || !wasListening { model.clearWaveform() }

        if suppressUntilInactive {
            if !isActive(state) { suppressUntilInactive = false }
            return
        }
        if isActive(state) { explicitlyDismissed = false }
        guard !explicitlyDismissed else { return }
        if state == .idle, previousState != .idle, model.recoveryText.isEmpty, model.shouldHideWhenFinished {
            model.state = previousState
            isHiding = true
            expiryTask = Task { [weak self] in
                guard let self, await self.fadeOutPanel() else { return }
                self.model.state = .idle
            }
            return
        }
        if state != .idle { presentPanel(onPointerDisplay: isActive(state) && !isActive(previousState)) }
        resizePanel()
        rearmExpiry()
    }

    private func receiveRecovery(text: String, message: String?) {
        guard !model.isPreview else { return }
        let previous = canonicalRecoveryText
        canonicalRecoveryText = text
        if let consumed = consumedRecoveryText {
            if text == consumed { return }
            consumedRecoveryText = nil
        }
        let resolved = model.updateRecoveryText(text, message: message)
        if !text.isEmpty, text != previous, !explicitlyDismissed, !suppressUntilInactive { presentPanel() }
        resizePanel()
        if resolved, !isActive(service.state) {
            hidePanelImmediately()
        } else {
            rearmExpiry()
        }
    }

    private func receiveCompletion(_ completion: DictationCompletion?, id: UUID?) {
        guard !model.isPreview else { return }
        guard case .empty(let reason) = completion, let id else {
            model.emptyCompletion = nil
            model.completionAttentionID = nil
            rearmExpiry()
            return
        }
        guard id != handledEmptyAttentionID else { return }
        handledEmptyAttentionID = id
        model.emptyCompletion = reason
        model.completionAttentionID = id
        if !explicitlyDismissed, !suppressUntilInactive { presentPanel() } else { rearmExpiry() }
    }

    private func hoverChanged(_ inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        rearmExpiry(restart: true)
    }

    private func expiryPlan() -> DictationPanelExpiryPlan? {
        guard isPresented, !model.isPreview || previewExpiry else { return nil }
        let state = model.state
        func plan(_ grace: Duration, _ action: DictationPanelExpiryAction) -> DictationPanelExpiryPlan {
            DictationPanelExpiryPlan(grace: grace, action: action, state: state, identity: model.attentionIdentity)
        }
        let emptyID = model.emptyCompletion != nil ? model.completionAttentionID : nil
        let recovery = model.recoveryText
        if !recovery.isEmpty { return plan(Self.recoveryGrace, .expireRecovery(recovery)) }
        if isActive(state) { return emptyID.map { plan(Self.noticeGrace, .clearEmpty($0)) } }
        if let emptyID { return plan(Self.noticeGrace, .clearEmpty(emptyID)) }
        if case .error = state { return plan(Self.noticeGrace, .hide) }
        if case .succeeded = state {
            return plan(model.shouldHideWhenFinished ? .milliseconds(120) : .milliseconds(900), .finishSuccess)
        }
        return nil
    }

    private func rearmExpiry(restart: Bool = false) {
        guard !isHiding else { return }
        guard !pointerInside, let plan = expiryPlan() else {
            cancelExpiry()
            return
        }
        guard restart || armedPlan != plan else { return }
        cancelExpiry()
        armedPlan = plan
        let generation = presentationGeneration
        expiryTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.sleeper(plan.grace) } catch { return }
            guard !Task.isCancelled, generation == self.presentationGeneration else { return }
            self.armedPlan = nil
            await self.runExpiry(plan.action)
        }
    }

    private func cancelExpiry() {
        expiryTask?.cancel()
        expiryTask = nil
        armedPlan = nil
    }

    private func runExpiry(_ action: DictationPanelExpiryAction) async {
        switch action {
        case .expireRecovery(let text):
            guard model.recoveryText == text else { return }
            discardRecovery(text)
            if isActive(service.state) {
                model.showsDetails = false
            } else {
                _ = await fadeOutPanel()
            }
        case .hide:
            _ = await fadeOutPanel()
        case .finishSuccess:
            if model.shouldHideWhenFinished, !(await fadeOutPanel()) { return }
            if case .succeeded = model.state { model.state = .idle }
        case .clearEmpty(let id):
            guard model.completionAttentionID == id else { return }
            model.emptyCompletion = nil
            model.completionAttentionID = nil
            if !isActive(model.state), model.shouldHideWhenFinished { _ = await fadeOutPanel() }
        }
    }

    /// Forgets a saved transcript: the optimistic model clear plus a
    /// snapshot-matched service clear, so a newer transcript is never lost.
    private func discardRecovery(_ text: String) {
        guard !text.isEmpty else { return }
        if canonicalRecoveryText == text { consumedRecoveryText = text }
        model.clearRecoveryText(matching: text)
        service.clearRecoveryText(matching: text)
    }

    /// Returns true only when this fade finished and hid the panel; a newer
    /// presentation or an immediate hide supersedes it and leaves the panel alone.
    private func fadeOutPanel() async -> Bool {
        guard isPresented, let panel, panel.isVisible else {
            hidePanelImmediately()
            return true
        }
        isHiding = true
        presentationGeneration &+= 1
        let generation = presentationGeneration
        model.showsDetails = false
        await fade(panel)
        guard generation == presentationGeneration else { return false }
        hidePanelImmediately()
        return true
    }

    private func hidePanelImmediately() {
        cancelExpiry()
        presentationGeneration &+= 1
        isHiding = false
        isPresented = false
        model.showsDetails = false
        model.capsuleHovered = false
        model.detailsHovered = false
        panel?.orderOut(nil)
    }

    private static func animateFadeOut(_ panel: NSPanel) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: {
                continuation.resume()
            }
        }
    }

    private func synchronizePresentation() {
        let text = service.recoveryText
        canonicalRecoveryText = text
        if consumedRecoveryText != text { consumedRecoveryText = nil }
        let consumed = consumedRecoveryText != nil
        model.present(service.state)
        model.activationMode = DictationModifierHotKeyMonitor.shared.activationMode
        model.targetApplicationName = service.targetApplicationName
        model.recoveryText = consumed ? "" : text
        model.recoveryMessage = consumed ? nil : service.recoveryMessage
        model.provisionalPreview = service.provisionalPreview
        model.activeIntent = service.activeIntent
    }

    private func perform(_ command: DictationPanelCommand) {
        if model.isPreview {
            switch command {
            case .start, .resume: model.state = .listening
            case .pause: model.state = .paused
            case .finish: model.state = .transcribing
            case .dismiss: dismiss()
            case .clearRecovery(let text): model.clearRecoveryText(matching: text)
            case .settings: break
            }
            resizePanel()
            return
        }
        switch command {
        case .start:
            isPanelStartPending = true
            service.startVoiceMode()
        case .pause: service.pauseVoiceMode()
        case .resume: service.resumeVoiceMode()
        case .finish: service.finishVoiceMode()
        case .dismiss: dismiss()
        case .clearRecovery(let text):
            discardRecovery(text)
            if !text.isEmpty, model.recoveryText.isEmpty, !isActive(service.state) {
                hidePanelImmediately()
            } else {
                rearmExpiry()
            }
        case .settings:
            if let url = model.permissionSettingsURL {
                NSWorkspace.shared.open(url)
            } else {
                SettingsWindowController.shared.showWindow(tab: "Dictation")
            }
        }
    }

    private func presentPanel(onPointerDisplay: Bool = false) {
        cancelExpiry()
        if panel == nil {
            panel = DictationFloatingPanel(rootView: DictationPanelView(
                model: model,
                command: { [weak self] in self?.perform($0) },
                dragEnded: { [weak self] in self?.completeDrag() }
            ))
        }
        presentationGeneration &+= 1
        isHiding = false
        isPresented = true
        if onPointerDisplay || panel?.isVisible != true {
            placePanel(preferredDisplayID: preferences.preferredDisplayID)
        } else {
            resizePanel()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel?.animator().alphaValue = 1
        }
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        rearmExpiry()
    }

    /// Re-asserts an intentionally visible panel after a Space or frontmost-app
    /// change without activating Gojo or taking key focus. Timer-hidden and
    /// manually dismissed panels stay hidden.
    private func reassertPanel(followSession: Bool = false) {
        guard isPresented, !isHiding, let panel else { return }
        panel.level = DictationFloatingPanel.presentationLevel
        panel.collectionBehavior = DictationFloatingPanel.presentationBehavior
        panel.orderFrontRegardless()
        let target = followSession ? displays.sessionDisplayID() : displays.pointerDisplayID()
        screensChanged(preferredDisplayID: target)
    }

    private func placePanel(preferredDisplayID: String?) {
        let screens = displays.screens()
        guard let placement = DictationPanelPlacement.restore(
            size: model.size,
            screens: screens,
            pointerDisplayID: displays.pointerDisplayID(),
            preferredDisplayID: preferredDisplayID,
            fallbackDisplayID: displays.sessionDisplayID(),
            positions: preferences.positions
        ) else { return }
        displayedOnID = placement.displayID
        panel?.setFrame(placement.frame, display: true)
    }

    private func resizePanel() {
        guard let panel, panel.isVisible,
              let screen = displays.screens().first(where: { $0.id == displayedOnID }) else { return }
        let frame = CGRect(origin: panel.frame.origin, size: model.size)
        panel.setFrame(DictationPanelPlacement.clamped(frame, to: screen.visibleFrame), display: true)
    }

    private func completeDrag() {
        guard let panel else { return }
        let screens = displays.screens()
        guard let screen = screens.max(by: {
            intersectionArea(panel.frame, $0.visibleFrame) < intersectionArea(panel.frame, $1.visibleFrame)
        }) else { return }
        let frame = DictationPanelPlacement.clamped(panel.frame, to: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        displayedOnID = screen.id
        guard let position = DictationPanelPlacement.savedPosition(for: frame, on: screen) else { return }
        preferences.preferredDisplayID = screen.id
        preferences.positions[screen.id] = position
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: Self.preferencesKey)
        }
    }

    private func screensChanged(preferredDisplayID: String? = nil) {
        guard let panel, panel.isVisible else { return }
        let screens = displays.screens()
        guard let placement = DictationPanelPlacement.restore(
            size: model.size,
            screens: screens,
            preferredDisplayID: preferredDisplayID ?? displayedOnID,
            fallbackDisplayID: displays.sessionDisplayID(),
            positions: preferences.positions
        ) else { return }
        displayedOnID = placement.displayID
        panel.setFrame(placement.frame, display: true)
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func isActive(_ state: DictationState) -> Bool {
        DictationPanelModel.isActiveSession(state)
    }
}

private final class DictationPanelHostingView: NSHostingView<DictationPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class DictationFloatingPanel: NSPanel {
    static let presentationLevel = NSWindow.Level.statusBar
    static let presentationBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle, .stationary
    ]

    init(rootView: DictationPanelView) {
        super.init(
            contentRect: CGRect(origin: .zero, size: DictationPanelPlacement.defaultSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        title = "Gojo voice controls"
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        isFloatingPanel = true
        level = Self.presentationLevel
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = Self.presentationBehavior
        contentView = DictationPanelHostingView(rootView: rootView)
        setAccessibilityLabel("Gojo dictation controls")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
