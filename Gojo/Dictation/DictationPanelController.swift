import AppKit
import Combine
import QuartzCore
import SwiftUI
import os

private struct DictationPanelPreferences: Codable {
    var preferredDisplayID: String?
    var positions: [String: DictationPanelSavedPosition] = [:]
}

@MainActor
final class DictationPanelController {
    static let shared = DictationPanelController()
    private static let preferencesKey = "gojo.dictation.panel.placement.v1"

    private let service = GojoDictationService.shared
    private let model = DictationPanelModel()
    private var panel: DictationFloatingPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var isObserving = false
    private var suppressUntilInactive = false
    private var explicitlyDismissed = false
    private var isPanelStartPending = false
    private var displayedOnID: String?
    private var dismissalTask: Task<Void, Never>?
    private var emptyCompletionTask: Task<Void, Never>?
    private var preferences: DictationPanelPreferences
    private var lastScreens: [DictationPanelScreen] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.preferencesKey),
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
            .sink { [weak self] text, message in
                guard let self, !self.model.isPreview else { return }
                self.model.recoveryText = text
                self.model.recoveryMessage = message
                if !text.isEmpty {
                    self.dismissalTask?.cancel()
                    self.dismissalTask = nil
                    if !self.explicitlyDismissed, !self.suppressUntilInactive { self.presentPanel() }
                }
                self.resizePanel()
                if text.isEmpty, case .error = self.model.state { self.scheduleErrorDismissal() }
            }
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
            .sink { [weak self] completion, id in
                guard let self, !self.model.isPreview else { return }
                self.emptyCompletionTask?.cancel()
                guard case .empty(let reason) = completion, let id else {
                    self.model.emptyCompletion = nil
                    self.model.completionAttentionID = nil
                    return
                }
                self.dismissalTask?.cancel()
                self.model.emptyCompletion = reason
                self.model.completionAttentionID = id
                if !self.explicitlyDismissed, !self.suppressUntilInactive { self.presentPanel() }
                self.emptyCompletionTask = Task { [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(2))
                        guard let self else { return }
                        while self.model.showsDetails { try await Task.sleep(for: .milliseconds(50)) }
                        guard !Task.isCancelled, self.model.completionAttentionID == id else { return }
                        self.model.emptyCompletion = nil
                        self.model.completionAttentionID = nil
                        if !self.isActive(self.model.state), self.model.shouldHideWhenFinished {
                            await self.fadeOutPanel()
                        }
                    } catch {}
                }
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &subscriptions)
    }

    func show() {
        startObserving()
        dismissalTask?.cancel()
        dismissalTask = nil
        suppressUntilInactive = false
        explicitlyDismissed = false
        if !model.isPreview { synchronizePresentation() }
        presentPanel(onPointerDisplay: !isActive(service.state))
    }

    func dismiss() {
        explicitlyDismissed = true
        emptyCompletionTask?.cancel()
        emptyCompletionTask = nil
        model.emptyCompletion = nil
        model.completionAttentionID = nil
        dismissalTask?.cancel()
        dismissalTask = nil
        if model.isPreview {
            endPreview()
        } else {
            suppressUntilInactive = isActive(service.state) || isPanelStartPending
            isPanelStartPending = false
            service.cancel { [weak self] in
                self?.suppressUntilInactive = false
            }
        }
        model.showsDetails = false
        panel?.orderOut(nil)
        model.clearWaveform()
    }

    func resetPosition() {
        preferences = DictationPanelPreferences()
        UserDefaults.standard.removeObject(forKey: Self.preferencesKey)
        displayedOnID = nil
        if panel?.isVisible == true { placePanel(preferredDisplayID: nil) }
    }

    #if DEBUG
    var debugFrame: CGRect? { panel?.frame }
    var debugIsKey: Bool { panel?.isKeyWindow ?? false }

    func previewFadeOut() {
        guard !isActive(service.state) else { return }
        showPreview(state: .error(.captureFailed("Microphone unavailable. Check your input device and try again.")))
        scheduleErrorDismissal()
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
        dismissalTask?.cancel()
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
        model.leavePreview(recoveryText: service.recoveryText, recoveryMessage: service.recoveryMessage)
        synchronizePresentation()
        resizePanel()
    }
    #else
    private func endPreview() {}
    #endif

    private func receive(_ state: DictationState) {
        guard state == service.state else { return }
        if model.isPreview {
            guard isActive(state) else { return }
            model.leavePreview(recoveryText: service.recoveryText, recoveryMessage: service.recoveryMessage)
        }
        dismissalTask?.cancel()
        dismissalTask = nil
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
        if state == .idle, previousState != .idle, model.shouldHideWhenFinished {
            model.state = previousState
            dismissalTask = Task { [weak self] in
                guard let self else { return }
                await self.fadeOutPanel()
                guard !Task.isCancelled else { return }
                self.model.state = .idle
                self.dismissalTask = nil
            }
            return
        }
        if state != .idle { presentPanel(onPointerDisplay: isActive(state) && !isActive(previousState)) }
        resizePanel()
        if case .error = state {
            scheduleErrorDismissal()
        } else if case .succeeded = state {
            let delay: Duration = .milliseconds(model.shouldHideWhenFinished ? 120 : 900)
            dismissalTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, !self.model.isPreview,
                      case .succeeded = self.model.state else { return }
                if self.model.shouldHideWhenFinished { await self.fadeOutPanel() }
                guard !Task.isCancelled else { return }
                self.model.state = .idle
                self.dismissalTask = nil
            }
        }
    }

    private func scheduleErrorDismissal() {
        guard model.recoveryText.isEmpty, !explicitlyDismissed else { return }
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
                guard let self else { return }
                repeat {
                    while self.model.showsDetails {
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    try await Task.sleep(for: .milliseconds(180))
                } while self.model.showsDetails
                guard !Task.isCancelled, case .error = self.model.state,
                      self.model.recoveryText.isEmpty else { return }
                await self.fadeOutPanel()
                guard !Task.isCancelled else { return }
                self.dismissalTask = nil
            } catch {}
        }
    }

    private func fadeOutPanel() async {
        guard !Task.isCancelled, model.recoveryText.isEmpty, let panel, panel.isVisible else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = 0
            } completionHandler: {
                continuation.resume()
            }
        }
        guard !Task.isCancelled, model.recoveryText.isEmpty else {
            if !explicitlyDismissed, panel.isVisible { panel.alphaValue = 1 }
            return
        }
        panel.orderOut(nil)
    }

    private func synchronizePresentation() {
        model.present(service.state)
        model.activationMode = DictationModifierHotKeyMonitor.shared.activationMode
        model.targetApplicationName = service.targetApplicationName
        model.recoveryText = service.recoveryText
        model.recoveryMessage = service.recoveryMessage
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
            case .clearRecovery: model.recoveryText = ""
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
        case .clearRecovery: service.clearRecoveryText()
        case .settings:
            if let url = model.permissionSettingsURL {
                NSWorkspace.shared.open(url)
            } else {
                SettingsWindowController.shared.showWindow(tab: "Dictation")
            }
        }
    }

    private func presentPanel(onPointerDisplay: Bool = false) {
        if panel == nil {
            panel = DictationFloatingPanel(rootView: DictationPanelView(
                model: model,
                command: { [weak self] in self?.perform($0) },
                dragEnded: { [weak self] in self?.completeDrag() }
            ))
        }
        if onPointerDisplay || panel?.isVisible != true {
            placePanel(preferredDisplayID: preferences.preferredDisplayID)
        } else {
            resizePanel()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel?.animator().alphaValue = 1
        }
        panel?.orderFrontRegardless()
    }

    private func placePanel(preferredDisplayID: String?) {
        let screens = screenDescriptions()
        guard let placement = DictationPanelPlacement.restore(
            size: model.size,
            screens: screens,
            pointerDisplayID: NSScreen.screenWithMouse?.displayUUID,
            preferredDisplayID: preferredDisplayID,
            fallbackDisplayID: sessionScreen()?.displayUUID,
            positions: preferences.positions
        ) else { return }
        displayedOnID = placement.displayID
        lastScreens = screens
        panel?.setFrame(placement.frame, display: true)
    }

    private func resizePanel() {
        guard let panel, panel.isVisible,
              let screen = screenDescriptions().first(where: { $0.id == displayedOnID }) else { return }
        let frame = CGRect(origin: panel.frame.origin, size: model.size)
        panel.setFrame(DictationPanelPlacement.clamped(frame, to: screen.visibleFrame), display: true)
    }

    private func completeDrag() {
        guard let panel else { return }
        let screens = screenDescriptions()
        guard let screen = screens.max(by: {
            intersectionArea(panel.frame, $0.visibleFrame) < intersectionArea(panel.frame, $1.visibleFrame)
        }) else { return }
        let frame = DictationPanelPlacement.clamped(panel.frame, to: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        displayedOnID = screen.id
        lastScreens = screens
        guard let position = DictationPanelPlacement.savedPosition(for: frame, on: screen) else { return }
        preferences.preferredDisplayID = screen.id
        preferences.positions[screen.id] = position
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.preferencesKey)
        }
    }

    private func screensChanged() {
        guard let panel, panel.isVisible else { return }
        let screens = screenDescriptions()
        var positions = preferences.positions
        if let oldScreen = lastScreens.first(where: { $0.id == displayedOnID }),
           let position = DictationPanelPlacement.savedPosition(for: panel.frame, on: oldScreen) {
            positions[oldScreen.id] = position
        }
        guard let placement = DictationPanelPlacement.restore(
            size: model.size,
            screens: screens,
            preferredDisplayID: displayedOnID,
            fallbackDisplayID: sessionScreen()?.displayUUID,
            positions: positions
        ) else { return }
        displayedOnID = placement.displayID
        lastScreens = screens
        panel.setFrame(placement.frame, display: true)
    }

    private func screenDescriptions() -> [DictationPanelScreen] {
        NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { DictationPanelScreen(id: $0, visibleFrame: screen.visibleFrame) }
        }
    }

    private func sessionScreen() -> NSScreen? {
        NSScreen.screens.first { $0.directDisplayID == service.sessionDisplayID }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func isActive(_ state: DictationState) -> Bool {
        switch state {
        case .requestingPermission, .listening, .pausing, .paused, .transcribing, .inserting: return true
        case .idle, .succeeded, .error: return false
        }
    }
}

private final class DictationPanelHostingView: NSHostingView<DictationPanelView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class DictationFloatingPanel: NSPanel {
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
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        contentView = DictationPanelHostingView(rootView: rootView)
        setAccessibilityLabel("Gojo dictation controls")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
