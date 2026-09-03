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

struct SettingsView: View {
    @State private var selectedTab: String
    @State private var accentColorUpdateTrigger = UUID()

    let updaterController: SPUStandardUpdaterController?

    init(updaterController: SPUStandardUpdaterController? = nil, initialTab: String = "General") {
        self.updaterController = updaterController
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
                    DictationSettings()
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
                    Text("Match menubar height")
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
                await XPCHelperClient.shared.isAccessibilityAuthorized()
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
    @State private var accessibilityAuthorized = false
    
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
                
                if !accessibilityAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility access is required to replace the system HUD.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button("Request Accessibility") {
                                XPCHelperClient.shared.requestAccessibilityAuthorization()
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
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
            }
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
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
                Picker(
                    selection: $hideNotchOption,
                    label:
                        HStack {
                            Text("Full screen behavior")
                            customBadge(text: "Beta")
                        }
                ) {
                    Text("Hide for all apps").tag(HideNotchOption.always)
                    Text("Hide for media app only").tag(
                        HideNotchOption.nowPlayingOnly)
                    Text("Never hide").tag(HideNotchOption.never)
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
    @AppStorage(DictationActivationMode.defaultsKey)
    private var dictationActivationModeRawValue = DictationActivationMode.holdToTalk.rawValue

    private var dictationActivationMode: DictationActivationMode {
        DictationActivationMode(rawValue: dictationActivationModeRawValue) ?? .holdToTalk
    }

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
                LabeledContent(
                    dictationActivationMode == .holdToTalk ? "Hold to Dictate:" : "Tap to Dictate:",
                    value: "⌃⌥"
                )
            } header: {
                Text("Dictation")
            } footer: {
                Text(dictationShortcutHelp)
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

    private var dictationShortcutHelp: String {
        switch dictationActivationMode {
        case .holdToTalk:
            return "Hold Control and Option while you talk. Release either key when you are done."
        case .tapToTalk:
            return "Tap Control and Option to start. Tap them again when you are done."
        }
    }
}

struct DictationSettings: View {
    @ObservedObject private var dictation = GojoDictationService.shared
    @AppStorage(DictationActivationMode.defaultsKey)
    private var dictationActivationModeRawValue = DictationActivationMode.holdToTalk.rawValue
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var accessibilityAuthorized = false
    @State private var modelToRemove: DictationModelID?
    @State private var openRouterAPIKeyDraft = ""
    @State private var isReplacingOpenRouterKey = false
    @State private var showS1MiniRemovalConfirmation = false
    @State private var vocabularySpokenDraft = ""
    @State private var vocabularyReplacementDraft = ""
    @State private var editingVocabularyID: UUID?
    @State private var vocabularyError: String?

    var body: some View {
        Form {
            Section {
                Picker("Activation", selection: dictationActivationModeBinding) {
                    ForEach(DictationActivationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Shortcut", value: "⌃⌥")
                LabeledContent("Status") {
                    if dictation.isPreparingTranscriber {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Preparing voice model…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(DictationSettingsStatus.title(for: dictation.state))
                    }
                }
                if dictation.isPreparingTranscriber {
                    Text("The first dictation after launch waits for this to finish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = dictation.stateDetail {
                    Text(detail)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } header: {
                Text("Voice input")
            } footer: {
                Text(dictationActivationHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(model.displayName)
                                    .fontWeight(.medium)
                                if model.isRecommended {
                                    Text("Recommended")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(model.engineLabel) · \(model.downloadSizeLabel)")
                                    .foregroundStyle(.secondary)
                            }

                            Text(model.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let error = dictation.modelErrors[model.id] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            HStack {
                                Button(modelButtonTitle(for: model.id)) {
                                    if dictation.isModelInstalled(model.id) {
                                        dictation.selectModel(model.id)
                                    } else {
                                        dictation.downloadModel(model.id)
                                    }
                                }
                                .disabled(modelButtonDisabled(for: model.id))

                                if dictation.isModelInstalled(model.id) {
                                    Button(
                                        dictation.removingModel == model.id ? "Removing…" : "Remove",
                                        role: .destructive
                                    ) {
                                        modelToRemove = model.id
                                    }
                                    .disabled(!dictation.canChangeModel)
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("Voice models")
                } footer: {
                    Text("Download one or more models, then choose which one Gojo should use. Dictation stays on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Polish English dictated text", isOn: cleanupEnabledBinding)
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

                    Text("A purpose-built English transcript normalizer running privately through llama.cpp.")
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
                TextField("When Gojo hears…", text: $vocabularySpokenDraft)
                    .accessibilityLabel("Spoken phrase")
                    .accessibilityHint("For example, g p t five point six sol.")
                    .onSubmit(saveVocabularyDraft)

                TextField("Replace it with…", text: $vocabularyReplacementDraft)
                    .accessibilityLabel("Preferred spelling")
                    .accessibilityHint("For example, gpt-5.6-sol.")
                    .onSubmit(saveVocabularyDraft)

                HStack {
                    Button(editingVocabularyID == nil ? "Add term" : "Save changes") {
                        saveVocabularyDraft()
                    }
                    .disabled(
                        vocabularySpokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || vocabularyReplacementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    if editingVocabularyID != nil {
                        Button("Cancel") {
                            clearVocabularyDraft()
                        }
                    }
                }

                if let vocabularyError {
                    Label(vocabularyError, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if dictation.vocabulary.isEmpty {
                    Text("No custom terms yet. Add names, code symbols, or technical jargon Gojo should spell exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dictation.vocabulary) { entry in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.spoken)
                                Text(entry.replacement)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button("Edit") {
                                editingVocabularyID = entry.id
                                vocabularySpokenDraft = entry.spoken
                                vocabularyReplacementDraft = entry.replacement
                                vocabularyError = nil
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit vocabulary entry for \(entry.spoken)")

                            Button(role: .destructive) {
                                dictation.removeVocabularyEntry(entry.id)
                                if editingVocabularyID == entry.id {
                                    clearVocabularyDraft()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete vocabulary entry for \(entry.spoken)")
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("Vocabulary replacements run on this Mac for every provider, even when AI cleanup is off or unavailable. Longer matching phrases take priority.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Microphone", value: microphoneStatusLabel)
                LabeledContent("Accessibility", value: accessibilityAuthorized ? "Allowed" : "Required")
                if microphoneStatus == .denied || !accessibilityAuthorized {
                    Button("Open Privacy & Security Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                    }
                }
            } header: {
                Text("Permissions")
            }
        }
        .navigationTitle("Dictation")
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
        .task {
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
    }

    private var microphoneStatusLabel: String {
        switch microphoneStatus {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private var dictationActivationMode: DictationActivationMode {
        DictationActivationMode(rawValue: dictationActivationModeRawValue) ?? .holdToTalk
    }

    private var dictationActivationModeBinding: Binding<DictationActivationMode> {
        Binding(
            get: { dictationActivationMode },
            set: { mode in
                dictationActivationModeRawValue = mode.rawValue
                DictationModifierHotKeyMonitor.shared.setActivationMode(mode)
            }
        )
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

    private var dictationActivationHelp: String {
        switch dictationActivationMode {
        case .holdToTalk:
            return "Click a text field, then hold Control and Option while you talk. Release either key when you are done. If a transcription is taking too long, press the shortcut again to cancel it and start over."
        case .tapToTalk:
            return "Click a text field, then tap Control and Option to start. Tap them again when you are done. If a transcription is taking too long, tap the shortcut again to cancel it and start over."
        }
    }

    private func modelButtonTitle(for model: DictationModelID) -> String {
        if dictation.preparingModel == model { return "Downloading…" }
        if dictation.switchingModel == model { return "Switching…" }
        if dictation.selectedModel == model, dictation.isModelInstalled(model) { return "In Use" }
        if dictation.isModelInstalled(model) { return "Use This Model" }
        return "Download"
    }

    private func modelButtonDisabled(for model: DictationModelID) -> Bool {
        if dictation.preparingModel != nil { return true }
        if !dictation.canChangeModel { return true }
        return dictation.selectedModel == model && dictation.isModelInstalled(model)
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).stroke(
                Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
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

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    HUD()
}
