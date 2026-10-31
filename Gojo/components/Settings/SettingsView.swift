//
//  SettingsView.swift
//  Gojo
//
//  Created by Richard Kunkli on 07/08/2024.
//

import AVFoundation
import Defaults
import EventKit
import KeyboardShortcuts
import LaunchAtLogin
import Sparkle
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var selectedTab: String
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?
    private weak var settingsWindow: NSWindow?

    init(
        updaterController: SPUStandardUpdaterController? = nil,
        initialTab: String = "General",
        settingsWindow: NSWindow? = nil
    ) {
        self.updaterController = updaterController
        self.settingsWindow = settingsWindow
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: "General") {
                    Label("General", systemImage: "gear")
                }
                NavigationLink(value: "Appearance") {
                    Label("Appearance", systemImage: "eye")
                }
                NavigationLink(value: "Media") {
                    Label("Media", systemImage: "play.laptopcomputer")
                }
                NavigationLink(value: "Calendar") {
                    Label("Calendar", systemImage: "calendar")
                }
                NavigationLink(value: "HUD") {
                    HStack {
                        Label("HUDs", systemImage: "dial.medium.fill")
                        Spacer()
                        comingSoonTag()
                    }
                }
                NavigationLink(value: "Battery") {
                    Label("Battery", systemImage: "battery.100.bolt")
                }
                NavigationLink(value: "Flux") {
                    Label("Night Shift", systemImage: "moon.stars")
                }
                NavigationLink(value: "Shelf") {
                    Label("Shelf", systemImage: "books.vertical")
                }
                NavigationLink(value: "Clipboard") {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                NavigationLink(value: "Search") {
                    Label("Search", systemImage: "magnifyingglass")
                }
                NavigationLink(value: "Dictation") {
                    Label("Dictation", systemImage: "waveform.and.mic")
                }
                NavigationLink(value: "Window Switcher") {
                    Label("Window Switcher", systemImage: "macwindow.on.rectangle")
                }
                NavigationLink(value: "Shortcuts") {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                NavigationLink(value: "License") {
                    Label("License", systemImage: "key.fill")
                }
                NavigationLink(value: "Advanced") {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                NavigationLink(value: "About") {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            Group {
                switch selectedTab {
                case "General":
                    GeneralSettings()
                case "Appearance":
                    Appearance()
                case "Media":
                    Media()
                case "Calendar":
                    CalendarSettings()
                case "HUD":
                    HUD()
                case "Battery":
                    Charge()
                case "Flux":
                    FluxSettings()
                case "Shelf":
                    Shelf()
                case "Clipboard":
                    ClipboardSettingsScreen()
                case "Search":
                    SearchSettings()
                case "Dictation":
                    DictationSettings(settingsWindow: settingsWindow)
                case "Window Switcher":
                    AltTabSettings()
                case "Shortcuts":
                    Shortcuts()
                case "License":
                    LicenseSettings()
                case "Extensions":
                    GeneralSettings()
                case "Advanced":
                    Advanced()
                case "About":
                    if let controller = updaterController {
                        About(updaterController: controller)
                    } else {
                        // Fallback with a default controller
                        About(
                            updaterController: SPUStandardUpdaterController(
                                startingUpdater: false, updaterDelegate: nil,
                                userDriverDelegate: nil))
                    }
                default:
                    GeneralSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @EnvironmentObject var vm: GojoViewModel
    @ObservedObject var coordinator = GojoViewCoordinator.shared

    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.menubarIcon] },
                    set: { Defaults[.menubarIcon] = $0 }
                )) {
                    Text("Show menu bar icon")
                }
                .tint(.effectiveAccent)
                LaunchAtLogin.Toggle("Launch at login")
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(
                        name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                    ForEach(screens, id: \.uuid) { screen in
                        Text(screen.name).tag(screen.uuid as String?)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens = NSScreen.screens.compactMap { screen in
                        guard let uuid = screen.displayUUID else { return nil }
                        return (uuid, screen.localizedName)
                    }
                }
                .disabled(showOnAllDisplays)
                
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                    .onChange(of: automaticallySwitchDisplay) {
                        NotificationCenter.default.post(
                            name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                    }
                    .disabled(showOnAllDisplays)
            } header: {
                Text("System features")
            }

            Section {
                Picker(
                    selection: $notchHeightMode,
                    label:
                        Text("Notch height on notch displays")
                ) {
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: notchHeightMode) {
                    switch notchHeightMode {
                    case .matchRealNotchSize:
                        notchHeight = 38
                    case .matchMenuBar:
                        notchHeight = 44
                    case .custom:
                        notchHeight = 38
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Notch height on non-notch displays", selection: $nonNotchHeightMode) {
                    Text("Match menu bar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch height")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(
                            name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch sizing")
            }

            NotchBehaviour()

            gestureControls()
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("General")
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
                .disabled(!openNotchOnHover)
            if enableGestures {
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(
                            Defaults[.gestureSensitivity] == 100
                                ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text(
                "Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled"
            )
            .multilineTextAlignment(.trailing)
            .foregroundStyle(.secondary)
            .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                    Text("Enable haptic feedback")
            }
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBatteryIndicator) {
                    Text("Show battery indicator")
                }
                Defaults.Toggle(key: .showPowerStatusNotifications) {
                    Text("Show power status notifications")
                }
            } header: {
                Text("General")
            }
            Section {
                Defaults.Toggle(key: .showBatteryPercentage) {
                    Text("Show battery percentage")
                }
                Defaults.Toggle(key: .showPowerStatusIcons) {
                    Text("Show power status icons")
                }
            } header: {
                Text("Battery Information")
            }
        }
        .onAppear {
            Task { @MainActor in
                _ = try? await XPCHelperClient.shared.helperPermissionStatus()
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Battery")
    }
}

struct HUD: View {
    @EnvironmentObject var vm: GojoViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    @ObservedObject private var shortcutMonitor = DictationModifierHotKeyMonitor.shared

    private var accessibilityAuthorized: Bool {
        guard case .available = shortcutMonitor.helperState else { return false }
        return shortcutMonitor.accessibilityState == .trusted
    }

    
    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system HUD")
                            .font(.headline)
                        Text("Replaces the standard macOS volume, display brightness, and keyboard brightness HUDs with a custom design.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .hudReplacement)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .disabled(!accessibilityAuthorized)
                }
                
                if case .unavailable = shortcutMonitor.helperState {
                    Text("Gojo could not connect to its background helper. Retry the connection before changing Accessibility access.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry connection") {
                        Task { await shortcutMonitor.start() }
                    }
                } else if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                Task { await shortcutMonitor.start(promptIfNeeded: true) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.top, 6)
                }
            }
            
            Section {
                Picker("Option key behaviour", selection: $optionKeyAction) {
                    ForEach(OptionKeyAction.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                
                Picker("Progress bar style", selection: $enableGradient) {
                    Text("Hierarchical")
                        .tag(false)
                    Text("Gradient")
                        .tag(true)
                }
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Tint progress bar with accent color")
                }
            } header: {
                Text("General")
            }
            .disabled(!hudReplacement)
            
            Section {
                Defaults.Toggle(key: .showOpenNotchHUD) {
                    Text("Show HUD in open notch")
                }
                Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                    Text("Show percentage")
                }
                .disabled(!Defaults[.showOpenNotchHUD])
            } header: {
                HStack {
                    Text("Open Notch")
                    customBadge(text: "Beta")
                }
            }
            .disabled(!hudReplacement)
            
            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.enableGradient] = false
                        }
                    }
                }
                
                Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                    Text("Show percentage")
                }
            } header: {
                Text("Closed Notch")
            }
            .disabled(!Defaults[.hudReplacement])
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("HUDs")
        .task {
            await shortcutMonitor.refreshReadiness()
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles

    @Default(.enableLyrics) var enableLyrics

    var body: some View {
        Form {
            Section {
                Picker("Music Source", selection: $mediaController) {
                    ForEach(availableMediaControllers) { controller in
                        Text(controller.rawValue).tag(controller)
                    }
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music currently depends on the Pear Desktop companion app:")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link(
                            "Open download page",
                            destination: URL(string: "https://github.com/pear-devs/pear-desktop")!
                        )
                        .font(.caption)
                        .foregroundColor(.blue)  // Ensures it's visibly a link
                    }
                } else {
                    Text(
                        "'Now Playing' was the only option on previous versions and works with all media apps."
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            
            Section {
                Toggle(
                    "Show music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
                Picker("Sneak Peek Style", selection: $sneakPeekStyles) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Media playback live activity")
            }
            
            Section {
                MusicSlotConfigurationView()
                Defaults.Toggle(key: .enableLyrics) {
                    HStack {
                        Text("Show lyrics below artist name")
                        customBadge(text: "Beta")
                    }
                }
            } header: {
                Text("Media controls")
            }  footer: {
                Text("Customize which controls appear in the music player. Volume expands when active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Media")
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct CalendarSettings: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent

    var body: some View {
        Form {
            Defaults.Toggle(key: .showCalendar) {
                Text("Show calendar")
            }
            Defaults.Toggle(key: .hideCompletedReminders) {
                Text("Hide completed reminders")
            }
            Defaults.Toggle(key: .hideAllDayEvents) {
                Text("Hide all-day events")
            }
            Defaults.Toggle(key: .autoScrollToNextEvent) {
                Text("Auto-scroll to next event")
            }
            Defaults.Toggle(key: .showFullEventTitles) {
                Text("Always show full event titles")
            }
            Section(header: Text("Calendars")) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text("Calendar access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Calendar Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
            Section(header: Text("Reminders")) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text("Reminder access is denied. Please enable it in System Settings.")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Open Reminder Settings") {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .accentColor(lighterColor(from: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Calendar")
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0,0,0,0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    let nr = lighten(r)
    let ng = lighten(g)
    let nb = lighten(b)

    return Color(red: Double(nr), green: Double(ng), blue: Double(nb), opacity: Double(a))
}

struct About: View {
    @State private var showBuildNumber: Bool = false
    let updaterController: SPUStandardUpdaterController
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack {
            Form {
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        if showBuildNumber {
                            Text("(\(Bundle.main.buildVersionNumber ?? ""))")
                                .foregroundStyle(.secondary)
                        }
                        Text(Bundle.main.releaseVersionNumber ?? "unkown")
                            .foregroundStyle(.secondary)
                    }
                    .onTapGesture {
                        withAnimation {
                            showBuildNumber.toggle()
                        }
                    }
                } header: {
                    Text("Version info")
                }

                Section {
                    HStack(alignment: .top) {
                        Text("License")
                        Spacer()
                        Text("GPLv3")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Open source")
                }

                UpdaterSettingsView(updater: updaterController.updater)
            }
            VStack(spacing: 0) {
                Divider()
                Text("Made with 🫶🏻 by rohoswagger")
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                    .padding(.bottom, 7)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .toolbar {
            //            Button("Welcome window") {
            //                openWindow(id: "onboarding")
            //            }
            //            .controlSize(.extraLarge)
            CheckForUpdatesView(updater: updaterController.updater)
        }
        .navigationTitle("About")
    }
}

struct SearchSettings: View {
    @Default(.searchEnabled) private var searchEnabled
    @Default(.searchOverrideCommandSpace) private var searchOverrideCommandSpace
    @State private var hotkeyActive = true

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .searchEnabled) {
                    Text("Enable search")
                }
            } header: {
                Text("General")
            } footer: {
                Text("Opens a floating search panel, centered on screen, independent of the notch.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.searchOverrideCommandSpace] },
                    set: {
                        Defaults[.searchOverrideCommandSpace] = $0
                        if $0 {
                            Task {
                                await SearchHotkeyInterceptor.shared.start(promptIfNeeded: true)
                                await refreshHotkeyActive()
                            }
                        }
                    }
                )) {
                    Text("Replace Spotlight (⌘Space)")
                }
                Text("Opens Gojo search when you press ⌘ Space, instead of Spotlight. Requires Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if searchOverrideCommandSpace && !hotkeyActive {
                    Label("Accessibility access is required for ⌘Space to open search.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                KeyboardShortcuts.Recorder("Additional shortcut:", name: .toggleSearchPanel)
            } header: {
                Text("Shortcuts")
            }
            .disabled(!searchEnabled)
        }
        .navigationTitle("Search")
        .task {
            await refreshHotkeyActive()
        }
    }

    @MainActor
    private func refreshHotkeyActive() async {
        hotkeyActive = SearchHotkeyInterceptor.shared.isActive
    }
}

struct Shelf: View {
    
    @Default(.shelfTapToOpen) var shelfTapToOpen: Bool
    @Default(.quickShareProvider) var quickShareProvider
    @Default(.expandedDragDetection) var expandedDragDetection: Bool
    @StateObject private var quickShareService = QuickShareService.shared

    private var selectedProvider: QuickShareProvider? {
        quickShareService.availableProviders.first(where: { $0.id == quickShareProvider })
    }
    
    init() {
        Task { await QuickShareService.shared.discoverAvailableProviders() }
    }
    
    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .shelfEnabled) {
                    Text("Enable shelf")
                }
                Defaults.Toggle(key: .openShelfByDefault) {
                    Text("Open shelf by default if items are present")
                }
                Defaults.Toggle(key: .expandedDragDetection) {
                    Text("Expanded drag detection area")
                }
                .onChange(of: expandedDragDetection) {
                    NotificationCenter.default.post(
                        name: Notification.Name.expandedDragDetectionChanged,
                        object: nil
                    )
                }
                Defaults.Toggle(key: .copyOnDrag) {
                    Text("Copy items on drag")
                }
                Defaults.Toggle(key: .autoRemoveShelfItems) {
                    Text("Remove from shelf after dragging")
                }

            } header: {
                HStack {
                    Text("General")
                }
            }
            
            Section {
                Picker("Quick Share Service", selection: $quickShareProvider) {
                    ForEach(quickShareService.availableProviders, id: \.id) { provider in
                        HStack {
                            Group {
                                if let imgData = provider.imageData, let nsImg = NSImage(data: imgData) {
                                    Image(nsImage: nsImg)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            .frame(width: 16, height: 16)
                            .foregroundColor(.accentColor)
                            Text(provider.id)
                        }
                        .tag(provider.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedProvider = selectedProvider {
                    HStack {
                        Group {
                            if let imgData = selectedProvider.imageData, let nsImg = NSImage(data: imgData) {
                                Image(nsImage: nsImg)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        .frame(width: 16, height: 16)
                        .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Currently selected: \(selectedProvider.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Files dropped on the shelf will be shared via this service")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Providers are always enabled; user can pick default service above.
                
            } header: {
                HStack {
                    Text("Quick Share")
                }
            } footer: {
                Text("Choose which service to use when sharing files from the shelf. Click the shelf button to select files, or drag files onto it to share immediately.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shelf")
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Show settings icon in notch")
                }

            } header: {
                Text("General")
            }

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Colored spectrogram")
                }
                Defaults
                    .Toggle("Player tinting", key: .playerColorTinting)
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.rawValue)
                    }
                }
            } header: {
                Text("Media")
            }

            Section {
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    comingSoonTag()
                }
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable camera mirror")
                }
                    .disabled(!checkVideoInput())
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Show cool face animation while inactive")
                }
            } header: {
                HStack {
                    Text("Additional features")
                }
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Appearance")
    }

    func checkVideoInput() -> Bool {
        if AVCaptureDevice.default(for: .video) != nil {
            return true
        }

        return false
    }
}

struct Advanced: View {
    @Default(.useCustomAccentColor) var useCustomAccentColor
    @Default(.customAccentColorData) var customAccentColorData
    @Default(.extendHoverArea) var extendHoverArea
    @Default(.showOnLockScreen) var showOnLockScreen
    @Default(.hideFromScreenRecording) var hideFromScreenRecording
    
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor? = nil

    // macOS accent colors
    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"
        
        var id: String { self.rawValue }
        
        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    // Toggle between system and custom
                    Picker("Accent color", selection: $useCustomAccentColor) {
                        Text("System").tag(false)
                        Text("Custom").tag(true)
                    }
                    .pickerStyle(.segmented)
                    
                    if !useCustomAccentColor {
                        // System accent info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                AccentCircleButton(
                                    isSelected: true,
                                    color: .accentColor,
                                    isSystemDefault: true
                                ) {}
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Using System Accent")
                                        .font(.body)
                                    Text("Your macOS system accent color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    } else {
                        // Custom color options
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color Presets")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 12) {
                                ForEach(PresetAccentColor.allCases) { preset in
                                    AccentCircleButton(
                                        isSelected: selectedPresetColor == preset,
                                        color: preset.color,
                                        isMulticolor: false
                                    ) {
                                        selectedPresetColor = preset
                                        customAccentColor = preset.color
                                        saveCustomColor(preset.color)
                                        forceUiUpdate()
                                    }
                                }
                                Spacer()
                            }
                            
                            Divider()
                                .padding(.vertical, 4)
                            
                            // Custom color picker
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Pick a Color")
                                        .font(.body)
                                    Text("Choose any color")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                ColorPicker(selection: Binding(
                                    get: { customAccentColor },
                                    set: { newColor in
                                        customAccentColor = newColor
                                        selectedPresetColor = nil
                                        saveCustomColor(newColor)
                                        forceUiUpdate()
                                    }
                                ), supportsOpacity: false) {
                                    ZStack {
                                        Circle()
                                            .fill(customAccentColor)
                                            .frame(width: 32, height: 32)
                                        
                                        if selectedPresetColor == nil {
                                            Circle()
                                                .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                                .frame(width: 32, height: 32)
                                        }
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Accent color")
            } footer: {
                Text("Choose between your system accent color or customize it with your own selection.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .onAppear {
                initializeAccentColorState()
            }
            
            Section {
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
            } header: {
                Text("Window Appearance")
            }
            
            Section {
                Defaults.Toggle(key: .extendHoverArea) {
                    Text("Extend hover area")
                }
                Defaults.Toggle(key: .hideTitleBar) {
                    Text("Hide title bar")
                }
                Defaults.Toggle(key: .showOnLockScreen) {
                    Text("Show notch on lock screen")
                }
                Defaults.Toggle(key: .hideFromScreenRecording) {
                    Text("Hide from screen recording")
                }
            } header: {
                Text("Window Behavior")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Advanced")
        .onAppear {
            loadCustomColor()
        }
    }
    
    private func forceUiUpdate() {
        // Force refresh the UI
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }
    
    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
            forceUiUpdate()
        }
    }
    
    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)
            
            // Check if loaded color matches a preset
            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }
    
    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)
        
        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
    
    private func initializeAccentColorState() {
        if !useCustomAccentColor {
            selectedPresetColor = nil // Multicolor is selected when useCustomAccentColor is false
        } else {
            loadCustomColor()
        }
    }
}

// MARK: - Accent Circle Button Component
struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Color circle
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                // Subtle border
                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                // Apple-style highlight ring around the middle when selected
                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS system accent color" : "")
    }
}

struct Shortcuts: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Clipboard:", name: .clipboardHistoryPanel)
            } header: {
                Text("Clipboard")
            } footer: {
                Text("Open Gojo directly into the Clipboard tab and focus search.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                LabeledContent("Push to talk:", value: "⌃⌥")
                LabeledContent("Lock / finish voice mode:", value: "⌃⌥ then Space")
            } header: {
                Text("Dictation")
            } footer: {
                Text("Hold Control and Option to talk; release to insert. While holding both keys, press Space to keep listening after release. Repeat Control–Option, then Space to finish.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
            } header: {
                Text("Media")
            } footer: {
                Text(
                    "Sneak Peek shows the media title and artist under the notch for a few seconds."
                )
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
            }
            Section {
                KeyboardShortcuts.Recorder("Left Half:", name: .windowLeftHalf)
                KeyboardShortcuts.Recorder("Right Half:", name: .windowRightHalf)
                KeyboardShortcuts.Recorder("Top Half:", name: .windowTopHalf)
                KeyboardShortcuts.Recorder("Bottom Half:", name: .windowBottomHalf)
                KeyboardShortcuts.Recorder("Maximize / Restore:", name: .windowMaximize)
                KeyboardShortcuts.Recorder("Zoom (Default Size):", name: .windowZoom)
            } header: {
                Text("Windows")
            } footer: {
                Text("Move the focused app window without opening Gojo. Maximize stores the previous frame, then pressing it again restores.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Shortcuts")
    }


}

struct DictationSettings: View {
    private weak var settingsWindow: NSWindow?
    @ObservedObject private var dictation = GojoDictationService.shared
    @AppStorage(DictationPauseDuration.defaultsKey)
    private var dictationPauseDurationRawValue = DictationPauseDuration.natural.rawValue
    @ObservedObject private var microphonePermission = DictationMicrophonePermission.shared
    @ObservedObject private var shortcutMonitor = DictationModifierHotKeyMonitor.shared
    @State private var modelToRemove: DictationModelID?
    @State private var openRouterAPIKeyDraft = ""
    @State private var isReplacingOpenRouterKey = false
    @State private var showS1MiniRemovalConfirmation = false
    @State private var vocabularySpokenDraft = ""
    @State private var vocabularyReplacementDraft = ""
    @State private var editingVocabularyID: UUID?
    @State private var vocabularyError: String?
    @State private var vocabularyImportPresentation: VocabularyImportPresentation?
    @State private var vocabularyImportOperation: VocabularyImportOperation?
    @State private var vocabularyImportFeedback: VocabularyImportFeedback?
    @State private var vocabularyImportLifetime: UUID?
    @State private var practiceFieldID = UUID()

    init(settingsWindow: NSWindow? = nil) {
        self.settingsWindow = settingsWindow
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Push to talk", value: "Hold ⌃⌥")
                LabeledContent("Lock microphone", value: "⌃⌥ then Space")
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Release Control–Option to insert text. Press Space while holding both keys to keep listening. Repeat the shortcut to finish; Escape cancels.")
            }

            permissionSection

            practiceSection

            Section {
                Picker("Insert after a pause", selection: $dictationPauseDurationRawValue) {
                    ForEach(DictationPauseDuration.allCases) { duration in
                        Text(duration.title).tag(duration.rawValue)
                    }
                }
                .disabled(!dictation.canChangeModel)

                LabeledContent("Floating controls") {
                    Button("Show controls") {
                        DictationPanelController.shared.show()
                    }
                }
                LabeledContent("Window position") {
                    Button("Reset") {
                        DictationPanelController.shared.resetPosition()
                    }
                }
                LabeledContent("Status") {
                    if showsModelPreparation {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Preparing model…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(DictationSettingsStatus.title(for: dictation.state))
                    }
                }
                if let detail = dictation.stateDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Voice mode")
            } footer: {
                Text("Text goes into the focused field between phrases. Drag the floating controls to move them; their position is saved for each display.")
            }

            inputSection

            Section {
                Picker("Provider", selection: dictationProviderBinding) {
                    ForEach(DictationProvider.allCases) { provider in
                        Text(provider.label).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!dictation.canChangeModel)

                if dictation.selectedProvider == .openRouter {
                    if dictation.hasOpenRouterAPIKey, !isReplacingOpenRouterKey {
                        LabeledContent("API key") {
                            HStack(spacing: 12) {
                                Text(dictation.openRouterAPIKeyHint ?? "Saved")
                                    .font(.body.monospaced())
                                    .foregroundStyle(.secondary)
                                    .privacySensitive()
                                    .accessibilityLabel("API key saved")
                                Button("Replace…") {
                                    isReplacingOpenRouterKey = true
                                }
                                Button("Remove", role: .destructive) {
                                    dictation.removeOpenRouterAPIKey()
                                    openRouterAPIKeyDraft = ""
                                }
                                .accessibilityHint("Removes the saved OpenRouter API key from your macOS Keychain.")
                            }
                        }
                    } else {
                        LabeledContent("API key") {
                            HStack(spacing: 8) {
                                SecureField("API key", text: $openRouterAPIKeyDraft, prompt: Text("sk-or-…"))
                                    .labelsHidden()
                                    .textContentType(.password)
                                    .privacySensitive()
                                    .onSubmit(saveOpenRouterAPIKey)
                                    .frame(minWidth: 180)
                                    .accessibilityLabel("OpenRouter API key")
                                    .accessibilityHint("Stored securely in your macOS Keychain.")

                                Button("Save") {
                                    saveOpenRouterAPIKey()
                                }
                                .disabled(openRouterAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                if isReplacingOpenRouterKey {
                                    Button("Cancel") {
                                        openRouterAPIKeyDraft = ""
                                        isReplacingOpenRouterKey = false
                                    }
                                }
                            }
                        }
                    }

                    LabeledContent("Speech model") {
                        HStack(spacing: 8) {
                            if dictation.availableOpenRouterModels.isEmpty {
                                if dictation.isRefreshingOpenRouterModels {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Loading models…")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Button("Load Models") {
                                        dictation.refreshOpenRouterModels()
                                    }
                                    .disabled(!dictation.canChangeModel)
                                }
                            } else {
                                Picker("Speech model", selection: openRouterModelBinding) {
                                    ForEach(dictation.availableOpenRouterModels) { model in
                                        Text(model.displayName).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .disabled(!dictation.canChangeModel)
                                .accessibilityLabel("Speech model")
                                .accessibilityHint("Only OpenRouter models that support speech transcription are shown.")

                                Button {
                                    dictation.refreshOpenRouterModels()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(!dictation.canChangeModel)
                                .help("Refresh the model list from OpenRouter")
                                .accessibilityLabel("Refresh OpenRouter speech models")
                            }
                        }
                    }

                    if let error = dictation.openRouterModelError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text(transcriptionPrivacyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if dictation.selectedProvider == .local {
                Section {
                    ForEach(DictationModelDescriptor.all) { model in
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .fontWeight(.medium)
                                Text("\(model.engineLabel) · \(model.downloadSizeLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(model.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let download = dictation.modelDownload, download.model == model.id {
                                    modelDownloadProgress(download, modelName: model.displayName)
                                }
                                if let error = dictation.modelErrors[model.id] {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 8) {
                                Button {
                                    if dictation.isModelInstalled(model.id) {
                                        dictation.selectModel(model.id)
                                    } else {
                                        dictation.downloadModel(model.id)
                                    }
                                } label: {
                                    Text(modelButtonTitle(for: model.id))
                                        .foregroundStyle(modelButtonDisabled(for: model.id) ? Color.secondary : Color.primary)
                                }
                                .disabled(modelButtonDisabled(for: model.id))
                                if dictation.isModelInstalled(model.id) {
                                    Button(role: .destructive) {
                                        modelToRemove = model.id
                                    } label: {
                                        Text(dictation.removingModel == model.id ? "Removing…" : "Remove")
                                            .foregroundStyle(!dictation.canChangeModel ? Color.secondary : Color.primary)
                                    }
                                    .disabled(!dictation.canChangeModel)
                                }
                            }
                            .controlSize(.small)
                            .tint(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Speech models")
                } footer: {
                    Text("Download one or more models, then choose which one Gojo should use. Dictation stays on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            experienceSection

            Section {
                Toggle("AI polish (optional, English)", isOn: cleanupEnabledBinding)
                    .disabled(
                        !dictation.s1MiniInstalled || dictation.s1MiniOperation != nil
                    )
                    .accessibilityHint(
                        dictation.s1MiniOperation == .removing
                            ? "Cleanup is unavailable while S1-mini is being removed."
                            : dictation.s1MiniInstalled
                            ? "Uses S1-mini locally to clean dictated text."
                            : "Download S1-mini to enable local transcript cleanup."
                    )

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(S1MiniModel.displayName)
                            .fontWeight(.medium)
                        Spacer()
                        Text(S1MiniModel.downloadSizeLabel)
                            .foregroundStyle(.secondary)
                    }

                    Text("Optional cleanup for English transcripts. Leave AI polish off to use the speech model’s output directly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let error = dictation.s1MiniError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    HStack {
                        if dictation.s1MiniInstalled {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button(
                                dictation.s1MiniOperation == .removing ? "Removing…" : "Remove",
                                role: .destructive
                            ) {
                                showS1MiniRemovalConfirmation = true
                            }
                            .disabled(!dictation.canChangeCleanupModel)
                            .accessibilityHint("Removes the local cleanup model and frees 462 MiB.")
                        } else {
                            if dictation.s1MiniOperation == .installing {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Downloading S1-mini by Superwhisper")
                                Button("Cancel download") {
                                    dictation.cancelS1MiniDownload()
                                }
                            } else {
                                Button("Download") {
                                    dictation.downloadS1Mini()
                                }
                                .disabled(!dictation.canChangeCleanupModel)
                                .accessibilityLabel("Download S1-mini by Superwhisper")
                                .accessibilityHint("Downloads a 462 MiB English cleanup model from Hugging Face.")
                            }
                        }
                    }
                }
                .padding(.vertical, 3)

                if dictation.cleanupEnabled {
                    Picker("Style", selection: writingStyleBinding) {
                        ForEach(DictationWritingStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)

                }
            } header: {
                Text("Transcript cleanup")
            } footer: {
                Text(writingStylePrivacyDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use personal vocabulary", isOn: Binding(
                    get: { dictation.usesVocabulary }, set: { dictation.setUsesVocabulary($0) }
                ))
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Learn from my corrections", isOn: learnsCorrectionsBinding)
                    Text("On by default. Gojo watches edits in the same text field for up to 30 seconds after dictation and learns a correction after you make it twice. This stays on this Mac. Learned entries appear below, where you can edit or delete them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)

                TextField("Word or phrase", text: $vocabularyReplacementDraft)
                    .accessibilityLabel("Word or phrase")
                    .accessibilityHint("The spelling Gojo should use, for example gpt-5.6-sol.")
                    .onSubmit(saveVocabularyDraft)

                HStack {
                    Button(editingVocabularyID == nil ? "Add term" : "Save changes") {
                        saveVocabularyDraft()
                    }
                    .disabled(
                        vocabularyReplacementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if editingVocabularyID != nil {
                        Button("Cancel") {
                            clearVocabularyDraft()
                        }
                    }

                    Spacer()

                    Button("Import file…") {
                        vocabularyImportPresentation = .file
                    }
                    .disabled(vocabularyImportOperation != nil || vocabularyImportPresentation != nil)

                    Button("Paste list…") {
                        vocabularyImportFeedback = nil
                        vocabularyImportPresentation = .paste
                    }
                    .disabled(vocabularyImportOperation != nil || vocabularyImportPresentation != nil)
                }

                Text("Import UTF-8 JSON, CSV, or text files up to 1 MiB. CSV treats a first-row word, words, or term column as a header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let vocabularyError {
                    Label(vocabularyError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let vocabularyImportFeedback {
                    Text(vocabularyImportFeedback.message)
                        .font(.caption)
                        .foregroundStyle(vocabularyImportFeedback.errorMessage == nil ? Color.secondary : Color.orange)
                        .textSelection(.enabled)
                }

                if vocabularyImportOperation != nil, vocabularyImportPresentation != .paste {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Importing words…").font(.caption)
                        Button("Cancel import") { cancelVocabularyImport() }
                    }
                }

                if dictation.vocabulary.isEmpty {
                    Text("No words yet. Add names, code symbols, or technical jargon Gojo should spell exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dictation.vocabulary) { entry in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.replacement)
                                    .textSelection(.enabled)
                                if entry.spoken != entry.replacement {
                                    Text("Also corrects: \(entry.spoken)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Edit") {
                                editingVocabularyID = entry.id
                                vocabularySpokenDraft = entry.spoken == entry.replacement ? "" : entry.spoken
                                vocabularyReplacementDraft = entry.replacement
                                vocabularyError = nil
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit vocabulary entry for \(entry.replacement)")

                            Button(role: .destructive) {
                                dictation.removeVocabularyEntry(entry.id)
                                if editingVocabularyID == entry.id {
                                    clearVocabularyDraft()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete vocabulary entry for \(entry.replacement)")
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("When enabled, Whisper uses saved words as recognition hints. All models preserve their spelling and apply learned corrections locally. Parakeet recognition hints are not supported yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dictation")
        .fileImporter(
            isPresented: vocabularyImportPresentationBinding(.file),
            allowedContentTypes: [.text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { beginVocabularyImport(.file(url)) }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    vocabularyImportFeedback = .failure(error.localizedDescription)
                }
            }
        }
        .sheet(isPresented: vocabularyImportPresentationBinding(.paste), onDismiss: cancelVocabularyImport) {
            VocabularyPasteSheet(
                isImporting: vocabularyImportOperation != nil,
                errorMessage: vocabularyImportFeedback?.errorMessage,
                onImport: { beginVocabularyImport(.paste($0)) },
                onCancel: {
                    cancelVocabularyImport()
                    vocabularyImportPresentation = nil
                }
            )
        }
        .alert(item: $modelToRemove) { model in
            let descriptor = DictationModelDescriptor.descriptor(for: model)
            return Alert(
                title: Text("Remove \(descriptor.displayName)?"),
                message: Text("This frees about \(descriptor.downloadSizeLabel). You can download it again later."),
                primaryButton: .destructive(Text("Remove")) {
                    dictation.removeModel(model)
                },
                secondaryButton: .cancel()
            )
        }
        .confirmationDialog(
            "Remove \(S1MiniModel.displayName)?",
            isPresented: $showS1MiniRemovalConfirmation
        ) {
            Button("Remove 462 MiB model", role: .destructive) {
                dictation.removeS1Mini()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("English transcript cleanup will turn off. Vocabulary corrections will keep working, and you can download the model again later.")
        }
        .onDisappear { dictation.cancelMicrophoneTest() }
        .onAppear { vocabularyImportLifetime = UUID() }
        .modifier(SettingsWindowCloseObserver(window: settingsWindow) {
            endPractice()
            vocabularyImportPresentation = nil
            cancelVocabularyImport()
        })
        .onDisappear {
            endPractice()
            vocabularyImportLifetime = nil
            vocabularyImportPresentation = nil
            cancelVocabularyImport()
        }
        .task {
            await microphonePermission.requestIfNeeded()
        }
        .task {
            await shortcutMonitor.refreshReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            microphonePermission.refresh()
            Task {
                await shortcutMonitor.refreshReadiness()
            }
        }
    }

    private var permissionSection: some View {
        Section {
            LabeledContent("Microphone", value: microphoneStatusLabel)
            if microphonePermission.status == .notDetermined {
                Button("Request microphone access") {
                    Task { await microphonePermission.requestIfNeeded() }
                }
                .disabled(microphonePermission.isRequesting)
            } else if microphonePermission.status == .denied || microphonePermission.status == .restricted {
                Text(microphonePermissionGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Microphone Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }

            LabeledContent("Gojo helper", value: helperStatusLabel)
            if case .unavailable = shortcutMonitor.helperState {
                Text("Gojo could not connect to its background helper. Restart Gojo if retrying does not restore the connection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry connection") {
                    Task { await shortcutMonitor.start() }
                }
            }
            LabeledContent("Accessibility", value: accessibilityStatusLabel)
            if case .available = shortcutMonitor.helperState,
               shortcutMonitor.accessibilityState != .trusted {
                Button("Enable Accessibility") {
                    Task { await shortcutMonitor.start(promptIfNeeded: true) }
                }
                .disabled(shortcutMonitor.accessibilityState == .requesting)
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            LabeledContent("Dictation shortcut", value: shortcutStatusLabel)
            if case .unavailable(.tap) = shortcutMonitor.shortcutReadiness {
                Text("Gojo could not activate the dictation shortcut. Retry after checking Accessibility access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry shortcut") {
                    Task { await shortcutMonitor.start() }
                }
            }
            LabeledContent("Microphone test", value: microphoneTestLabel)
            if dictation.microphoneTestState == .testing {
                Button("Cancel microphone test") { dictation.cancelMicrophoneTest() }
            } else {
                Button("Test microphone") { dictation.testMicrophone() }
                    .disabled(microphonePermission.status != .authorized || !dictation.canTestMicrophone)
            }
            if case .failed(let detail) = dictation.microphoneTestState {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Permissions")
        }
    }

    private var helperStatusLabel: String {
        switch shortcutMonitor.helperState {
        case .checking: return "Checking…"
        case .available: return "Connected"
        case .unavailable: return "Unavailable"
        }
    }

    private var accessibilityStatusLabel: String {
        switch shortcutMonitor.accessibilityState {
        case .unknown: return "Not checked"
        case .notTrusted: return "Required"
        case .requesting: return "Waiting for permission…"
        case .trusted: return "Allowed"
        }
    }

    private var shortcutStatusLabel: String {
        switch shortcutMonitor.shortcutReadiness {
        case .stopped: return "Inactive"
        case .checking: return "Checking…"
        case .awaitingAccessibility: return "Waiting for Accessibility"
        case .ready: return "Active"
        case .unavailable: return "Unavailable"
        }
    }

    private var microphoneTestLabel: String {
        switch dictation.microphoneTestState {
        case .idle: return "Not tested"
        case .testing: return "Checking audio input…"
        case .passed: return "Audio received"
        case .failed: return "Unavailable"
        }
    }

    private var microphoneStatusLabel: String {
        if microphonePermission.isRequesting { return "Waiting for permission…" }
        switch microphonePermission.status {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private var microphonePermissionGuidance: String {
        if microphonePermission.status == .restricted {
            return "Microphone access is restricted on this Mac. Review Screen Time or device management restrictions."
        }
        return "Allow Gojo in System Settings > Privacy & Security > Microphone."
    }

    private var practiceSection: some View {
        Section {
            Text("Click the field and hold Control–Option to dictate. Press Space while holding to lock the microphone, then repeat the shortcut to finish.")
                .font(.caption)
                .foregroundStyle(.secondary)
            DictationPracticeField(fieldID: practiceFieldID)
                .frame(height: 100)
            HStack {
                Button {
                    if dictation.activePracticeFieldID == practiceFieldID {
                        dictation.finishVoiceMode()
                    } else {
                        dictation.beginPractice(fieldID: practiceFieldID)
                    }
                } label: {
                    Text(dictation.activePracticeFieldID == practiceFieldID ? "Finish" : "Start")
                        .frame(width: 52)
                }
                .disabled(dictation.activePracticeFieldID == nil && !dictation.canChangeModel)
                Button("Cancel") { dictation.cancelPractice(fieldID: practiceFieldID) }
                    .disabled(dictation.activePracticeFieldID != practiceFieldID)
                Spacer()
                Text(dictation.activePracticeFieldID == practiceFieldID
                     ? DictationSettingsStatus.title(for: dictation.state) : "Ready to practice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 28)
        } header: {
            Text("Try dictation")
        } footer: {
            Text("Practice text stays in this field and is never saved. This checks dictation inside Gojo. Accessibility delivery to other apps is checked separately.")
        }
    }

    private var experienceSection: some View {
        Section {
            Picker("Intent", selection: Binding(
                get: { dictation.selectedIntent }, set: { dictation.setIntent($0) }
            )) {
                ForEach(DictationSessionIntent.allCases) { intent in
                    Text(intent.label).tag(intent)
                }
            }
            Text(intentDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Spoken commands", selection: Binding(
                get: { dictation.spokenCommandMode }, set: { dictation.setSpokenCommandMode($0) }
            )) {
                Text("Off").tag(DictationSpokenCommandMode.off)
                Text("Punctuation").tag(DictationSpokenCommandMode.punctuation)
                Text("Punctuation and code").tag(DictationSpokenCommandMode.punctuationAndCode)
            }
            .disabled(dictation.selectedIntent == .literal)
            if dictation.spokenCommandMode != .off, dictation.selectedIntent != .literal {
                Picker("Command language", selection: Binding(
                    get: { dictation.commandLanguage }, set: { dictation.setCommandLanguage($0) }
                )) {
                    Text("English").tag(DictationCommandLanguage.english)
                    Text("Spanish").tag(DictationCommandLanguage.spanish)
                    Text("Portuguese").tag(DictationCommandLanguage.portuguese)
                }
                Text("Say commands in the selected language. Say literal before a command to keep its words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let capabilities = dictation.currentModelCapabilities {
                switch capabilities.language {
                case .fixedEnglish:
                    LabeledContent("Recognition language", value: "English")
                case .automaticOnly:
                    LabeledContent("Recognition language", value: "Automatic detection")
                case .selectable(let languages):
                    Picker("Recognition language", selection: recognitionLanguageCodeBinding) {
                        Text("Automatic detection").tag("auto")
                        ForEach(languages.sorted(), id: \.self) { code in
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                        }
                    }
                }
                if capabilities.supportsTranslationToEnglish {
                    Toggle("Translate to English", isOn: Binding(
                        get: { dictation.translatesToEnglish }, set: { dictation.setTranslatesToEnglish($0) }
                    ))
                }
                if capabilities.supportsRecognizedPreview {
                    Toggle("Draft preview", isOn: Binding(
                        get: { dictation.previewEnabled }, set: { dictation.setPreviewEnabled($0) }
                    ))
                    Text("Shows recent recognized speech while holding the shortcut. The full recording is transcribed again when you finish. Available with local Parakeet Unified only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Quiet sound feedback", isOn: Binding(
                get: { dictation.cuesEnabled }, set: { dictation.setCuesEnabled($0) }
            ))
            Picker("Local model memory", selection: Binding(
                get: { dictation.residencyPolicy }, set: { dictation.setResidencyPolicy($0) }
            )) {
                Text("Keep ready").tag(DictationResidencyPolicy.keepWarm)
                Text("Release after idle").tag(DictationResidencyPolicy.releaseAfterIdle)
            }
        } header: {
            Text("Dictation behavior")
        } footer: {
            Text("Changes apply to your next dictation. Literal preserves recognized wording and disables spoken commands and cleanup. Code skips cleanup. English cleanup runs only when the recognition language or translation guarantees English output.")
        }
    }

    private var inputSection: some View {
        Section {
            HStack {
                Picker("Microphone", selection: inputDeviceUIDBinding) {
                    Text("System default").tag("")
                    ForEach(dictation.inputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                    if case .deviceUID(let uid) = dictation.selectedInput,
                       !dictation.inputDevices.contains(where: { $0.id == uid }) {
                        Text("Selected microphone unavailable").tag(uid)
                    }
                }
                Button("Refresh") { dictation.refreshInputDevices() }
            }
            LabeledContent("Current input", value: dictation.currentInputName ?? "Not recording")
            Toggle("Adapt to quiet speech", isOn: Binding(
                get: { dictation.adaptiveSpeech }, set: { dictation.setAdaptiveSpeech($0) }
            ))
        } header: {
            Text("Audio input")
        } footer: {
            Text("Microphone changes apply to the next recording. If a selected microphone disconnects, recording stops so you can choose an available input.")
        }
        .onAppear { dictation.refreshInputDevices() }
    }

    private var intentDescription: String {
        switch dictation.selectedIntent {
        case .standard: return "Use your normal cleanup and writing style."
        case .literal: return "Keep recognized wording, paragraph breaks, and personal vocabulary spelling."
        case .code: return "Keep symbols and formatting without prose cleanup."
        case .chat: return "Use conversational text with your selected cleanup style."
        }
    }

    private var recognitionLanguageCodeBinding: Binding<String> {
        Binding(
            get: { dictation.recognitionLanguage.persistedCode },
            set: { dictation.setRecognitionLanguage($0 == "auto" ? .automatic : .fixed($0)) }
        )
    }

    private var inputDeviceUIDBinding: Binding<String> {
        Binding(
            get: {
                if case .deviceUID(let uid) = dictation.selectedInput { return uid }
                return ""
            },
            set: { dictation.setInput($0.isEmpty ? .systemDefault : .deviceUID($0)) }
        )
    }

    private func endPractice() {
        DictationPracticeRegistry.shared.invalidate(fieldID: practiceFieldID)
        dictation.cancelPractice(fieldID: practiceFieldID)
    }

    private var dictationProviderBinding: Binding<DictationProvider> {
        Binding(
            get: { dictation.selectedProvider },
            set: { provider in
                dictation.setProvider(provider)
            }
        )
    }

    private var openRouterModelBinding: Binding<String> {
        Binding(
            get: { dictation.selectedOpenRouterModelID },
            set: { dictation.selectOpenRouterModel($0) }
        )
    }

    private var cleanupEnabledBinding: Binding<Bool> {
        Binding(
            get: { dictation.cleanupEnabled },
            set: { dictation.setCleanupEnabled($0) }
        )
    }

    private var learnsCorrectionsBinding: Binding<Bool> {
        Binding(
            get: { dictation.learnsCorrections },
            set: { dictation.setLearnsCorrections($0) }
        )
    }

    private var writingStyleBinding: Binding<DictationWritingStyle> {
        Binding(
            get: { dictation.writingStyle },
            set: { dictation.setWritingStyle($0) }
        )
    }

    private var transcriptionPrivacyDescription: String {
        if dictation.selectedProvider == .local {
            return "On-device transcription keeps your audio on this Mac."
        }
        return "OpenRouter transcription sends your recorded audio to the selected model provider. Your API key is stored only in your macOS Keychain."
    }

    private var writingStylePrivacyDescription: String {
        if dictation.cleanupEnabled {
            return "S1-mini cleans English transcripts entirely on this Mac. If cleanup fails, Gojo inserts the vocabulary-corrected transcription."
        }
        if !dictation.s1MiniInstalled {
            return "Download S1-mini by Superwhisper to add private, on-device English transcript cleanup."
        }
        return "Turn on AI polish to clean transcripts locally with your preferred writing style."
    }

    private enum VocabularyImportPresentation {
        case file
        case paste
    }

    private struct VocabularyImportOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private enum VocabularyImportSource: Sendable {
        case file(URL)
        case paste(String)
    }

    private enum VocabularyImportFeedback {
        case report(DictationVocabularyImport.Report)
        case failure(String)

        var message: String {
            switch self {
            case .report(let report):
                return "Added \(report.added) \(report.added == 1 ? "word" : "words"). Skipped \(report.duplicates) \(report.duplicates == 1 ? "duplicate" : "duplicates"), \(report.invalid) invalid \(report.invalid == 1 ? "word" : "words"), and \(report.overLimit) beyond the \(DictationVocabularyEntry.maximumEntries)-entry limit."
            case .failure(let detail):
                return "Import failed. \(detail) No words imported."
            }
        }

        var errorMessage: String? {
            if case .failure = self { return message }
            return nil
        }
    }

    private enum VocabularyImportFileFailure: LocalizedError {
        case notRegularFile
        case unsupportedType

        var errorDescription: String? {
            switch self {
            case .notRegularFile: return "Choose a regular file on this Mac."
            case .unsupportedType: return "Choose a JSON, CSV, or plain text file."
            }
        }
    }

    private func vocabularyImportPresentationBinding(_ presentation: VocabularyImportPresentation) -> Binding<Bool> {
        Binding(
            get: { vocabularyImportPresentation == presentation },
            set: { isPresented in
                if isPresented {
                    vocabularyImportPresentation = presentation
                } else if vocabularyImportPresentation == presentation {
                    vocabularyImportPresentation = nil
                }
            }
        )
    }

    @MainActor
    private func beginVocabularyImport(_ source: VocabularyImportSource) {
        guard settingsWindow?.isVisible == true,
              vocabularyImportOperation == nil, let lifetime = vocabularyImportLifetime else { return }
        vocabularyImportFeedback = nil
        let id = UUID()
        let worker = Task.detached(priority: .userInitiated) {
            try Self.readVocabularyImport(source)
        }
        let task = Task { @MainActor in
            defer {
                if vocabularyImportOperation?.id == id { vocabularyImportOperation = nil }
            }
            do {
                let document = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard vocabularyImportOperation?.id == id, vocabularyImportLifetime == lifetime else { return }
                vocabularyImportFeedback = .report(dictation.importVocabulary(document))
                if vocabularyImportPresentation == .paste { vocabularyImportPresentation = nil }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled,
                      vocabularyImportOperation?.id == id,
                      vocabularyImportLifetime == lifetime else { return }
                vocabularyImportFeedback = .failure(error.localizedDescription)
            }
        }
        vocabularyImportOperation = VocabularyImportOperation(id: id, task: task)
    }

    private func cancelVocabularyImport() {
        vocabularyImportOperation?.task.cancel()
        vocabularyImportOperation = nil
    }

    nonisolated private static func readVocabularyImport(
        _ source: VocabularyImportSource
    ) throws -> DictationVocabularyImport.Document {
        try Task.checkCancellation()
        switch source {
        case .paste(let text):
            guard text.utf8.count <= DictationVocabularyImport.maximumBytes else {
                throw DictationVocabularyImport.Failure.tooLarge
            }
            return try DictationVocabularyImport.parse(Data(text.utf8), format: .wordList)
        case .file(let url):
            guard url.isFileURL else { throw VocabularyImportFileFailure.notRegularFile }
            return try url.accessSecurityScopedResource { scopedURL in
                let values = try scopedURL.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
                guard values.isRegularFile == true else { throw VocabularyImportFileFailure.notRegularFile }
                let format: DictationVocabularyImport.Format
                switch scopedURL.pathExtension.lowercased() {
                case "json": format = .json
                case "csv": format = .csv
                default:
                    guard values.contentType?.conforms(to: .plainText) == true else {
                        throw VocabularyImportFileFailure.unsupportedType
                    }
                    format = .wordList
                }
                let handle = try FileHandle(forReadingFrom: scopedURL)
                defer { try? handle.close() }
                var data = Data()
                while data.count <= DictationVocabularyImport.maximumBytes {
                    try Task.checkCancellation()
                    let remaining = DictationVocabularyImport.maximumBytes + 1 - data.count
                    guard let chunk = try handle.read(upToCount: min(65_536, remaining)), !chunk.isEmpty else { break }
                    data.append(chunk)
                    if data.count > DictationVocabularyImport.maximumBytes {
                        throw DictationVocabularyImport.Failure.tooLarge
                    }
                }
                return try DictationVocabularyImport.parse(data, format: format)
            }
        }
    }

    private func saveVocabularyDraft() {
        vocabularyError = dictation.saveVocabularyEntry(
            id: editingVocabularyID,
            spoken: vocabularySpokenDraft,
            replacement: vocabularyReplacementDraft
        )
        if vocabularyError == nil {
            clearVocabularyDraft()
        }
    }

    private func clearVocabularyDraft() {
        editingVocabularyID = nil
        vocabularySpokenDraft = ""
        vocabularyReplacementDraft = ""
        vocabularyError = nil
    }

    private func saveOpenRouterAPIKey() {
        let key = openRouterAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if dictation.saveOpenRouterAPIKey(key) {
            openRouterAPIKeyDraft = ""
            isReplacingOpenRouterKey = false
        }
    }

    private var showsModelPreparation: Bool {
        guard dictation.isPreparingTranscriber else { return false }
        switch dictation.state {
        case .idle, .succeeded: return true
        default: return false
        }
    }

    private func modelButtonTitle(for model: DictationModelID) -> String {
        if dictation.preparingModel == model { return "Downloading…" }
        if dictation.switchingModel == model { return "Switching…" }
        if dictation.selectedModel == model, dictation.isModelInstalled(model) { return "Selected" }
        if dictation.isModelInstalled(model) { return "Use" }
        return "Download"
    }

    private func modelButtonDisabled(for model: DictationModelID) -> Bool {
        if dictation.preparingModel != nil { return true }
        if !dictation.canChangeModel { return true }
        return dictation.selectedModel == model && dictation.isModelInstalled(model)
    }

    @ViewBuilder
    private func modelDownloadProgress(_ download: DictationModelDownload, modelName: String) -> some View {
        switch download.phase {
        case .preparing:
            ProgressView("Preparing download…")
                .progressViewStyle(.linear)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(modelName) download")
                .accessibilityValue("Preparing download")
        case .downloading(let fraction):
            ProgressView(value: fraction, total: 1) {
                Text("File download progress")
            } currentValueLabel: {
                Text("\(Int(fraction * 100))%")
                    .monospacedDigit()
            }
            .progressViewStyle(.linear)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(modelName) download")
            .accessibilityValue("\(Int(fraction * 100)) percent file download progress")
        case .verifying:
            ProgressView("Verifying model…")
                .progressViewStyle(.linear)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(modelName) download")
                .accessibilityValue("Verifying model")
        }
    }
}

private struct VocabularyPasteSheet: View {
    @State private var draft = ""
    let isImporting: Bool
    let errorMessage: String?
    let onImport: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste vocabulary").font(.headline)
            Text("Enter one word or phrase per line. Existing words stay, and duplicates are skipped.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $draft)
                .font(.body)
                .border(Color.secondary.opacity(0.3))
                .accessibilityLabel("Words to import")
                .disabled(isImporting)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                if isImporting {
                    ProgressView().controlSize(.small)
                    Text("Importing words…").font(.caption)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Import") { onImport(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting)
            }
        }
        .padding(20)
        .frame(width: 500, height: 360)
        .interactiveDismissDisabled(isImporting)
    }
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

#Preview {
    HUD()
}
