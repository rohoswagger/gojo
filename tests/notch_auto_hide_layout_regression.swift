import AppKit
import SwiftUI

@main
struct NotchAutoHideLayoutRegression {
    @MainActor private static var failures: [String] = []

    @MainActor
    static func main() {
        let host = NSHostingView(rootView: notchHoverLayout(isAutoHidden: false, closedNotchHeight: 0))
        let cases: [(height: CGFloat, targetHeight: CGFloat)] = [(0, 10), (1, 10), (5, 10), (9, 10), (32, 32)]
        for testCase in cases {
            for isAutoHidden in [true, false, true] {
                host.rootView = notchHoverLayout(isAutoHidden: isAutoHidden, closedNotchHeight: testCase.height)
                expect(host.fittingSize, CGSize(width: 185, height: testCase.targetHeight), "Closed height \(testCase.height), auto-hidden \(isAutoHidden) preserves its hover target")
            }
        }
        host.rootView = notchHoverLayout(isAutoHidden: false, closedNotchHeight: 5, contentHeight: 84)
        expect(host.fittingSize, CGSize(width: 185, height: 84), "A revealed HUD keeps its natural height")
        host.rootView = notchHoverLayout(isAutoHidden: false, closedNotchHeight: 5, contentHeight: 84, isOpen: true)
        expect(host.fittingSize, CGSize(width: 185, height: 300), "An open panel keeps its requested height")
        guard failures.isEmpty else {
            failures.forEach { print($0) }
            exit(1)
        }
        print("Notch auto-hide hosted layout regressions passed")
    }

    @MainActor
    static func expect(_ actual: CGSize, _ expected: CGSize, _ message: String) {
        if actual != expected { failures.append("\(message). Expected \(expected), got \(actual)") }
    }
}
