//
//  AltTabManager.swift
//  Gojo
//
//  Coordinates the per-display window switcher (alt-tab): captures the windows
//  on the active display, owns the floating switcher panel, and raises the
//  selected window on commit. The keyboard handling lives in
//  AltTabHotKeyMonitor; this type owns the state and lifecycle.
//

import AppKit
import Combine
import Defaults

@MainActor
final class AltTabManager: ObservableObject {
    static let shared = AltTabManager()

    @Published private(set) var session: AltTabSession?
    private(set) var lastSelectionWasKeyboard = true

    private let windowProvider = FocusedWindowProvider()
    private lazy var panel = AltTabPanel()
    private var cancellables = Set<AnyCancellable>()
    private var recency = AltTabRecency()
    private var started = false

    private init() {}

    var isEnabled: Bool { Defaults[.altTabEnabled] }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let keys: [Defaults._AnyKey] = [.altTabEnabled, .altTabModifier]
        Defaults.publisher(keys: keys, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.reconfigure() }
            }
            .store(in: &cancellables)

        reconfigure()
    }

    private func reconfigure(promptIfNeeded: Bool = false) {
        if isEnabled {
            Task { await AltTabHotKeyMonitor.shared.start(promptIfNeeded: promptIfNeeded) }
        } else {
            AltTabHotKeyMonitor.shared.stop()
            if session != nil { cancel() }
        }
    }

    /// Called by the settings UI right after the user enables the feature, so we
    /// prompt for Accessibility if it isn't granted yet.
    func enableFromSettings() {
        Task { await AltTabHotKeyMonitor.shared.start(promptIfNeeded: true) }
    }

    // MARK: - Switching

    func handleTrigger(reverse: Bool) {
        guard !LicenseManager.lockedFlag else { return }
        if session == nil {
            open(reverse: reverse)
        } else {
            advance(reverse: reverse)
        }
    }

    private func open(reverse: Bool) {
        guard let activeScreen = windowProvider.activeScreen()
            ?? NSScreen.screenWithMouse
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
        }

        let screens: [NSScreen]
        if Defaults[.altTabCurrentDisplayOnly] {
            screens = [activeScreen]
        } else {
            screens = [activeScreen] + NSScreen.screens.filter { $0.displayUUID != activeScreen.displayUUID }
        }
        let items = captureItems(on: screens)

        guard !items.isEmpty else { return }

        let count = items.count
        let index = reverse
            ? AltTabSelection.advance(from: 0, count: count, reverse: true)
            : AltTabSelection.initialIndex(count: count)

        lastSelectionWasKeyboard = true
        session = AltTabSession(items: items, selectedIndex: index, screenUUID: activeScreen.displayUUID)
        panel.present(on: activeScreen)
        enrichTitles()
    }

    /// All switchable windows on the given displays: the on-screen windows of
    /// each display's active Space, unioned with windows on its other Spaces
    /// (including fullscreen). The on-screen list comes first so the frontmost
    /// window stays at index 0; cross-Space windows are appended, deduped by
    /// window.
    private func captureItems(on screens: [NSScreen]) -> [AltTabItem] {
        var result: [AltTabItem] = []
        var seen = Set<String>()

        func add(_ items: [AltTabItem]) {
            for item in items {
                let key = item.windowID.map { "w\($0)" } ?? item.id
                if seen.insert(key).inserted { result.append(item) }
            }
        }

        for screen in screens {
            add(windowProvider.enumerateWindows(on: screen).map { summary in
                AltTabItem(
                    id: summary.id,
                    pid: summary.pid,
                    windowID: summary.windowID,
                    appName: summary.appName,
                    title: summary.title,
                    icon: summary.icon
                )
            })
            add(AltTabSpaceEnumerator.items(on: screen))
        }
        let orderedIDs = recency.order(freshIDs: result.map(\.id))
        var itemsByID: [String: AltTabItem] = [:]
        for item in result where itemsByID[item.id] == nil {
            itemsByID[item.id] = item
        }
        return orderedIDs.compactMap { itemsByID[$0] }
    }

    func advance(reverse: Bool) {
        guard var s = session else { return }
        lastSelectionWasKeyboard = true
        s.selectedIndex = AltTabSelection.advance(from: s.selectedIndex, count: s.items.count, reverse: reverse)
        session = s
    }

    func select(index: Int) {
        guard var s = session,
              let selectedIndex = AltTabSelection.pointerIndex(index, count: s.items.count),
              selectedIndex != s.selectedIndex else {
            return
        }
        lastSelectionWasKeyboard = false
        s.selectedIndex = selectedIndex
        session = s
    }

    func commit() {
        guard let item = session?.selectedItem else {
            cancel()
            return
        }
        recency.promote(item.id)
        close()
        Task {
            _ = await XPCHelperClient.shared.raiseWindow(pid: item.pid, windowID: item.windowID)
        }
    }

    func cancel() {
        close()
    }

    private func close() {
        session = nil
        panel.dismiss()
    }

    // MARK: - Title enrichment

    /// Window titles require the Accessibility API, which only works in the XPC
    /// helper. We show icons + app names immediately, then fill in real titles
    /// asynchronously once they arrive.
    private func enrichTitles() {
        guard Defaults[.altTabShowTitles], let s = session else { return }
        let pairs = s.items.compactMap { item in
            item.windowID.map { (pid: item.pid, windowID: $0) }
        }
        guard !pairs.isEmpty else { return }

        Task {
            let titles = await XPCHelperClient.shared.windowTitles(for: pairs)
            await MainActor.run { self.applyTitles(titles) }
        }
    }

    private func applyTitles(_ titles: [CGWindowID: String]) {
        guard var s = session, !titles.isEmpty else { return }
        for index in s.items.indices {
            if let wid = s.items[index].windowID, let title = titles[wid] {
                s.items[index].title = title
            }
        }
        session = s
    }
}
