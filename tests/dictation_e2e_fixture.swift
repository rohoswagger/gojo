import AppKit
import Foundation

@MainActor
private final class DictationFixture: NSObject, NSApplicationDelegate {
    private let readyURL: URL
    private let textURL: URL
    private let window: NSWindow
    private let textView: NSTextView
    private var lastWrittenText: String?
    private var focusAttemptsRemaining = 1_200
    private var textPollTimer: Timer?
    private var focusTimer: Timer?
    private var terminationSource: DispatchSourceSignal?

    init(readyURL: URL, textURL: URL, notificationName _: Notification.Name) {
        self.readyURL = readyURL
        self.textURL = textURL

        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 360)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gojo Dictation Test"

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: contentRect.size))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.string = ""
        scrollView.documentView = textView
        window.contentView = scrollView

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        terminationSource = source

        textPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.persistTextIfChanged()
            }
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      (NSWorkspace.shared.frontmostApplication?.processIdentifier
                          != ProcessInfo.processInfo.processIdentifier
                          || self.window.firstResponder !== self.textView) else {
                    return
                }
                self.window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                _ = self.window.makeFirstResponder(self.textView)
            }
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView
        )

        focusFixture()
    }

    func applicationWillTerminate(_ notification: Notification) {
        textPollTimer?.invalidate()
        focusTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        persistTextIfChanged()
    }

    @objc private func textDidChange(_ notification: Notification) {
        persistTextIfChanged()
    }

    private func focusFixture() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = window.makeFirstResponder(textView)

        guard window.firstResponder === textView,
              NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier else {
            focusAttemptsRemaining -= 1
            guard focusAttemptsRemaining > 0 else {
                FileHandle.standardError.write(Data("Fixture could not focus its text view.\n".utf8))
                NSApplication.shared.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusFixture()
            }
            return
        }

        persistTextIfChanged()
        do {
            try "\(ProcessInfo.processInfo.processIdentifier)\n".write(
                to: readyURL,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            FileHandle.standardError.write(Data("Could not create fixture ready file: \(error)\n".utf8))
            NSApplication.shared.terminate(nil)
        }
    }

    private func persistTextIfChanged() {
        let text = textView.string
        guard text != lastWrittenText else { return }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            lastWrittenText = text
        } catch {
            FileHandle.standardError.write(Data("Could not write fixture text: \(error)\n".utf8))
        }
    }
}

@main
@MainActor
private struct FixtureMain {
    static func main() {
        guard CommandLine.arguments.count == 4 else {
            FileHandle.standardError.write(
                Data("Usage: dictation_e2e_fixture <ready-file> <text-file> <notification-name>\n".utf8)
            )
            exit(2)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let fixture = DictationFixture(
            readyURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            textURL: URL(fileURLWithPath: CommandLine.arguments[2]),
            notificationName: Notification.Name(CommandLine.arguments[3])
        )
        application.delegate = fixture
        application.run()
    }
}
