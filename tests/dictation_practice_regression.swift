import AppKit
import SwiftUI

@main
struct DictationPracticeRegression {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let registry = DictationPracticeRegistry()
        let fieldID = UUID()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 180))
        let field = NSTextView(frame: scroll.bounds)
        field.isRichText = false
        field.isEditable = true
        scroll.documentView = field
        window.contentView = scroll
        window.orderFront(nil)
        registry.register(field, fieldID: fieldID)
        window.makeFirstResponder(field)
        expect(registry.focusedFieldID == nil, "A background practice window must not intercept the shortcut intended for another app")
        field.string = "Hello café 🎙️ world"
        let replacement = (field.string as NSString).range(of: "café 🎙️")
        field.setSelectedRange(replacement)
        let target = try registry.capture(fieldID: fieldID)
        expect(target.originalText == "Hello café 🎙️ world" && target.selectedUTF16Range == replacement,
               "Capture must use the real native text and UTF-16 selection")
        expect(try registry.insert("日本語\nSecond paragraph", target: target) == .verified,
               "Native NSTextView insertion must be read back and verified")
        expect(field.string == "Hello 日本語\nSecond paragraph world", "Native replacement must preserve Unicode and paragraphs")
        expect(try registry.insert(" again", target: target) == .verified,
               "A continuous practice target must advance after verified insertion")
        expect(field.string == "Hello 日本語\nSecond paragraph again world", "The next phrase must use the native caret after insertion")

        let selectionTarget = try registry.capture(fieldID: fieldID)
        field.setSelectedRange(NSRange(location: 0, length: 0))
        expectThrows("Moving the caret must reject the captured target") { try registry.insert("unsafe", target: selectionTarget) }
        expect(!field.string.contains("unsafe"), "A selection mismatch must not modify the field")
        let editTarget = try registry.capture(fieldID: fieldID)
        field.string += "Manual edit"
        expectThrows("Manual edits must reject the captured target") { try registry.insert("unsafe", target: editTarget) }
        let staleTarget = try registry.capture(fieldID: fieldID)
        registry.invalidate(fieldID: fieldID)
        expectThrows("Invalidation must reject old registration generations") { try registry.insert("unsafe", target: staleTarget) }
        let closedTarget = try registry.capture(fieldID: fieldID)
        window.close()
        expectThrows("A closed retained window must reject insertion") { try registry.insert("unsafe", target: closedTarget) }
        expectThrows("A hidden retained window must not capture a new target") { try registry.capture(fieldID: fieldID) }
        window.orderFront(nil)
        let reopenedTarget = try registry.capture(fieldID: fieldID)
        expect(try registry.insert("Reopened", target: reopenedTarget) == .verified, "The retained field must work after reopening with a new capture")
        field.isEditable = false
        expectThrows("A noneditable practice field must not capture") { try registry.capture(fieldID: fieldID) }
        field.isEditable = true
        let replacedTarget = try registry.capture(fieldID: fieldID)
        let otherField = NSTextView(frame: scroll.bounds)
        registry.register(otherField, fieldID: fieldID)
        expectThrows("Replacing a registered view must reject old tokens") { try registry.insert("unsafe", target: replacedTarget) }
        registry.unregister(fieldID: fieldID)
        expectThrows("Unregistering must reject capture") { try registry.capture(fieldID: fieldID) }

        let productionFieldID = UUID()
        var closeCount = 0
        let host = NSHostingView(rootView: DictationPracticeField(fieldID: productionFieldID)
            .frame(width: 400, height: 100)
            .modifier(SettingsWindowCloseObserver(window: window) {
                closeCount += 1
                DictationPracticeRegistry.shared.invalidate(fieldID: productionFieldID)
            }))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        guard let productionField = firstTextView(in: host) else { fatalError("The production representable must create a real NSTextView") }
        expect(productionField.frame.width > 300 && productionField.frame.height > 80,
               "The production field must provide a real visible text entry area")
        let productionTarget = try DictationPracticeRegistry.shared.capture(fieldID: productionFieldID)
        expect(try DictationPracticeRegistry.shared.insert("Native practice field", target: productionTarget) == .verified,
               "The production representable must register its real field for verified insertion")
        expect(productionField.string == "Native practice field", "The production field must display the inserted text")
        let beforeClose = try DictationPracticeRegistry.shared.capture(fieldID: productionFieldID)
        window.close()
        expect(closeCount == 1, "The production Settings close observer must run for the retained window")
        window.orderFront(nil)
        expect(window.contentView === host, "Reopening must reuse the retained host for this regression")
        expectThrows("Closing and reopening the retained host must invalidate its original practice token") {
            try DictationPracticeRegistry.shared.insert("stale", target: beforeClose)
        }
        let afterReopen = try DictationPracticeRegistry.shared.capture(fieldID: productionFieldID)
        expect(try DictationPracticeRegistry.shared.insert(" after reopen", target: afterReopen) == .verified,
               "The retained production field must allow a fresh capture after closing")
        DictationPracticeRegistry.shared.unregister(fieldID: productionFieldID)
        window.orderOut(nil)
        print("Native dictation practice insertion, continuation, stale selection, edit, generation, and retained-window regressions passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    private static func expectThrows<T>(_ message: String, _ operation: () throws -> T) {
        do { _ = try operation(); fatalError(message) } catch {}
    }

    @MainActor
    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let field = view as? NSTextView { return field }
        return view.subviews.lazy.compactMap { firstTextView(in: $0) }.first
    }
}
