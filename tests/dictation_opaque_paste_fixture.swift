import AppKit
import Foundation

@MainActor
private final class OpaquePasteField: NSTextField {
    let fieldName: String
    let textURL: URL

    private var text = ""
    private var lastPersistedText: String?

    init(fieldName: String, textURL: URL, frame: NSRect) {
        self.fieldName = fieldName
        self.textURL = textURL
        super.init(frame: frame)
        stringValue = fieldName
        isEditable = false
        isSelectable = false
        isBordered = true
        drawsBackground = true
        backgroundColor = .windowBackgroundColor
        focusRingType = .exterior
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        layer?.borderWidth = 3
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderWidth = 1
        return true
    }

    @objc func paste(_ sender: Any?) {
        if let value = NSPasteboard.general.string(forType: .string) {
            FileHandle.standardError.write(
                Data("paste field=\(fieldName) bytes=\(value.utf8.count)\n".utf8)
            )
            text += value
            persistTextIfChanged()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func accessibilityIsIgnored() -> Bool { false }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { fieldName }
    override func accessibilityValue() -> String? { text }

    override func setAccessibilityValue(_ value: Any?) {
        guard let value = value as? String else { return }
        text = value
        persistTextIfChanged()
    }

    func persistTextIfChanged() {
        guard text != lastPersistedText else { return }
        do {
            try text.write(to: textURL, atomically: true, encoding: .utf8)
            lastPersistedText = text
            stringValue = text.isEmpty ? fieldName : text
        } catch {
            FileHandle.standardError.write(
                Data("Could not write \(fieldName) text: \(error)\n".utf8)
            )
        }
    }
}

@MainActor
private final class OpaquePasteFixture: NSObject, NSApplicationDelegate {
    private let readyURL: URL
    private let firstTextURL: URL
    private let secondTextURL: URL
    private let window: NSWindow
    private let alternateWindow: NSWindow
    private let firstField: OpaquePasteField
    private let secondField: OpaquePasteField
    private let alternateField: OpaquePasteField
    private var focusAttemptsRemaining = 1_200
    private var focusTimer: Timer?
    private var focusMoveObserver: Any?
    private var terminationSource: DispatchSourceSignal?
    private let focusMoveTarget: String
    private var desiredField: OpaquePasteField?

    init(
        readyURL: URL,
        firstTextURL: URL,
        secondTextURL: URL,
        probeNotificationName _: Notification.Name,
        focusMoveTarget: String
    ) {
        self.readyURL = readyURL
        self.firstTextURL = firstTextURL
        self.secondTextURL = secondTextURL
        self.focusMoveTarget = focusMoveTarget
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 360)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Gojo Opaque Paste Test"
        alternateWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        alternateWindow.title = "Gojo Opaque Paste Other Window"

        firstField = OpaquePasteField(
            fieldName: "Opaque field one",
            textURL: firstTextURL,
            frame: NSRect(x: 40, y: 190, width: 600, height: 82)
        )
        secondField = OpaquePasteField(
            fieldName: "Opaque field two",
            textURL: secondTextURL,
            frame: NSRect(x: 40, y: 70, width: 600, height: 82)
        )
        alternateField = OpaquePasteField(
            fieldName: "Opaque other-window field",
            textURL: secondTextURL,
            frame: NSRect(x: 40, y: 70, width: 440, height: 82)
        )

        super.init()

        let content = NSView(frame: contentRect)
        content.autoresizingMask = [.width, .height]
        content.addSubview(firstField)
        content.addSubview(secondField)
        window.contentView = content

        let alternateContent = NSView(frame: alternateWindow.contentRect(forFrameRect: alternateWindow.frame))
        alternateContent.autoresizingMask = [.width, .height]
        alternateContent.addSubview(alternateField)
        alternateWindow.contentView = alternateContent
        desiredField = firstField
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            NSApplication.shared.terminate(nil)
        }
        source.resume()
        terminationSource = source

        focusMoveObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("rohoswagger.gojo.dictation-opaque-paste-fixture-focus-next"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.focusSecondField()
            }
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let desiredField = self.desiredField else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                          != ProcessInfo.processInfo.processIdentifier
                        || desiredField.window?.firstResponder !== desiredField else {
                    return
                }
                self.focusDesiredField()
            }
        }

        firstField.persistTextIfChanged()
        secondField.persistTextIfChanged()
        focusFirstField()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let focusMoveObserver {
            DistributedNotificationCenter.default().removeObserver(focusMoveObserver)
        }
        focusTimer?.invalidate()
        firstField.persistTextIfChanged()
        secondField.persistTextIfChanged()
    }

    private func focusFirstField() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = window.makeFirstResponder(firstField)

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                  == ProcessInfo.processInfo.processIdentifier,
              window.firstResponder === firstField else {
            focusAttemptsRemaining -= 1
            guard focusAttemptsRemaining > 0 else {
                FileHandle.standardError.write(
                    Data("Opaque fixture could not focus the first field.\n".utf8)
                )
                NSApplication.shared.terminate(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.focusFirstField()
            }
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
                Data("Could not create opaque fixture ready file: \(error)\n".utf8)
            )
            NSApplication.shared.terminate(nil)
        }
    }

    private func focusSecondField() {
        desiredField = focusMoveTarget == "window-switch" ? alternateField : secondField
        FileHandle.standardError.write(
            Data("focus move target=\(focusMoveTarget)\n".utf8)
        )
        focusDesiredField()
    }

    private func focusDesiredField() {
        guard let desiredField,
              let targetWindow = desiredField.window else {
            return
        }
        if targetWindow === alternateWindow {
            window.orderBack(nil)
            alternateWindow.center()
        }
        targetWindow.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = targetWindow.makeFirstResponder(desiredField)
    }
}

@main
@MainActor
private struct OpaquePasteFixtureMain {
    static func main() {
        guard CommandLine.arguments.count == 6 else {
            FileHandle.standardError.write(
                Data("Usage: dictation_opaque_paste_fixture <ready-file> <first-text-file> <second-text-file> <probe-notification> <focus-move-target>\n".utf8)
            )
            exit(2)
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let fixture = OpaquePasteFixture(
            readyURL: URL(fileURLWithPath: CommandLine.arguments[1]),
            firstTextURL: URL(fileURLWithPath: CommandLine.arguments[2]),
            secondTextURL: URL(fileURLWithPath: CommandLine.arguments[3]),
            probeNotificationName: Notification.Name(CommandLine.arguments[4]),
            focusMoveTarget: CommandLine.arguments[5]
        )
        application.delegate = fixture
        application.run()
    }
}
