import SwiftUI

private enum NotchState { case closed, open }
private enum CurrentView { case home, clipboard }

@MainActor
private enum AnimationScope {
    static var current: Int?
    static var next = 0
}

@MainActor
private func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    let previous = AnimationScope.current
    AnimationScope.next += 1
    AnimationScope.current = AnimationScope.next
    defer { AnimationScope.current = previous }
    return try body()
}

@MainActor
private enum Defaults {
    struct Key<Value> {
        let name: String
        let defaultValue: Value
    }
    static var values: [String: Any] = [:]
    static subscript<Value>(_ key: Key<Value>) -> Value {
        get { values[key.name] as? Value ?? key.defaultValue }
        set { values[key.name] = newValue }
    }
}

private extension Defaults.Key where Value == Bool {
    static let enableHaptics = Self(name: "haptics", defaultValue: false)
    static let openNotchOnHover = Self(name: "hover", defaultValue: true)
}

private extension Defaults.Key where Value == Double {
    static let minimumHoverDuration = Self(name: "dwell", defaultValue: 0.2)
}

@MainActor
private final class Coordinator {
    var firstLaunch = false
    var sneakPeek = (show: false, value: 0)
    var currentView = CurrentView.home
}

@MainActor
private final class ClipboardState {
    var keepsNotchOpenOnHoverExit = false
}

@MainActor
private final class SharingStateManager {
    static let shared = SharingStateManager()
    var preventNotchClose = false
}

@MainActor
private final class ViewModel {
    var hideOnClosed = true
    var notchState = NotchState.closed
    var isBatteryPopoverActive = false
    var revealTransaction: Int?
    var openTransaction: Int?
    var wasHiddenAtOpen: Bool?
    var openCalls = 0
    /* MODEL_PRESENTATION */

    func open() {
        wasHiddenAtOpen = isAutoHidden
        openTransaction = AnimationScope.current
        openCalls += 1
        notchState = .open
    }

    func close() {
        notchState = .closed
    }
}

@MainActor
private final class HoverFixture {
    let vm = ViewModel()
    let coordinator = Coordinator()
    let clipboardState = ClipboardState()
    var hoverTask: Task<Void, Never>?
    var isHovering = false
    var haptics = false
    let reduceMotion = false
    /* HOVER_ANIMATION */
    /* OPEN_ANIMATION */
    /* HOVER_METHODS */
}

@main
private struct NotchAutoHideHoverRegression {
    @MainActor private static var failures: [String] = []

    @MainActor
    static func main() async {
        let hidden = HoverFixture()
        hidden.handleHover(true)
        expect(hidden.isHovering, "Hover entry records pointer presence")
        expect(hidden.vm.notchState == .closed && hidden.vm.isAutoHidden, "Auto-hidden hover stays closed and invisible immediately during dwell")
        try? await Task.sleep(for: .milliseconds(40))
        expect(hidden.vm.notchState == .closed && hidden.vm.isAutoHidden, "Auto-hidden hover stays closed and invisible before configured dwell completes")
        await hidden.hoverTask?.value
        expect(hidden.vm.notchState == .open && !hidden.vm.isAutoHidden, "Dwell completion opens and reveals together")
        expect(hidden.vm.wasHiddenAtOpen == false && hidden.vm.openTransaction != nil && hidden.vm.openTransaction == hidden.vm.revealTransaction, "Reveal and opening share one animation transaction")

        let cancelled = HoverFixture()
        cancelled.handleHover(true)
        let pendingOpen = cancelled.hoverTask
        cancelled.handleHover(false)
        await pendingOpen?.value
        await cancelled.hoverTask?.value
        expect(cancelled.vm.notchState == .closed && cancelled.vm.isAutoHidden && !cancelled.isHovering && cancelled.vm.openCalls == 0, "Hover exit cancels pending opening and preserves hidden presentation")

        Defaults[.openNotchOnHover] = false
        let manual = HoverFixture()
        manual.handleHover(true)
        expect(manual.vm.notchState == .closed && !manual.vm.isAutoHidden && manual.hoverTask == nil, "Disabled hover opening still reveals the closed notch")
        Defaults[.openNotchOnHover] = true

        let desktop = HoverFixture()
        desktop.vm.hideOnClosed = false
        desktop.handleHover(true)
        expect(desktop.vm.notchState == .closed && !desktop.vm.isAutoHidden, "Uncovered desktop hover stays visible during dwell")
        await desktop.hoverTask?.value
        expect(desktop.vm.notchState == .open, "Uncovered desktop hover still opens after dwell")

        let sneakPeek = HoverFixture()
        sneakPeek.coordinator.sneakPeek.show = true
        sneakPeek.handleHover(true)
        expect(sneakPeek.vm.notchState == .closed && !sneakPeek.vm.isAutoHidden && sneakPeek.hoverTask == nil, "Sneak peek blocks opening while revealing the closed notch")

        let interrupted = HoverFixture()
        interrupted.handleHover(true)
        interrupted.coordinator.sneakPeek.show = true
        await interrupted.hoverTask?.value
        expect(interrupted.vm.notchState == .closed && !interrupted.vm.isAutoHidden, "Sneak peek appearing during dwell reveals the closed notch without opening")

        let firstLaunch = HoverFixture()
        firstLaunch.coordinator.firstLaunch = true
        firstLaunch.handleHover(true)
        firstLaunch.doOpen()
        expect(!firstLaunch.isHovering && firstLaunch.vm.isAutoHidden && firstLaunch.vm.openCalls == 0 && firstLaunch.hoverTask == nil, "First launch prevents hover and opening changes")

        for keepOpen in ["battery", "sharing", "clipboard"] {
            let protected = HoverFixture()
            protected.vm.notchState = .open
            protected.vm.isBatteryPopoverActive = keepOpen == "battery"
            SharingStateManager.shared.preventNotchClose = keepOpen == "sharing"
            protected.coordinator.currentView = keepOpen == "clipboard" ? .clipboard : .home
            protected.clipboardState.keepsNotchOpenOnHoverExit = keepOpen == "clipboard"
            protected.handleHover(true)
            protected.handleHover(false)
            await protected.hoverTask?.value
            expect(protected.vm.notchState == .open && !protected.isHovering, "Hover exit preserves the \(keepOpen) close guard")
            SharingStateManager.shared.preventNotchClose = false
        }

        guard failures.isEmpty else {
            failures.forEach { print($0) }
            exit(1)
        }
        print("Notch auto-hide production hover regressions passed")
    }

    @MainActor
    private static func expect(_ result: Bool, _ message: String) {
        if !result { failures.append(message) }
    }
}
