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

        // Pointer selection only accepts cards that still exist in the active
        // session. This prevents stale hover events from changing selection as
        // the switcher closes or its contents change.
        assertEqual(AltTabSelection.pointerIndex(2, count: 4), 2, "pointer selects an in-range card")
        assertEqual(AltTabSelection.pointerIndex(-1, count: 4), nil, "pointer rejects a negative index")
        assertEqual(AltTabSelection.pointerIndex(4, count: 4), nil, "pointer rejects an index past the end")
        assertEqual(AltTabSelection.pointerIndex(0, count: 0), nil, "pointer rejects selection in an empty list")

        // Hover must not steal the keyboard's initial selection just because the
        // switcher opened underneath a resting cursor.
        assertEqual(
            AltTabSelection.pointerHoverIsIntentional(
                origin: CGPoint(x: 400, y: 300),
                current: CGPoint(x: 400, y: 300)
            ),
            false,
            "a stationary cursor never takes over the selection"
        )
        assertEqual(
            AltTabSelection.pointerHoverIsIntentional(
                origin: CGPoint(x: 400, y: 300),
                current: CGPoint(x: 401, y: 301)
            ),
            false,
            "sub-tolerance jitter never takes over the selection"
        )
        assertEqual(
            AltTabSelection.pointerHoverIsIntentional(
                origin: CGPoint(x: 400, y: 300),
                current: CGPoint(x: 440, y: 300)
            ),
            true,
            "a horizontal pointer move arms hover selection"
        )
        assertEqual(
            AltTabSelection.pointerHoverIsIntentional(
                origin: CGPoint(x: 400, y: 300),
                current: CGPoint(x: 400, y: 260)
            ),
            true,
            "a vertical pointer move arms hover selection"
        )
        assertEqual(
            AltTabSelection.pointerHoverIsIntentional(
                origin: nil,
                current: CGPoint(x: 400, y: 300)
            ),
            true,
            "hover works when no pointer origin was recorded"
        )

        assertEqual(
            WindowTargetResolver.windowActivationTarget(
                requestedWindowID: 42,
                exactMatch: "requested",
                fallback: "sibling"
            ),
            "requested",
            "an exact activation match selects the requested window"
        )
        assertEqual(
            WindowTargetResolver.windowActivationTarget(
                requestedWindowID: 42,
                exactMatch: Optional<String>.none,
                fallback: "sibling"
            ),
            nil,
            "a missing exact activation match never substitutes a sibling window"
        )
        assertEqual(
            WindowTargetResolver.windowActivationTarget(
                requestedWindowID: nil,
                exactMatch: Optional<String>.none,
                fallback: "focused"
            ),
            "focused",
            "activation without a window ID may use the app fallback"
        )
        var evaluatedSiblingFallback = false
        let unresolvedExactTarget = WindowTargetResolver.windowActivationTarget(
            requestedWindowID: 42,
            exactMatch: Optional<String>.none,
            fallback: {
                evaluatedSiblingFallback = true
                return "sibling"
            }()
        )
        assertEqual(unresolvedExactTarget, nil, "an unresolved exact target stays unresolved")
        assertEqual(evaluatedSiblingFallback, false, "an exact request never searches the sibling fallback")

        var recency = AltTabRecency()
        assertEqual(
            recency.order(freshIDs: ["brave-a", "mail", "brave-b"]),
            ["brave-a", "mail", "brave-b"],
            "first capture preserves fresh order"
        )
        assertEqual(
            recency.order(freshIDs: ["brave-a", "brave-a", "mail", "mail", "brave-b"]),
            ["brave-a", "mail", "brave-b"],
            "duplicate fresh IDs are removed"
        )

        recency.promote("brave-b")
        assertEqual(
            recency.order(freshIDs: ["brave-b", "brave-a", "mail"]),
            ["brave-b", "brave-a", "mail"],
            "promoting one Brave window changes only that window's MRU position"
        )

        recency = AltTabRecency()
        _ = recency.order(freshIDs: ["brave-a", "mail", "brave-b"])
        recency.promote("mail")
        assertEqual(
            recency.order(freshIDs: ["brave-a", "brave-b", "mail"]),
            ["brave-a", "mail", "brave-b"],
            "fresh macOS grouping keeps prior non-Brave use between Brave siblings"
        )

        assertEqual(
            recency.order(freshIDs: ["brave-a", "brave-b", "notes"]),
            ["brave-a", "brave-b", "notes"],
            "closed IDs are pruned and new IDs are appended"
        )
        assertEqual(
            recency.order(freshIDs: []),
            [],
            "empty input clears history"
        )

        let ownPID: pid_t = 999
        let browserPID: pid_t = 100
        let finderPID: pid_t = 300
        let displayBounds = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: -147, width: 1920, height: 1080),
            CGRect(x: 3648, y: -147, width: 1920, height: 1080)
        ]
        let browserWindows = [
            WindowTargetWindowSnapshot(
                pid: browserPID,
                ownerName: "Safari",
                layer: 0,
                bounds: CGRect(x: 3800, y: 20, width: 1200, height: 900)
            ),
            WindowTargetWindowSnapshot(
                pid: finderPID,
                ownerName: "Finder",
                layer: 0,
                bounds: CGRect(x: 1900, y: 0, width: 1200, height: 900)
            ),
            WindowTargetWindowSnapshot(
                pid: browserPID,
                ownerName: "Safari",
                layer: 0,
                bounds: CGRect(x: 100, y: 80, width: 1200, height: 900)
            )
        ]
        assertEqual(
            WindowTargetResolver.displayIndex(
                forTopWindowOwnedBy: browserPID,
                topWindows: browserWindows,
                displayBounds: displayBounds,
                ownPID: ownPID
            ),
            2,
            "the focused app's topmost window chooses the active display"
        )
        assertEqual(
            WindowTargetResolver.displayIndex(
                forTopWindowOwnedBy: finderPID,
                topWindows: browserWindows,
                displayBounds: displayBounds,
                ownPID: ownPID
            ),
            1,
            "another app's topmost window resolves its own display"
        )
        assertEqual(
            WindowTargetResolver.displayIndex(
                forTopWindowOwnedBy: ownPID,
                topWindows: browserWindows,
                displayBounds: displayBounds,
                ownPID: ownPID
            ),
            nil,
            "the switcher's own windows cannot select an active display"
        )

        let spanningWindow = WindowTargetWindowSnapshot(
            pid: browserPID,
            ownerName: "Safari",
            layer: 0,
            bounds: CGRect(x: 1500, y: 100, width: 900, height: 700)
        )
        assertEqual(
            WindowTargetResolver.displayIndex(
                forTopWindowOwnedBy: browserPID,
                topWindows: [spanningWindow],
                displayBounds: displayBounds,
                ownPID: ownPID
            ),
            1,
            "a spanning window belongs to the display containing most of it"
        )

        print("alt-tab-regression-pass")
    }
}
