import AppKit

@main
struct WindowHistoryRegression {
    @MainActor
    static func main() {
        guard let screen = NSScreen.screens.first else {
            fatalError("A display is required for the focused-window history regression")
        }
        func window(_ id: CGWindowID, frame: CGRect) -> FocusedWindow {
            FocusedWindow(
                element: nil, windowID: id, pid: 123, appName: "Regression",
                bundleIdentifier: nil, title: "History", axFrame: frame,
                normalFrame: frame, screen: screen
            )
        }
        let originalFrame = CGRect(x: 80, y: 100, width: 640, height: 480)
        let original = window(10, frame: originalFrame)
        let moved = window(10, frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        let other = window(20, frame: CGRect(x: 200, y: 220, width: 300, height: 400))
        let history = WindowHistoryStore()

        precondition(history.entry(for: original) == nil)
        history.ensureRestoreFrame(for: original, action: .leftHalf)
        precondition(history.entry(for: original)?.restoreFrame == originalFrame)
        precondition(history.entry(for: original)?.lastAction == .leftHalf)

        history.ensureRestoreFrame(for: moved, action: .maximize)
        precondition(history.entry(for: moved)?.restoreFrame == originalFrame)
        precondition(history.entry(for: moved)?.lastAction == .maximize)
        history.ensureRestoreFrame(for: moved, action: .rightHalf)
        precondition(history.entry(for: original)?.restoreFrame == originalFrame)
        precondition(history.entry(for: original)?.lastAction == .rightHalf)

        history.ensureRestoreFrame(for: other, action: .bottomHalf)
        precondition(history.entry(for: other)?.restoreFrame == other.normalFrame)
        precondition(history.entry(for: other)?.lastAction == .bottomHalf)
        precondition(history.entry(for: original)?.restoreFrame == originalFrame)

        history.clear(for: original)
        precondition(history.entry(for: moved) == nil)
        precondition(history.entry(for: other)?.lastAction == .bottomHalf)
        history.clear(for: original)
        history.ensureRestoreFrame(for: moved, action: .topHalf)
        precondition(history.entry(for: moved)?.restoreFrame == moved.normalFrame)
        precondition(history.entry(for: moved)?.lastAction == .topHalf)
        print("window_history_regression: ok")
    }
}
