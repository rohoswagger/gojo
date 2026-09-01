//
//  GojoApp.swift
//  GojoApp
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import os
import Sparkle
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Default(.fluxEnabled) var fluxEnabled
    @Environment(\.openWindow) var openWindow
    @StateObject private var accessibilityFlow = MenuBarAccessibilityAuthorizationFlow()

    let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("Gojo", image: "gojo-menubar", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.showWindow()
                }
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Button("Enable Accessibility…") {
                accessibilityFlow.start()
            }
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Toggle("Night Shift", isOn: $fluxEnabled)
            Divider()
            Button("Restart Gojo") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// With @NSApplicationDelegateAdaptor, `NSApp.delegate` is a private SwiftUI
    /// wrapper — `NSApp.delegate as? AppDelegate` fails. Anything that needs the
    /// real delegate (e.g. WindowPowerSession routing for keyboard shortcuts)
    /// must use this reference instead.
    private(set) static weak var shared: AppDelegate?

    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: GojoViewModel] = [:] // UUID -> GojoViewModel
    var window: NSWindow?
    let vm: GojoViewModel = .init()
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var systemSleepObserver: Any?
    private var systemWakeObserver: Any?
    private var dictationEscapeGlobalMonitor: Any?
    private var dictationEscapeLocalMonitor: Any?
    private var dictationAccessibilityObserver: Any?
    private var cancellables = Set<AnyCancellable>()
#if DEBUG
    private var dictationCaptureE2EProbeObserver: Any?
    private var dictationE2EProbeObserver: Any?
    private var dictationModelE2EProbeObserver: Any?
    private var dictationInferenceE2EProbeObserver: Any?
    private var dictationShortcutE2EProbeObserver: Any?
    private var dictationEventTapShortcutE2EProbeObserver: Any?
    private var dictationOpaquePasteE2EProbeObserver: Any?
    private var dictationUnicodeTypingE2EProbeObserver: Any?
    private var dictationRealMicrophoneShortcutE2EObserver: Any?
    private var onboardingMusicE2EProbeObserver: Any?
    private var settingsE2EProbeObserver: Any?
#endif
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            await DictationModifierHotKeyMonitor.shared.recoverIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        if let observer = systemSleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            systemSleepObserver = nil
        }
        if let observer = systemWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            systemWakeObserver = nil
        }
        if let monitor = dictationEscapeGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            dictationEscapeGlobalMonitor = nil
        }
        if let monitor = dictationEscapeLocalMonitor {
            NSEvent.removeMonitor(monitor)
            dictationEscapeLocalMonitor = nil
        }
        if let observer = dictationAccessibilityObserver {
            NotificationCenter.default.removeObserver(observer)
            dictationAccessibilityObserver = nil
        }
#if DEBUG
        if let observer = dictationCaptureE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationCaptureE2EProbeObserver = nil
        }
        if let observer = dictationE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationE2EProbeObserver = nil
        }
        if let observer = dictationModelE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationModelE2EProbeObserver = nil
        }
        if let observer = dictationInferenceE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationInferenceE2EProbeObserver = nil
        }
        if let observer = dictationShortcutE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationShortcutE2EProbeObserver = nil
        }
        if let observer = dictationEventTapShortcutE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationEventTapShortcutE2EProbeObserver = nil
        }
        if let observer = dictationOpaquePasteE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationOpaquePasteE2EProbeObserver = nil
        }
        if let observer = dictationUnicodeTypingE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationUnicodeTypingE2EProbeObserver = nil
        }
        if let observer = dictationRealMicrophoneShortcutE2EObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            dictationRealMicrophoneShortcutE2EObserver = nil
        }
        if let observer = onboardingMusicE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            onboardingMusicE2EProbeObserver = nil
        }
        if let observer = settingsE2EProbeObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            settingsE2EProbeObserver = nil
        }
#endif
        MusicManager.shared.destroy()
        ClipboardStateViewModel.shared.stop()
        FluxManager.shared.shutdown()
        Task { @MainActor in
            DictationModifierHotKeyMonitor.shared.stop()
            GojoDictationService.shared.terminate()
        }
        // Always restore the native ⌘-Tab switcher: the symbolic-hotkey change
        // persists system-wide, so we must undo it even on quit.
        AltTabHotKeyMonitor.shared.restoreNativeSwitcher()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        DictationModifierHotKeyMonitor.shared.cancelCurrentSession()
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        Task {
            await DictationModifierHotKeyMonitor.shared.recoverIfNeeded()
        }
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? GojoSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? GojoSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? GojoSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? GojoSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard !coordinator.firstLaunch, Defaults[.shelfEnabled], let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func createGojoWindow(for screen: NSScreen, with viewModel: GojoViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = GojoSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NSHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

#if DEBUG
        dictationCaptureE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-capture-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                .int32Value
            Task { @MainActor in
                await self?.runDictationCaptureE2EProbe(expectedPID: expectedPID)
            }
        }
        dictationE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                .int32Value
            Task { @MainActor in
                await self?.runDictationInsertionE2EProbe(expectedPID: expectedPID)
            }
        }
        dictationModelE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-model-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                .int32Value
            Task { @MainActor in
                await self?.runDictationModelE2EProbe(expectedPID: expectedPID)
            }
        }
        dictationInferenceE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-inference-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runDictationInferenceE2EProbe()
            }
        }
        dictationShortcutE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-shortcut-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.runDictationShortcutE2EProbe()
            }
        }
        dictationEventTapShortcutE2EProbeObserver =
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(
                    "rohoswagger.gojo.dictation-event-tap-shortcut-e2e-probe"
                ),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let runID = notification.userInfo?["runID"] as? String ?? "unknown"
                Task { @MainActor in
                    await self?.runDictationEventTapShortcutE2EProbe(runID: runID)
                }
            }
        dictationOpaquePasteE2EProbeObserver =
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(
                    "rohoswagger.gojo.dictation-opaque-paste-e2e-probe"
                ),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let moveFocus = (notification.userInfo?["moveFocusAfterCapture"] as? NSNumber)?
                    .boolValue == true
                let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                    .int32Value
                Task { @MainActor in
                    await self?.runDictationOpaquePasteE2EProbe(
                        moveFocusAfterCapture: moveFocus,
                        expectedPID: expectedPID
                    )
                }
            }
        dictationUnicodeTypingE2EProbeObserver =
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(
                    "rohoswagger.gojo.dictation-unicode-typing-e2e-probe"
                ),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let transcript = notification.userInfo?["transcript"] as? String
                let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                    .int32Value
                Task { @MainActor in
                    await self?.runDictationUnicodeTypingE2EProbe(
                        transcript: transcript,
                        expectedPID: expectedPID
                    )
                }
            }
        dictationRealMicrophoneShortcutE2EObserver =
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(
                    "rohoswagger.gojo.dictation-real-microphone-shortcut-e2e"
                ),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let action = notification.userInfo?["action"] as? String
                let expectedPID = (notification.userInfo?["expectedPID"] as? NSNumber)?
                    .int32Value
                Task { @MainActor in
                    guard await self?.focusDictationE2ETarget(expectedPID) != false else {
                        return
                    }
                    switch action {
                    case "down":
                        GojoDictationService.sendShortcutEvent(.keyDown)
                        await self?.stabilizeDictationE2ETargetFocus(
                            expectedPID,
                            attempts: 16
                        )
                    case "up":
                        GojoDictationService.sendShortcutEvent(.keyUp)
                        await self?.stabilizeDictationE2ETargetFocus(
                            expectedPID,
                            attempts: 120
                        )
                    default:
                        break
                    }
                }
            }
        onboardingMusicE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.onboarding-music-e2e-probe"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onboardingWindowController?.close()
            self?.onboardingWindowController = nil
            self?.showOnboardingWindow(step: .musicPermission)
        }
        settingsE2EProbeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.settings-e2e-probe"),
            object: nil,
            queue: .main
        ) { _ in
            SettingsWindowController.shared.showWindow(tab: "Dictation")
        }
#endif

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition(changeAlpha: true)
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            Task { @MainActor in
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        systemSleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                DictationModifierHotKeyMonitor.shared.cancelCurrentSession()
            }
        }

        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await DictationModifierHotKeyMonitor.shared.recoverIfNeeded()
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self, !LicenseManager.shared.isLocked else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        dictationAccessibilityObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityAuthorizationChanged,
            object: nil,
            queue: .main
        ) { notification in
            let granted = notification.userInfo?["granted"] as? Bool ?? false
            Task { @MainActor in
                if granted {
                    await DictationModifierHotKeyMonitor.shared.start()
                } else {
                    DictationModifierHotKeyMonitor.shared.accessibilityAuthorizationWasRevoked()
                }
            }
        }
        XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        // Prompt here rather than failing quietly: without Accessibility the
        // event tap is never created, so the dictation chord does nothing and
        // the user gets no indication why.
        Task { await DictationModifierHotKeyMonitor.shared.start(promptIfNeeded: true) }

        dictationEscapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    DictationModifierHotKeyMonitor.shared.cancelCurrentSession()
                }
            }
        }
        dictationEscapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    DictationModifierHotKeyMonitor.shared.cancelCurrentSession()
                }
            }
            return event
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self, !self.coordinator.firstLaunch else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.close()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard Defaults[.clipboardHistoryEnabled] else { return }

                let viewModel = self.viewModelForCurrentMouseLocation()
                let targetWindow = self.windowFor(viewModel: viewModel)
                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                self.coordinator.currentView = .clipboard
                ClipboardStateViewModel.shared.requestSearchFocus()

                if viewModel.notchState == .closed {
                    viewModel.open()
                }

                targetWindow?.makeKeyAndOrderFront(nil)
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSearchPanel) {
            Task { @MainActor in
                guard Defaults[.searchEnabled] else { return }
                SearchPanelController.shared.toggle()
            }
        }

        WindowShortcutController.shared.register()

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createGojoWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()
        ClipboardStateViewModel.shared.start()
        FluxManager.shared.start()
        AltTabManager.shared.start()

        Defaults.publisher(keys: .searchEnabled, .searchOverrideCommandSpace, options: [])
            .sink { _ in
                Task { @MainActor in
                    await SearchHotkeyInterceptor.shared.start()
                }
            }
            .store(in: &cancellables)
        Task { @MainActor in
            await SearchHotkeyInterceptor.shared.start()
        }

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens
    }

#if DEBUG
    @MainActor
    private func runDictationShortcutE2EProbe() async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "shortcut")
        GojoDictationService.sendShortcutEvent(.keyDown)

        for _ in 0..<80 {
            let state = GojoDictationService.shared.state
            if state == .listening {
                break
            }
            if case .error = state {
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }

        let state = GojoDictationService.shared.state
        let success = state == .listening
        let detail = GojoDictationService.shared.stateDetail ?? "none"
        logger.notice(
            "result success=\(success, privacy: .public) state=\(String(describing: state), privacy: .public) detail=\(detail, privacy: .public)"
        )
        // Keep the real listening state visible long enough for the DEBUG UI probe to inspect it.
        if success {
            try? await Task.sleep(for: .seconds(4))
        }
        GojoDictationService.sendShortcutEvent(.cancel)
    }

    @MainActor
    private func runDictationEventTapShortcutE2EProbe(runID: String) async {
        let logger = Logger(
            subsystem: "rohoswagger.gojo.dictation-e2e",
            category: "event-tap-shortcut"
        )
        let monitor = DictationModifierHotKeyMonitor.shared
        for _ in 0..<80 where !monitor.isMonitoring {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard monitor.isMonitoring else {
            logger.error(
                "result success=false runID=\(runID, privacy: .public) error=eventTapUnavailable"
            )
            return
        }

        let recoverySucceeded = monitor.recoverDisabledEventTapForTesting()

        let originalMode = monitor.activationMode
        let hold = await exerciseDictationEventTap(mode: .holdToTalk)
        let tap = await exerciseDictationEventTap(mode: .tapToTalk)
        monitor.cancelCurrentSession()
        GojoDictationService.shared.cancel()
        monitor.setActivationMode(originalMode)

        let success = recoverySucceeded
            && hold.started && hold.stopped
            && tap.started && tap.stopped
        let message = "result success=\(success)"
            + " runID=\(runID)"
            + " recoverySucceeded=\(recoverySucceeded)"
            + " holdStarted=\(hold.started)"
            + " holdStopped=\(hold.stopped)"
            + " holdStartMs=\(hold.startMilliseconds)"
            + " tapStarted=\(tap.started)"
            + " tapStopped=\(tap.stopped)"
            + " tapStartMs=\(tap.startMilliseconds)"
        logger.notice("\(message, privacy: .public)")
    }

    @MainActor
    private func exerciseDictationEventTap(
        mode: DictationActivationMode
    ) async -> (started: Bool, stopped: Bool, startMilliseconds: Int) {
        let monitor = DictationModifierHotKeyMonitor.shared
        monitor.cancelCurrentSession()
        GojoDictationService.shared.cancel()
        monitor.setActivationMode(mode)
        try? await Task.sleep(for: .milliseconds(150))

        let startTime = ProcessInfo.processInfo.systemUptime
        guard await postControlOptionChordDown() else {
            return (false, false, 0)
        }
        if mode == .tapToTalk {
            await postControlOptionChordUp()
        }

        var started = false
        for _ in 0..<120 {
            let state = GojoDictationService.shared.state
            if state == .listening {
                started = true
                break
            }
            if case .error = state {
                break
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        let startMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
        )

        if mode == .holdToTalk {
            await postControlOptionChordUp()
        } else if started {
            guard await postControlOptionChordDown() else {
                monitor.cancelCurrentSession()
                GojoDictationService.shared.cancel()
                return (started, false, startMilliseconds)
            }
            await postControlOptionChordUp()
        }

        var stopped = false
        if started {
            for _ in 0..<120 {
                let state = GojoDictationService.shared.state
                if state != .requestingPermission && state != .listening {
                    stopped = true
                    break
                }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }

        monitor.cancelCurrentSession()
        GojoDictationService.shared.cancel()
        try? await Task.sleep(for: .milliseconds(150))
        return (started, stopped, startMilliseconds)
    }

    @MainActor
    private func postControlOptionChordDown() async -> Bool {
        guard postModifierEvent(
            keyCode: 0x3B,
            keyDown: true,
            flags: [.maskControl]
        ) else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(12))
        return postModifierEvent(
            keyCode: 0x3A,
            keyDown: true,
            flags: [.maskControl, .maskAlternate]
        )
    }

    @MainActor
    private func focusDictationE2ETarget(_ expectedPID: pid_t?) async -> Bool {
        guard let expectedPID else { return true }
        guard let application = NSRunningApplication(processIdentifier: expectedPID),
              !application.isTerminated else {
            return false
        }

        application.activate(options: [.activateAllWindows])
        for _ in 0..<80 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    @MainActor
    private func stabilizeDictationE2ETargetFocus(
        _ expectedPID: pid_t?,
        attempts: Int
    ) async {
        guard let expectedPID,
              let application = NSRunningApplication(processIdentifier: expectedPID),
              !application.isTerminated else {
            return
        }

        for _ in 0..<attempts {
            application.activate(options: [.activateAllWindows])
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor
    private func postControlOptionChordUp() async {
        _ = postModifierEvent(
            keyCode: 0x3A,
            keyDown: false,
            flags: [.maskControl]
        )
        try? await Task.sleep(for: .milliseconds(12))
        _ = postModifierEvent(
            keyCode: 0x3B,
            keyDown: false,
            flags: []
        )
    }

    private func postModifierEvent(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: keyCode,
                  keyDown: keyDown
              ) else {
            return false
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        return true
    }

    @MainActor
    private func runDictationCaptureE2EProbe(expectedPID: pid_t?) async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "capture")
        let capture = await captureDictationE2ETarget(expectedPID: expectedPID)
        let success = (capture["success"] as? NSNumber)?.boolValue == true
        let capturedPID = (capture["pid"] as? NSNumber)?.int32Value
        let windowID = (capture["windowID"] as? NSNumber)?.uint32Value
        let displayID = (capture["displayID"] as? NSNumber)?.uint32Value
        let expectedMatch = expectedPID == nil || capturedPID == expectedPID
        let error = capture["error"] as? String ?? "none"
        logger.notice(
            "result success=\(success, privacy: .public) expectedMatch=\(expectedMatch, privacy: .public) pid=\(capturedPID ?? 0, privacy: .public) windowID=\(windowID ?? 0, privacy: .public) displayID=\(displayID ?? 0, privacy: .public) error=\(error, privacy: .public)"
        )
    }

    @MainActor
    private func runDictationInsertionE2EProbe(expectedPID: pid_t?) async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "insertion")
        let transcript = "Gojo local dictation end to end."
        let capture = await captureDictationE2ETarget(expectedPID: expectedPID)
        guard (capture["success"] as? NSNumber)?.boolValue == true,
              let token = capture["token"] as? String,
              expectedPID == nil
                || (capture["pid"] as? NSNumber)?.int32Value == expectedPID else {
            let error = capture["error"] as? String ?? "captureFailed"
            logger.error("result success=false stage=capture error=\(error, privacy: .public)")
            return
        }
        let insertion = await XPCHelperClient.shared.insertText(transcript, token: token)
        let success = (insertion["success"] as? NSNumber)?.boolValue == true
        let verified = (insertion["verified"] as? NSNumber)?.boolValue == true
        let method = insertion["method"] as? String ?? "none"
        let error = insertion["error"] as? String ?? "none"
        logger.notice(
            "result success=\(success, privacy: .public) verified=\(verified, privacy: .public) method=\(method, privacy: .public) error=\(error, privacy: .public)"
        )
    }

    @MainActor
    private func runDictationOpaquePasteE2EProbe(
        moveFocusAfterCapture: Bool,
        expectedPID: pid_t?
    ) async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "opaque-paste")
        let transcript = moveFocusAfterCapture
            ? "Gojo pasted at the active cursor."
            : "Gojo opaque paste reached the target."
        let scenario = moveFocusAfterCapture ? "focus-move" : "stable"
        let capture = await captureDictationE2ETarget(expectedPID: expectedPID)
        guard (capture["success"] as? NSNumber)?.boolValue == true,
              let token = capture["token"] as? String,
              expectedPID == nil
                || (capture["pid"] as? NSNumber)?.int32Value == expectedPID else {
            let error = capture["error"] as? String ?? "captureFailed"
            logger.error(
                "result success=false scenario=\(scenario, privacy: .public) stage=capture error=\(error, privacy: .public)"
            )
            return
        }

        if moveFocusAfterCapture {
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("rohoswagger.gojo.dictation-opaque-paste-fixture-focus-next"),
                object: nil,
                deliverImmediately: true
            )
            try? await Task.sleep(for: .milliseconds(180))
        }

        let insertion = await XPCHelperClient.shared.insertText(transcript, token: token)
        let success = (insertion["success"] as? NSNumber)?.boolValue == true
        let verified = (insertion["verified"] as? NSNumber)?.boolValue == true
        let method = insertion["method"] as? String ?? "none"
        let clipboardRestored = (insertion["clipboardRestored"] as? NSNumber)?.boolValue == true
        let error = insertion["error"] as? String ?? "none"
        logger.notice(
            "result success=\(success, privacy: .public) scenario=\(scenario, privacy: .public) method=\(method, privacy: .public) verified=\(verified, privacy: .public) clipboardRestored=\(clipboardRestored, privacy: .public) error=\(error, privacy: .public)"
        )
    }

    @MainActor
    private func runDictationUnicodeTypingE2EProbe(
        transcript: String?,
        expectedPID: pid_t?
    ) async {
        let logger = Logger(
            subsystem: "rohoswagger.gojo.dictation-e2e",
            category: "unicode-typing"
        )
        guard let transcript, !transcript.isEmpty else {
            logger.error("result success=false stage=input error=emptyText")
            return
        }
        let capture = await captureDictationE2ETarget(expectedPID: expectedPID)
        guard (capture["success"] as? NSNumber)?.boolValue == true,
              let token = capture["token"] as? String,
              expectedPID == nil
                || (capture["pid"] as? NSNumber)?.int32Value == expectedPID else {
            let error = capture["error"] as? String ?? "captureFailed"
            logger.error(
                "result success=false stage=capture error=\(error, privacy: .public)"
            )
            return
        }

        let insertion = await XPCHelperClient.shared.insertText(
            transcript,
            token: token
        )
        let success = (insertion["success"] as? NSNumber)?.boolValue == true
        let method = insertion["method"] as? String ?? "none"
        let partialInsertion =
            (insertion["partialInsertion"] as? NSNumber)?.boolValue == true
        let error = insertion["error"] as? String ?? "none"
        logger.notice(
            "result success=\(success, privacy: .public) method=\(method, privacy: .public) partialInsertion=\(partialInsertion, privacy: .public) error=\(error, privacy: .public)"
        )
    }

    @MainActor
    private func runDictationModelE2EProbe(expectedPID: pid_t?) async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "model")
        let reference = "Gojo local dictation should type this sentence into the focused text field."
        let capture = await captureDictationE2ETarget(expectedPID: expectedPID)
        guard (capture["success"] as? NSNumber)?.boolValue == true,
              let token = capture["token"] as? String,
              expectedPID == nil
                || (capture["pid"] as? NSNumber)?.int32Value == expectedPID else {
            let error = capture["error"] as? String ?? "captureFailed"
            logger.error("result success=false stage=capture error=\(error, privacy: .public)")
            return
        }

        do {
            let audio = try await synthesizeDictationFixture(reference)
            let clock = ContinuousClock()
            let started = clock.now
            let rawTranscript = try await GojoDictationService.shared.transcribeE2E(audio)
            let elapsed = started.duration(to: clock.now)
            let transcript = DictationTranscriptPolicy.normalize(rawTranscript)
            let referenceMatch = matchesSyntheticReference(transcript, reference: reference)
            let insertion = await XPCHelperClient.shared.insertText(transcript, token: token)
            let success = (insertion["success"] as? NSNumber)?.boolValue == true
            let verified = (insertion["verified"] as? NSNumber)?.boolValue == true
            let method = insertion["method"] as? String ?? "none"
            logger.notice(
                "result success=\(success, privacy: .public) verified=\(verified, privacy: .public) referenceMatch=\(referenceMatch, privacy: .public) method=\(method, privacy: .public) elapsed=\(String(describing: elapsed), privacy: .public)"
            )
        } catch {
            logger.error("result success=false stage=model error=\(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func captureDictationE2ETarget(expectedPID: pid_t?) async -> NSDictionary {
        var capture = await XPCHelperClient.shared.captureFocusedTextTarget(
            promptIfNeeded: false
        )
        if let expectedPID {
            for _ in 0..<30 where (capture["pid"] as? NSNumber)?.int32Value != expectedPID {
                try? await Task.sleep(for: .milliseconds(20))
                capture = await XPCHelperClient.shared.captureFocusedTextTarget(
                    promptIfNeeded: false
                )
            }
        }
        return capture
    }

    @MainActor
    private func runDictationInferenceE2EProbe() async {
        let logger = Logger(subsystem: "rohoswagger.gojo.dictation-e2e", category: "inference")
        let reference = "Gojo local dictation should type this sentence into the focused text field."
        let selectedModel = GojoDictationService.shared.selectedModel.rawValue

        do {
            let audio = try await synthesizeDictationFixture(reference)
            let clock = ContinuousClock()
            let started = clock.now
            let rawTranscript = try await GojoDictationService.shared.transcribeE2E(audio)
            let elapsed = started.duration(to: clock.now)
            let transcript = DictationTranscriptPolicy.normalize(rawTranscript)
            let referenceMatch = matchesSyntheticReference(transcript, reference: reference)
            logger.notice(
                "result success=true referenceMatch=\(referenceMatch, privacy: .public) model=\(selectedModel, privacy: .public) elapsed=\(String(describing: elapsed), privacy: .public)"
            )
        } catch {
            logger.error(
                "result success=false model=\(selectedModel, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func synthesizeDictationFixture(_ text: String) async throws -> DictationAudio {
        let accumulator = DictationE2ESpeechAccumulator()
        return try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.write(utterance) { buffer in
                _ = synthesizer
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    continuation.resume(throwing: DictationE2EProbeError.invalidSpeechBuffer)
                    return
                }
                if pcm.frameLength == 0 {
                    guard let snapshot = accumulator.finish() else { return }
                    do {
                        let audio = try AVAudioEngineCaptureService.normalize(
                            samples: snapshot.samples,
                            from: snapshot.sampleRate
                        )
                        continuation.resume(returning: audio)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                accumulator.append(pcm)
            }
        }
    }

    private func matchesSyntheticReference(_ transcript: String, reference: String) -> Bool {
        func words(in text: String) -> [Substring] {
            text.lowercased().split { character in
                !character.isLetter && !character.isNumber
            }
        }
        return words(in: transcript) == words(in: reference)
    }
#endif

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "seeall", fileExtension: "m4a")
    }

    @MainActor
    func viewModelForCurrentMouseLocation() -> GojoViewModel {
        let mouseLocation = NSEvent.mouseLocation
        var selectedViewModel = vm

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                if let uuid = screen.displayUUID, let screenViewModel = viewModels[uuid] {
                    selectedViewModel = screenViewModel
                    break
                }
            }
        }

        return selectedViewModel
    }

    @MainActor
    private func windowFor(viewModel: GojoViewModel) -> NSWindow? {
        if viewModel === vm {
            return window
        }

        return viewModels.first(where: { $0.value === viewModel }).flatMap { windows[$0.key] }
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = GojoViewModel(screenUUID: uuid)
                    let window = createGojoWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)

            if window == nil {
                window = createGojoWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 540),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                        // Final onboarding beat: play the hello animation in the
                        // notch itself, now that the onboarding window is gone.
                        DispatchQueue.main.async {
                            withAnimation(.spring(.bouncy(duration: 0.4))) {
                                self.vm.open()
                                self.coordinator.helloAnimationRunning = true
                            }
                        }
                    },
                    onOpenSettings: {
                        window.close()
                        SettingsWindowController.shared.showWindow()
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")
            // Keep onboarding visible above other apps for the whole flow — as
            // an accessory app its window would otherwise slip behind and get
            // lost. (The accessibility step fades this out on its own while the
            // drag companion is up, then refocuses it once access is granted.)
            window.level = .floating
            window.collectionBehavior.insert(.canJoinAllSpaces)
            // Onboarding is designed dark end-to-end; pin the window appearance
            // so materials (badges, glass buttons) don't render pale in light mode.
            window.appearance = NSAppearance(named: .darkAqua)

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

#if DEBUG
private enum DictationE2EProbeError: Error {
    case invalidSpeechBuffer
}

private final class DictationE2ESpeechAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate = 0.0
    private var finished = false

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }
        var mono = [Float](repeating: 0, count: frameCount)
        for channelIndex in 0..<channelCount {
            for frameIndex in 0..<frameCount {
                mono[frameIndex] += channels[channelIndex][frameIndex] / Float(channelCount)
            }
        }
        lock.withLock {
            if sampleRate == 0 { sampleRate = buffer.format.sampleRate }
            samples.append(contentsOf: mono)
        }
    }

    func finish() -> (samples: [Float], sampleRate: Double)? {
        lock.withLock {
            guard !finished else { return nil }
            finished = true
            return (samples, sampleRate)
        }
    }
}
#endif

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
