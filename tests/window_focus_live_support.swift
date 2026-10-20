import Foundation
import AppKit

struct WindowSummary: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let windowID: CGWindowID?
    let appName: String
    let bundleIdentifier: String?
    let icon: NSImage?
    let title: String?
    let normalFrame: CGRect
    let currentAction: WindowAction?

    static func == (lhs: WindowSummary, rhs: WindowSummary) -> Bool {
        lhs.id == rhs.id
            && lhs.pid == rhs.pid
            && lhs.windowID == rhs.windowID
            && lhs.appName == rhs.appName
            && lhs.title == rhs.title
            && lhs.normalFrame.equalTo(rhs.normalFrame)
            && lhs.currentAction == rhs.currentAction
    }
}


struct WindowFrameResult { let success: Bool }
final class XPCHelperClient {
    static let shared = XPCHelperClient()
    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool { AXIsProcessTrusted() }
    private let probeHelper = ProbeHelper()
    func focusedWindow(forPID pid: pid_t) async -> WindowTargetWindowSnapshot? {
        await withCheckedContinuation { continuation in
            probeHelper.focusedWindowSnapshot(forPID: NSNumber(value: pid)) { result in
                guard let windowID = WindowTargetResolver.cgWindowIDValue(result["windowID"]),
                      let bounds = WindowTargetResolver.rectValue(result["axFrame"]) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: WindowTargetWindowSnapshot(windowID: windowID, pid: pid, ownerName: nil, layer: 0, bounds: bounds))
            }
        }
    }
    func setWindowFrame(_ frame: CGRect, pid: pid_t, windowID: CGWindowID?) async -> WindowFrameResult { fatalError("Read-only probe") }
}
func gojoDebug(_ message: String) {}

@_silgen_name("_AXUIElementGetWindow")
func probeGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
final class ProbeHelper: NSObject {
    func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    func windowID(of element: AXUIElement) -> CGWindowID? {
        var result: CGWindowID = 0
        return probeGetWindow(element, &result) == .success ? result : nil
    }
    func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    func isUsableWindow(_ element: AXUIElement) -> Bool {
        guard let frame = frame(of: element) else { return false }
        return frame.width > 0 && frame.height > 0
    }
}
