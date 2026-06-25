import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message) — expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

@main
struct AltTabRegressionRunner {
    static func main() {
        // Initial selection: with 2+ windows, preselect index 1 (the window
        // behind the frontmost one) so a quick trigger-and-release switches to
        // the previous window. With 0 or 1 windows, select index 0.
        assertEqual(AltTabSelection.initialIndex(count: 0), 0, "empty list selects index 0")
        assertEqual(AltTabSelection.initialIndex(count: 1), 0, "single window selects index 0")
        assertEqual(AltTabSelection.initialIndex(count: 2), 1, "two windows preselect the second")
        assertEqual(AltTabSelection.initialIndex(count: 5), 1, "many windows preselect the second")

        // Forward cycling wraps around.
        assertEqual(AltTabSelection.advance(from: 1, count: 3, reverse: false), 2, "forward advances by one")
        assertEqual(AltTabSelection.advance(from: 2, count: 3, reverse: false), 0, "forward wraps past the end")

        // Reverse cycling wraps around.
        assertEqual(AltTabSelection.advance(from: 0, count: 3, reverse: true), 2, "reverse wraps before the start")
        assertEqual(AltTabSelection.advance(from: 1, count: 3, reverse: true), 0, "reverse decrements by one")

        // Out-of-range input indices normalize back into bounds (the index can
        // drift if the window list shrinks between trigger and advance).
        assertEqual(AltTabSelection.advance(from: -1, count: 3, reverse: false), 0, "negative index normalizes into range")
        assertEqual(AltTabSelection.advance(from: 10, count: 3, reverse: false), 2, "oversized index wraps into range")

        // Degenerate counts stay in bounds.
        assertEqual(AltTabSelection.advance(from: 0, count: 0, reverse: false), 0, "empty list stays at 0")
        assertEqual(AltTabSelection.advance(from: 0, count: 1, reverse: false), 0, "single window wraps to itself forward")
        assertEqual(AltTabSelection.advance(from: 0, count: 1, reverse: true), 0, "single window wraps to itself reverse")

        print("alt-tab-regression-pass")
    }
}
