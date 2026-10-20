import AppKit
import ApplicationServices
@_silgen_name("_AXUIElementGetWindow")
func axWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
@main struct Probe {
    @MainActor static func main() async throws {
        guard AXIsProcessTrusted() else { print("SKIP Accessibility required for live focus comparison"); exit(77) }
        guard NSScreen.screens.count > 1 else { print("SKIP fewer than two displays"); exit(77) }
        let provider = FocusedWindowProvider()
        let focused = try await provider.focusedWindow()
        print("resolved pid=\(focused.pid) windowID=\(focused.windowID ?? 0) display=\(focused.screen.directDisplayID ?? 0)")
        let app=AXUIElementCreateApplication(focused.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let value else { fatalError("AX focus unavailable") }
        var expected: CGWindowID=0
        guard axWindowID(value as! AXUIElement, &expected) == .success else { fatalError("AX window ID unavailable") }
        guard focused.windowID == expected else { fatalError("CG targeting differs from actual AX focused window, expected \(expected)") }
        guard provider.activeScreen()?.directDisplayID == focused.screen.directDisplayID else { fatalError("Active display differs from focused display") }
        guard provider.enumerateWindows(on: focused.screen).contains(where: { $0.windowID == expected }) else { fatalError("Focused external window missing from enumeration") }
        for screen in NSScreen.screens {
            let windows = provider.enumerateWindows(on: screen)
            guard windows.allSatisfy({ NSScreen.screen(containing: $0.normalFrame)?.directDisplayID == screen.directDisplayID }) else { fatalError("Cross-display candidate") }
            print("display=\(screen.directDisplayID ?? 0) windowCount=\(windows.count)")
        }
        print("window-display-live-probe: PASS")
    }
}
