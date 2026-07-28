import AppKit
import CoreGraphics
import Foundation

@MainActor
private final class UnicodeTextView: NSView {
    private let textURL: URL
    private var text = ""
    private var lastPersistedText: String?

    init(textURL: URL, frame: NSRect) {
        self.textURL = textURL
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 2
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let characters = event.characters, !characters.isEmpty {
            text += characters
            persistTextIfChanged()
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityIsIgnored() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityValue() -> Any? { text }

    func persistTextIfChanged() {
        guard text != lastPersistedText else { return }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            lastPersistedText = text
        } catch {
            FileHandle.standardError.write(
                Data("Could not write Unicode fixture text: \(error)\n".utf8)
            )
        }
    }
}

@MainActor
private final class UnicodeTextFixture: NSObject, NSApplicationDelegate {
    private let readyURL: URL
    private let textView: UnicodeTextView
    private let window: NSWindow
    private var focusAttemptsRemaining = 1_200
    private var focusTimer: Timer?
    private var terminationSource: DispatchSourceSignal?

    init(readyURL: URL, textURL: URL) {
        self.readyURL = readyURL
        let contentRect = NSRect(x: 0, y: 0, width: 720, height: 300)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gojo Unicode Typing Test"

        textView = UnicodeTextView(
            textURL: textURL,
            frame: NSRect(x: 24, y: 24, width: 672, height: 252)
        )

        super.init()

        let content = NSView(frame: contentRect)
        content.autoresizingMask = [.width, .height]
        textView.autoresizingMask = [.width, .height]
        content.addSubview(textView)
        window.contentView = content
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        terminationSource = source

        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.focusTextView()
            }
        }

        textView.persistTextIfChanged()
        focusTextView()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusTimer?.invalidate()
        textView.persistTextIfChanged()
    }

    private func focusTextView() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                  != ProcessInfo.processInfo.processIdentifier
                || window.firstResponder !== textView else {
            return
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = window.makeFirstResponder(textView)

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                  == ProcessInfo.processInfo.processIdentifier,
              window.firstResponder === textView else {
            focusAttemptsRemaining -= 1
            guard focusAttemptsRemaining > 0 else {
                FileHandle.standardError.write(
                    Data("Unicode fixture could not focus the text view.\n".utf8)
                )
                NSApplication.shared.terminate(nil)
                return
            }
            return
        }

        guard !FileManager.default.fileExists(atPath: readyURL.path) else {
            return
        }

        do {
            try "\(ProcessInfo.processInfo.processIdentifier)\n".write(
                to: readyURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            FileHandle.standardError.write(
                Data("Could not create Unicode fixture ready file: \(error)\n".utf8)
            )
            NSApplication.shared.terminate(nil)
        }
    }

}

@main
@MainActor
private struct UnicodeTextFixtureMain {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            FileHandle.standardError.write(
                Data("Usage: dictation_unicode_text_fixture <ready-file> <text-file>\n".utf8)
            )
            exit(2)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let fixture = UnicodeTextFixture(
            readyURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            textURL: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        application.delegate = fixture
        application.run()
    }
}
