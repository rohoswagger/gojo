import AppKit
import CoreGraphics
import Darwin
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }
let owner = CommandLine.arguments[1]
guard let application = NSWorkspace.shared.runningApplications.first(where: {
    $0.localizedName == owner
}) else {
    exit(4)
}
application.activate(options: [.activateAllWindows])
usleep(300_000)

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let ownerWindows = windows.compactMap { window -> (window: [String: Any], area: Double)? in
    guard (window[kCGWindowOwnerName as String] as? String) == owner,
          ((window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = (bounds["Width"] as? NSNumber)?.doubleValue,
          let height = (bounds["Height"] as? NSNumber)?.doubleValue,
          width >= 200,
          height >= 150 else {
        return nil
    }
    return (window, width * height)
}

guard let window = ownerWindows.max(by: { $0.area < $1.area })?.window,
    let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
    let x = (rawBounds["X"] as? NSNumber)?.doubleValue,
    let y = (rawBounds["Y"] as? NSNumber)?.doubleValue,
    let width = (rawBounds["Width"] as? NSNumber)?.doubleValue,
    let height = (rawBounds["Height"] as? NSNumber)?.doubleValue else {
    exit(3)
}

let point = owner == "Safari" || owner == "Brave Browser"
    ? CGPoint(x: x + min(350, width / 2), y: y + min(180, height / 2))
    : CGPoint(x: x + width / 2, y: y + height / 2)
let down = CGEvent(
    mouseEventSource: nil,
    mouseType: .leftMouseDown,
    mouseCursorPosition: point,
    mouseButton: .left
)!
let up = CGEvent(
    mouseEventSource: nil,
    mouseType: .leftMouseUp,
    mouseCursorPosition: point,
    mouseButton: .left
)!
down.post(tap: .cghidEventTap)
usleep(100_000)
up.post(tap: .cghidEventTap)
