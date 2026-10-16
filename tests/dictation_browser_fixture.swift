import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct ClipboardItem: Codable, Equatable {
    let values: [String: Data]
}

struct FixtureState: Decodable {
    let href: String
    let title: String
    let fieldID: String
    let value: String
    let focused: Bool
    let visible: Bool
    let receivedAt: TimeInterval
}

func clipboardItems() -> [ClipboardItem] {
    (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var values: [String: Data] = [:]
        for type in item.types {
            guard let data = item.data(forType: type) else {
                fail("Could not snapshot an advertised clipboard format. Refusing to continue.")
            }
            values[type.rawValue] = data
        }
        return ClipboardItem(values: values)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func fixtureWindow(title: String, application: NSRunningApplication) -> AXUIElement? {
    guard AXIsProcessTrusted() else { return nil }
    let element = AXUIElementCreateApplication(application.processIdentifier)
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &raw) == .success,
          let windows = raw as? [AXUIElement] else { return nil }
    let matches = windows.filter { window in
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success
            && value as? String == title
    }
    return matches.count == 1 ? matches[0] : nil
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { exit(2) }
switch command {
case "snapshot" where arguments.count == 2:
    let data = try JSONEncoder().encode(clipboardItems())
    guard FileManager.default.createFile(
        atPath: arguments[1],
        contents: data,
        attributes: [.posixPermissions: 0o600]
    ) else {
        fail("Could not save the browser test clipboard snapshot.")
    }
case "restore" where arguments.count == 2:
    let snapshot = try JSONDecoder().decode(
        [ClipboardItem].self,
        from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    )
    if clipboardItems() != snapshot {
        let items = snapshot.map { saved in
            let item = NSPasteboardItem()
            for (type, data) in saved.values {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        NSPasteboard.general.clearContents()
        if !items.isEmpty && !NSPasteboard.general.writeObjects(items) {
            fail("Could not restore the browser test clipboard snapshot.")
        }
    }
    guard clipboardItems() == snapshot else {
        fail("The restored browser test clipboard bytes do not match the snapshot.")
    }
    print("browser-fixture clipboard-restored=true")
case "close" where arguments.count == 4:
    guard let state = try? JSONDecoder().decode(
        FixtureState.self,
        from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
    ) else { exit(0) }
    let age = Date().timeIntervalSince1970 - state.receivedAt
    guard state.href == arguments[2],
          state.title == arguments[3],
          state.fieldID == "dictation",
          state.focused,
          state.visible,
          (0..<0.5).contains(age),
          NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari",
          CGPreflightPostEventAccess(),
          let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x0D, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x0D, keyDown: false) else {
        print("browser-fixture close-skipped=true reason=fixture-not-confirmed-focused-or-event-access-unavailable")
        exit(0)
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    usleep(20_000)
    up.post(tap: .cghidEventTap)
    print("browser-fixture close-requested=true")
case "post" where arguments.count == 5:
    if let application = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == "com.apple.Safari"
    }), let window = fixtureWindow(title: arguments[3], application: application) {
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
        application.activate(options: [.activateAllWindows])
        print("browser-fixture exact-window-matched=true raise-succeeded=\(raised)")
    } else {
        print("browser-fixture exact-window-matched=false")
    }
    var lastState: FixtureState?
    for _ in 0..<100 {
        let state = try JSONDecoder().decode(
            FixtureState.self,
            from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        )
        lastState = state
        let age = Date().timeIntervalSince1970 - state.receivedAt
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier == "com.apple.Safari",
           state.href == arguments[2],
           state.title == arguments[3],
           state.fieldID == "dictation",
           state.value.isEmpty,
           state.focused,
           state.visible,
           (0..<0.5).contains(age),
           NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier {
            print("browser-fixture target-confirmed=true field=dictation initial=\"\"")
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(arguments[4]),
                object: nil,
                userInfo: ["expectedPID": NSNumber(value: application.processIdentifier)],
                deliverImmediately: true
            )
            exit(0)
        }
        usleep(50_000)
    }
    let frontmost = NSWorkspace.shared.frontmostApplication
    print("browser-fixture frontmost=\(String(reflecting: frontmost?.localizedName ?? "none")) bundle=\(frontmost?.bundleIdentifier ?? "none")")
    if let state = lastState {
        print("browser-fixture focused=\(state.focused) visible=\(state.visible) empty=\(state.value.isEmpty) age=\(Date().timeIntervalSince1970 - state.receivedAt)")
    }
    fail("The unique browser fixture is not freshly focused and empty in Safari. Refusing to type.")
default:
    exit(2)
}
