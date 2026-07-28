import CoreGraphics
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ApplicationPasteTargetRegressionRunner {
    static func main() {
        let ownPID: pid_t = 999
        let targetPID: pid_t = 100
        let capturedWindowID = CGWindowID(42)
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let displayBounds = [
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: -1920, y: 80, width: 1920, height: 1080),
            CGRect(x: 1728, y: -220, width: 2560, height: 1440),
        ]
        let codexPID: pid_t = 200
        let bravePID: pid_t = 201
        let applicationsByPID = [
            codexPID: WindowTargetApplicationSnapshot(
                pid: codexPID,
                bundleIdentifier: "com.openai.codex",
                activationPolicy: .regular,
                isTerminated: false
            ),
            bravePID: WindowTargetApplicationSnapshot(
                pid: bravePID,
                bundleIdentifier: "com.brave.Browser",
                activationPolicy: .regular,
                isTerminated: false
            ),
        ]

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 7306,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: -1920, y: 30, width: 1920, height: 1050)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: 1165,
                        pid: bravePID,
                        ownerName: "Brave Browser",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: [],
                allowedBundleIDs: ["com.openai.codex"]
            ) == DictationApplicationPasteTarget(pid: codexPID, windowID: 7306),
            "AX-opaque capture should use the frontmost WindowServer app and exact window, not stale workspace focus"
        )

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 7000,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: -32, y: 0, width: 64, height: 32)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: 7306,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: -1920, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: [],
                allowedBundleIDs: ["com.openai.codex"]
            ) == DictationApplicationPasteTarget(pid: codexPID, windowID: 7306),
            "small utility windows should not replace the active content window"
        )

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 0,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: [],
                allowedBundleIDs: ["com.openai.codex"]
            ) == nil,
            "AX-opaque capture should reject a WindowServer target without a stable window ID"
        )

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 7306,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: ["com.openai.codex"],
                allowedBundleIDs: ["com.openai.codex"]
            ) == nil,
            "AX-opaque capture should still reject excluded applications"
        )

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 1165,
                        pid: bravePID,
                        ownerName: "Brave Browser",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: [],
                allowedBundleIDs: ["com.openai.codex"]
            ) == nil,
            "AX-opaque capture should fail closed for apps without a reviewed editor fallback"
        )

        require(
            WindowTargetResolver.topmostApplicationPasteTarget(
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 1165,
                        pid: bravePID,
                        ownerName: "Brave Browser",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: 7306,
                        pid: codexPID,
                        ownerName: "ChatGPT",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)
                    ),
                ],
                applicationsByPID: applicationsByPID,
                ownPID: ownPID,
                excludedBundleIDs: [],
                allowedBundleIDs: ["com.openai.codex"]
            ) == nil,
            "an unsupported frontmost app must not fall through to an allowed background window"
        )

        require(
            WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(
                preferredPID: codexPID,
                focusedCandidatePIDs: []
            ),
            "a valid main-process hint should be usable when the helper sees no AX focus"
        )
        require(
            WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(
                preferredPID: codexPID,
                focusedCandidatePIDs: [bravePID]
            ),
            "an authoritative Codex window hint should override stale helper focus from another app"
        )
        require(
            !WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(
                preferredPID: codexPID,
                focusedCandidatePIDs: [codexPID]
            ),
            "same-app AX focus should still be inspected for secure and editable controls"
        )
        require(
            !WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(
                preferredPID: nil,
                focusedCandidatePIDs: [bravePID]
            ),
            "missing preferred-window evidence must not override AX focus"
        )

        require(
            WindowTargetResolver.displayIndex(
                containing: CGRect(x: -1510, y: 240, width: 360, height: 44),
                displayBounds: displayBounds
            ) == 1,
            "a focused control with negative coordinates should resolve to the external display"
        )
        require(
            WindowTargetResolver.displayIndex(
                containing: CGRect(x: 1700, y: 100, width: 180, height: 80),
                displayBounds: displayBounds
            ) == 2,
            "a control spanning displays should resolve to the display containing most of it"
        )
        require(
            WindowTargetResolver.displayIndex(
                containing: CGRect(x: 6000, y: 6000, width: 200, height: 40),
                displayBounds: displayBounds
            ) == nil,
            "a focused control outside every online display should fail closed"
        )

        let multiDisplayWindows = [
            WindowTargetWindowSnapshot(
                windowID: 91,
                pid: targetPID,
                ownerName: "Codex",
                layer: 0,
                bounds: CGRect(x: 180, y: 120, width: 1200, height: 850)
            ),
            WindowTargetWindowSnapshot(
                windowID: 92,
                pid: targetPID,
                ownerName: "Codex",
                layer: 0,
                bounds: CGRect(x: -1780, y: 160, width: 1420, height: 880)
            ),
        ]
        require(
            WindowTargetResolver.windowID(
                containing: CGRect(x: -1510, y: 240, width: 360, height: 44),
                targetPID: targetPID,
                topWindows: multiDisplayWindows,
                ownPID: ownPID
            ) == 92,
            "opaque input fallback should select the same-display window containing the active cursor"
        )
        require(
            WindowTargetResolver.windowID(
                containing: CGRect(x: 5200, y: 800, width: 300, height: 40),
                targetPID: targetPID,
                topWindows: multiDisplayWindows,
                ownPID: ownPID
            ) == nil,
            "opaque input fallback should fail closed when no same-app window contains the active cursor"
        )

        require(
            WindowTargetResolver.isCapturedWindowTopmost(
                targetPID: targetPID,
                targetWindowID: capturedWindowID,
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 44,
                        pid: targetPID,
                        ownerName: "Browser",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 0, width: 800, height: 32)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: capturedWindowID,
                        pid: targetPID,
                        ownerName: "Browser",
                        layer: 0,
                        bounds: bounds
                    )
                ],
                ownPID: ownPID
            ),
            "small browser chrome windows should not displace the captured content window"
        )

        require(
            !WindowTargetResolver.isCapturedWindowTopmost(
                targetPID: targetPID,
                targetWindowID: capturedWindowID,
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: 43,
                        pid: targetPID,
                        ownerName: "Browser",
                        layer: 0,
                        bounds: bounds
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: capturedWindowID,
                        pid: targetPID,
                        ownerName: "Browser",
                        layer: 0,
                        bounds: bounds
                    )
                ],
                ownPID: ownPID
            ),
            "a sibling window from the same app must not be accepted"
        )

        require(
            !WindowTargetResolver.isCapturedWindowTopmost(
                targetPID: targetPID,
                targetWindowID: capturedWindowID,
                topWindows: [],
                ownPID: ownPID
            ),
            "a missing captured window must fail closed"
        )

        let capturedPasteTarget = DictationApplicationPasteTarget(
            pid: targetPID,
            windowID: capturedWindowID
        )
        require(
            capturedPasteTarget == DictationApplicationPasteTarget(
                pid: targetPID,
                windowID: capturedWindowID
            ),
            "browser and Electron paste identity should depend only on the captured app and window"
        )
        require(
            capturedPasteTarget != DictationApplicationPasteTarget(
                pid: targetPID,
                windowID: CGWindowID(43)
            ),
            "moving to a sibling window in the same app must fail closed"
        )
        require(
            capturedPasteTarget != DictationApplicationPasteTarget(
                pid: pid_t(101),
                windowID: capturedWindowID
            ),
            "switching applications must fail closed"
        )

        require(
            WindowTargetResolver.isCapturedWindowTopmost(
                targetPID: targetPID,
                targetWindowID: CGWindowID(84),
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: CGWindowID(84),
                        pid: targetPID,
                        ownerName: "Codex",
                        layer: 0,
                        bounds: CGRect(x: -1728, y: 64, width: 1512, height: 982)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: CGWindowID(85),
                        pid: targetPID,
                        ownerName: "Codex",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 48, width: 1512, height: 982)
                    )
                ],
                ownPID: ownPID
            ),
            "the active captured window should stay valid on a negative-origin external display"
        )

        require(
            !WindowTargetResolver.isCapturedWindowTopmost(
                targetPID: targetPID,
                targetWindowID: CGWindowID(85),
                topWindows: [
                    WindowTargetWindowSnapshot(
                        windowID: CGWindowID(84),
                        pid: targetPID,
                        ownerName: "Codex",
                        layer: 0,
                        bounds: CGRect(x: -1728, y: 64, width: 1512, height: 982)
                    ),
                    WindowTargetWindowSnapshot(
                        windowID: CGWindowID(85),
                        pid: targetPID,
                        ownerName: "Codex",
                        layer: 0,
                        bounds: CGRect(x: 0, y: 48, width: 1512, height: 982)
                    )
                ],
                ownPID: ownPID
            ),
            "a same-app window on another display must not be accepted when the external display window is topmost"
        )
    }
}
