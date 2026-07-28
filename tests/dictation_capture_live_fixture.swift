import AppKit
import CoreGraphics
import Foundation

private enum FixtureMode: String {
    case secure
    case multiDisplay = "multi-display"
}

@MainActor
private final class DictationCaptureFixture: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private let readyURL: URL
    private let textURL: URL
    private let mode: FixtureMode
    private let window: NSWindow
    private let textField: NSTextField
    private var focusAttemptsRemaining = 1_200
    private var focusTimer: Timer?
    private var textPollTimer: Timer?
    private var terminationSource: DispatchSourceSignal?
    private var lastWrittenText: String?

    init(readyURL: URL, textURL: URL, mode: FixtureMode, display: NSScreen?) {
        self.readyURL = readyURL
        self.textURL = textURL
        self.mode = mode

        let screenFrame = display?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(
            x: 0,
            y: 0,
            width: 900,
            height: 700
        )
        let contentRect = NSRect(
            x: screenFrame.midX - 220,
            y: screenFrame.midY - 60,
            width: 440,
            height: 120
        )
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = mode == .secure
            ? "Gojo Secure Dictation Capture Fixture"
            : "Gojo Multi Display Dictation Capture Fixture"

        if mode == .secure {
            textField = NSSecureTextField(frame: NSRect(x: 24, y: 42, width: 392, height: 28))
            textField.stringValue = "not changed"
        } else {
            textField = NSTextField(frame: NSRect(x: 24, y: 42, width: 392, height: 28))
            textField.stringValue = ""
        }
        textField.isEditable = true
        textField.isSelectable = true
        textField.delegate = nil

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 120))
        contentView.addSubview(textField)
        window.contentView = contentView

        super.init()
        textField.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        terminationSource = source

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controlTextDidChange(_:)),
            name: NSControl.textDidChangeNotification,
            object: textField
        )
        textPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistTextIfChanged()
            }
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.keepFocused()
            }
        }

        focusFixture()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusTimer?.invalidate()
        textPollTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        persistTextIfChanged()
    }

    @objc func controlTextDidChange(_ notification: Notification) {
        persistTextIfChanged()
    }

    private func keepFocused() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                != ProcessInfo.processInfo.processIdentifier
                || window.firstResponder !== textField.currentEditor() else {
            return
        }
        focusFixture()
    }

    private func focusFixture() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = window.makeFirstResponder(textField)

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier,
              window.firstResponder === textField.currentEditor() else {
            focusAttemptsRemaining -= 1
            guard focusAttemptsRemaining > 0 else {
                FileHandle.standardError.write(Data("Fixture could not focus its text field.\n".utf8))
                NSApplication.shared.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusFixture()
            }
            return
        }

        persistTextIfChanged()
        writeReadyFile()
    }

    private func persistTextIfChanged() {
        let text = textField.stringValue
        guard text != lastWrittenText else { return }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            lastWrittenText = text
        } catch {
            FileHandle.standardError.write(Data("Could not write fixture text: \(error)\n".utf8))
        }
    }

    private func writeReadyFile() {
        let processID = ProcessInfo.processInfo.processIdentifier
        let displayID = window.screen.flatMap(Self.displayID(for:)) ?? 0
        let payload = "pid=\(processID)\ndisplayID=\(displayID)\n"
        do {
            try payload.write(to: readyURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(Data("Could not create fixture ready file: \(error)\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@main
@MainActor
private struct FixtureMain {
    static func main() {
        guard CommandLine.arguments.count == 4,
              let mode = FixtureMode(rawValue: CommandLine.arguments[3]) else {
            FileHandle.standardError.write(
                Data("Usage: dictation_capture_live_fixture <ready-file> <text-file> <secure|multi-display>\n".utf8)
            )
            exit(2)
        }

        let targetScreen: NSScreen?
        if mode == .multiDisplay {
            let mainScreenNumber = NSScreen.main?.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
            let secondary = NSScreen.screens.first { screen in
                let screenNumber = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID
                return screenNumber != nil && screenNumber != mainScreenNumber
            }
            guard let secondary else {
                FileHandle.standardError.write(Data("No non-primary display is online.\n".utf8))
                exit(77)
            }
            targetScreen = secondary
        } else {
            targetScreen = NSScreen.main
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let fixture = DictationCaptureFixture(
            readyURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            textURL: URL(fileURLWithPath: CommandLine.arguments[2]),
            mode: mode,
            display: targetScreen
        )
        application.delegate = fixture
        application.run()
    }
}
