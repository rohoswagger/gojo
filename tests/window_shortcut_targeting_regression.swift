import AppKit
import ApplicationServices
import Combine
import KeyboardShortcuts

final class FixtureScreen: NSScreen {
    let uuid: String
    private let fixtureFrame: CGRect
    private let fixtureVisibleFrame: CGRect

    init(uuid: String, frame: CGRect, visibleFrame: CGRect) {
        self.uuid = uuid
        fixtureFrame = frame
        fixtureVisibleFrame = visibleFrame
        super.init()
    }

    override var frame: CGRect { fixtureFrame }
    override var visibleFrame: CGRect { fixtureVisibleFrame }
    override var localizedName: String { uuid }
}

extension NSScreen {
    static var fixtureScreens: [NSScreen] = []

    var displayUUID: String? { (self as? FixtureScreen)?.uuid }

    static func screen(withUUID uuid: String) -> NSScreen? {
        fixtureScreens.first { $0.displayUUID == uuid }
    }

    static func screen(containing frame: CGRect) -> NSScreen? {
        fixtureScreens.max {
            let lhs = $0.frame.intersection(frame)
            let rhs = $1.frame.intersection(frame)
            return max(0, lhs.width) * max(0, lhs.height) < max(0, rhs.width) * max(0, rhs.height)
        }
    }
}

struct FocusedWindow {
    let windowID: CGWindowID?
    let pid: pid_t
    let appName: String
    let title: String?
    let normalFrame: CGRect
    let screen: NSScreen

    var identity: String { "window-\(windowID ?? 0)" }
}

extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

@MainActor
final class GojoViewModel {
    let screenUUID: String?
    let windowPowerState = WindowPowerState()

    init(screenUUID: String?) { self.screenUUID = screenUUID }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var viewModels: [String: GojoViewModel] = [:]
    let vm = GojoViewModel(screenUUID: "built-in")
    var pointerScreenUUID = "built-in"

    func viewModelForCurrentMouseLocation() -> GojoViewModel {
        viewModels[pointerScreenUUID] ?? vm
    }
}

struct WindowFrameResult {
    let success: Bool
    let resultingFrame: CGRect?
}

@MainActor
final class XPCHelperClient {
    static let shared = XPCHelperClient()
    private(set) var raiseRequests: [(id: CGWindowID?, allowApplicationFallback: Bool)] = []

    func raiseWindow(pid: pid_t, windowID: CGWindowID?, allowApplicationFallback: Bool) async -> Bool {
        raiseRequests.append((windowID, allowApplicationFallback))
        return windowID.flatMap { FocusedWindowProvider.windows[$0] }?.pid == pid
    }

    func performZoom(pid: pid_t, windowID: CGWindowID?) async -> WindowFrameResult {
        FocusedWindowProvider.zoomedWindowIDs.append(windowID ?? 0)
        return WindowFrameResult(success: true, resultingFrame: nil)
    }

    func setWindowFrame(_ frame: CGRect, pid: pid_t, windowID: CGWindowID?) async -> WindowFrameResult {
        FocusedWindowProvider.move(windowID: windowID, to: frame)
        return WindowFrameResult(success: true, resultingFrame: frame)
    }

    func enumerateWindows(screenUUID: String?) async -> [[String: Any]] { [] }
}

@MainActor
final class FocusedWindowProvider {
    enum ProviderError: Error { case permissionMissing, noFocusedWindow, noFocusedWindowOnScreen }

    static var windows: [CGWindowID: FocusedWindow] = [:]
    static var focusedWindowID: CGWindowID = 0
    static var movedWindows: [(id: CGWindowID, frame: CGRect)] = []
    static var zoomedWindowIDs: [CGWindowID] = []
    static var isAuthorized = true

    func focusedWindow(promptIfNeeded: Bool = false) async throws -> FocusedWindow {
        guard Self.isAuthorized else { throw ProviderError.permissionMissing }
        guard let window = Self.windows[Self.focusedWindowID] else { throw ProviderError.noFocusedWindow }
        return window
    }

    func activeScreen() -> NSScreen? {
        Self.windows[Self.focusedWindowID]?.screen
    }

    func focusedWindow(for screen: NSScreen?, promptIfNeeded: Bool = false) async throws -> FocusedWindow {
        let window = try await focusedWindow(promptIfNeeded: promptIfNeeded)
        guard let screen, screen.displayUUID != window.screen.displayUUID else { return window }
        guard let onScreen = Self.windows.values.first(where: { $0.screen.displayUUID == screen.displayUUID }) else {
            throw ProviderError.noFocusedWindowOnScreen
        }
        return onScreen
    }

    func enumerateWindows(on screen: NSScreen) -> [WindowSummary] {
        Self.windows.values.filter { $0.screen.displayUUID == screen.displayUUID }.map(Self.summary)
    }

    func resolveWindow(pid: pid_t, windowID: CGWindowID?, fallbackAppName: String, fallbackTitle: String?) -> FocusedWindow? {
        windowID.flatMap { Self.windows[$0] }
    }

    func setFrame(_ frame: CGRect, for window: FocusedWindow) async -> Bool {
        Self.move(windowID: window.windowID, to: frame)
        return true
    }

    static func move(windowID: CGWindowID?, to frame: CGRect) {
        guard let windowID, let window = windows[windowID] else { fatalError("Unknown window") }
        movedWindows.append((windowID, frame))
        windows[windowID] = FocusedWindow(
            windowID: windowID, pid: window.pid, appName: window.appName, title: window.title,
            normalFrame: frame, screen: window.screen
        )
    }

    static func summary(_ window: FocusedWindow) -> WindowSummary {
        WindowSummary(
            id: window.identity, pid: window.pid, windowID: window.windowID, appName: window.appName,
            bundleIdentifier: nil, icon: nil, title: window.title, normalFrame: window.normalFrame,
            currentAction: nil
        )
    }
}

@main
struct WindowShortcutTargetingRegression {
    @MainActor
    static func main() async {
        let builtIn = FixtureScreen(
            uuid: "built-in", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 875)
        )
        let external = FixtureScreen(
            uuid: "external-left", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        )
        NSScreen.fixtureScreens = [builtIn, external]
        let delegate = AppDelegate()
        AppDelegate.shared = delegate
        delegate.viewModels = ["built-in": delegate.vm, "external-left": GojoViewModel(screenUUID: "external-left")]
        let originalBuiltInFrame = CGRect(x: 120, y: 100, width: 800, height: 600)
        let originalExternalFrame = CGRect(x: -1800, y: 100, width: 1000, height: 700)
        FocusedWindowProvider.windows = [
            11: FocusedWindow(windowID: 11, pid: 111_111, appName: "Built-in editor", title: nil, normalFrame: originalBuiltInFrame, screen: builtIn),
            22: FocusedWindow(windowID: 22, pid: 222_222, appName: "External editor", title: nil, normalFrame: originalExternalFrame, screen: external)
        ]
        FocusedWindowProvider.focusedWindowID = 22
        WindowShortcutController.shared.register()

        await pressShortcut(.windowRightHalf)
        expect(FocusedWindowProvider.movedWindows.last?.id == 22, "Shortcut with pointer on built-in display must move focused external window 22; got \(String(describing: FocusedWindowProvider.movedWindows.last?.id))")
        expect(FocusedWindowProvider.windows[22]?.normalFrame == CGRect(x: -960, y: 0, width: 960, height: 1055), "Focused external window must snap within its display")
        expect(FocusedWindowProvider.windows[11]?.normalFrame == originalBuiltInFrame, "Pointer display window must keep its frame")
        expect(delegate.viewModels["external-left"]?.windowPowerState.appName == "External editor", "Shortcut status must update the focused display")
        print("window-shortcut-external-focus-pass")

        delegate.pointerScreenUUID = "external-left"
        FocusedWindowProvider.focusedWindowID = 11
        await pressShortcut(.windowLeftHalf)
        expect(FocusedWindowProvider.movedWindows.last?.id == 11, "Shortcut must follow focus back to built-in window 11")
        expect(FocusedWindowProvider.windows[11]?.normalFrame == CGRect(x: 0, y: 25, width: 720, height: 875), "Built-in snap must use built-in visible frame")
        print("window-shortcut-built-in-focus-pass")

        FocusedWindowProvider.focusedWindowID = 22
        await pressShortcut(.windowZoom)
        expect(FocusedWindowProvider.zoomedWindowIDs == [22], "Zoom shortcut must address the focused external window")
        print("window-shortcut-zoom-focus-pass")

        delegate.pointerScreenUUID = "built-in"
        let frameActions: [(KeyboardShortcuts.Name, CGRect)] = [
            (.windowLeftHalf, CGRect(x: -1920, y: 0, width: 960, height: 1055)),
            (.windowTopHalf, CGRect(x: -1920, y: 528, width: 1920, height: 527)),
            (.windowBottomHalf, CGRect(x: -1920, y: 0, width: 1920, height: 527)),
            (.windowMaximize, CGRect(x: -1920, y: 0, width: 1920, height: 1055))
        ]
        for (shortcut, expectedFrame) in frameActions {
            await pressShortcut(shortcut)
            expect(FocusedWindowProvider.movedWindows.last?.id == 22, "\(shortcut) must move focused external window 22")
            expect(FocusedWindowProvider.windows[22]?.normalFrame == expectedFrame, "\(shortcut) must produce \(expectedFrame)")
        }
        await pressShortcut(.windowMaximize)
        expect(FocusedWindowProvider.movedWindows.last?.id == 22, "Repeated maximize must restore the focused external window")
        expect(FocusedWindowProvider.windows[22]?.normalFrame == CGRect(x: -1800, y: 100, width: 1000, height: 700), "Repeated maximize must restore the saved external frame")
        print("window-shortcut-all-actions-and-restore-pass")

        let beforeDeniedMoves = FocusedWindowProvider.movedWindows.count
        let beforeDeniedZooms = FocusedWindowProvider.zoomedWindowIDs.count
        FocusedWindowProvider.isAuthorized = false
        await pressShortcut(.windowRightHalf)
        await pressShortcut(.windowZoom)
        expect(FocusedWindowProvider.movedWindows.count == beforeDeniedMoves && FocusedWindowProvider.zoomedWindowIDs.count == beforeDeniedZooms, "Denied Accessibility must prevent frame and zoom mutations")
        let deniedState = delegate.viewModels["external-left"]!.windowPowerState
        expect(deniedState.title == "Accessibility access needed" && !deniedState.isAccessibilityAuthorized, "Denied shortcut must show missing Accessibility permission on the active external display")
        FocusedWindowProvider.isAuthorized = true
        print("window-shortcut-permission-denied-pass")

        let selected = FocusedWindowProvider.summary(FocusedWindowProvider.windows[11]!)
        await WindowActionExecutor.shared.execute(
            .bottomHalf, target: selected, screenUUID: "built-in", state: delegate.vm.windowPowerState
        )
        expect(FocusedWindowProvider.movedWindows.last?.id == 11, "Windows tab explicit selection must win over keyboard focus on window 22")
        expect(FocusedWindowProvider.windows[11]?.normalFrame == CGRect(x: 0, y: 25, width: 1440, height: 437), "Windows tab selection must use its owning display")
        print("window-tab-explicit-target-pass")

        await WindowActionExecutor.shared.execute(.topHalf, screenUUID: "built-in", state: delegate.vm.windowPowerState)
        expect(FocusedWindowProvider.movedWindows.last?.id == 11, "Windows tab without explicit selection must stay scoped to its display")
        expect(FocusedWindowProvider.windows[11]?.normalFrame == CGRect(x: 0, y: 463, width: 1440, height: 437), "Windows tab fallback must use its display bounds")
        print("window-tab-display-scope-pass")

        let focusedFrame = FocusedWindowProvider.windows[22]!.normalFrame
        let sibling = FocusedWindow(windowID: 33, pid: 222_222, appName: "External editor", title: "Second document", normalFrame: CGRect(x: -1700, y: 150, width: 900, height: 650), screen: external)
        FocusedWindowProvider.windows[33] = sibling
        let siblingSummary = FocusedWindowProvider.summary(sibling)
        let externalState = delegate.viewModels["external-left"]!.windowPowerState
        await WindowActionExecutor.shared.execute(.leftHalf, target: siblingSummary, screenUUID: "external-left", state: externalState)
        expect(FocusedWindowProvider.movedWindows.last?.id == 33, "Windows tab must move the selected same-app sibling window 33")
        expect(FocusedWindowProvider.windows[33]?.normalFrame == CGRect(x: -1920, y: 0, width: 960, height: 1055), "Selected sibling must snap on the external display")
        expect(FocusedWindowProvider.windows[22]?.normalFrame == focusedFrame, "Selecting another window in the same app must preserve focused window 22")
        expect(XPCHelperClient.shared.raiseRequests.last?.allowApplicationFallback == false, "Windows tab must raise the exact selected window")
        print("window-tab-same-app-target-pass")

        FocusedWindowProvider.windows.removeValue(forKey: 33)
        let moveCount = FocusedWindowProvider.movedWindows.count
        await WindowActionExecutor.shared.execute(.rightHalf, target: siblingSummary, screenUUID: "external-left", state: externalState)
        expect(FocusedWindowProvider.movedWindows.count == moveCount, "A stale Windows tab selection must not move a sibling window")
        expect(externalState.statusKind == .error && externalState.title == "Window unavailable", "A stale selection must report the unavailable window")
        print("window-tab-stale-target-pass")

        let arrangements: [(String, CGWindowID, CGRect, CGRect, CGRect)] = [
            ("external-right", 44,
             CGRect(x: 1440, y: 0, width: 2560, height: 1440),
             CGRect(x: 1440, y: 0, width: 2560, height: 1415),
             CGRect(x: 2720, y: 0, width: 1280, height: 1415)),
            ("external-above", 55,
             CGRect(x: 0, y: 900, width: 1920, height: 1080),
             CGRect(x: 0, y: 900, width: 1920, height: 1055),
             CGRect(x: 960, y: 900, width: 960, height: 1055)),
            ("external-below", 66,
             CGRect(x: 0, y: -1200, width: 1920, height: 1200),
             CGRect(x: 0, y: -1200, width: 1920, height: 1175),
             CGRect(x: 960, y: -1200, width: 960, height: 1175))
        ]
        for (uuid, id, frame, visibleFrame, expectedFrame) in arrangements {
            let screen = FixtureScreen(uuid: uuid, frame: frame, visibleFrame: visibleFrame)
            NSScreen.fixtureScreens.append(screen)
            FocusedWindowProvider.windows[id] = FocusedWindow(
                windowID: id, pid: pid_t(id) + 300_000, appName: uuid, title: nil,
                normalFrame: CGRect(x: frame.minX + 100, y: frame.minY + 100, width: 800, height: 600), screen: screen
            )
            FocusedWindowProvider.focusedWindowID = id
            await pressShortcut(.windowRightHalf)
            expect(FocusedWindowProvider.movedWindows.last?.id == id, "\(uuid) must keep keyboard-focused window \(id)")
            expect(FocusedWindowProvider.windows[id]?.normalFrame == expectedFrame, "\(uuid) must snap to \(expectedFrame)")
            expect(WindowPowerState.shared.appName == uuid, "A display without a notch view model must still receive shortcut status")
        }
        print("window-shortcut-display-arrangements-pass")
    }

    @MainActor
    private static func pressShortcut(_ name: KeyboardShortcuts.Name) async {
        let states = Array(AppDelegate.shared!.viewModels.values.map(\.windowPowerState)) + [WindowPowerState.shared]
        for state in states { state.statusKind = .idle }
        KeyboardShortcuts.press(name)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !states.contains(where: { $0.statusKind != .idle }) {
            expect(ContinuousClock.now < deadline, "Shortcut \(name) did not finish within two seconds")
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("Assertion failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
