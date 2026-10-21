import AppKit
import SwiftUI

struct DictationPracticeTarget: Equatable, Sendable {
    let fieldID: UUID
    let generation: UUID
    let originalText: String
    let selectedUTF16Range: NSRange
}

enum DictationPracticeFailure: LocalizedError {
    case unavailable
    case changed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The practice field is no longer available. Your text is saved for copying."
        case .changed: return "The practice field changed while you dictated. Your text is saved for copying."
        }
    }
}

@MainActor
final class DictationPracticeRegistry {
    static let shared = DictationPracticeRegistry()

    private final class Registration {
        weak var view: NSTextView?
        var generation = UUID()
        var capturedTarget: DictationPracticeTarget?
        var expectedText: String?
        var expectedRange: NSRange?

        init(view: NSTextView) { self.view = view }
    }

    private var registrations: [UUID: Registration] = [:]

    func register(_ view: NSTextView, fieldID: UUID) {
        guard registrations[fieldID]?.view !== view else { return }
        registrations[fieldID] = Registration(view: view)
    }

    func unregister(fieldID: UUID) {
        registrations.removeValue(forKey: fieldID)
    }

    func invalidate(fieldID: UUID) {
        registrations[fieldID]?.generation = UUID()
        registrations[fieldID]?.capturedTarget = nil
        registrations[fieldID]?.expectedText = nil
        registrations[fieldID]?.expectedRange = nil
    }

    var focusedFieldID: UUID? {
        registrations.first { _, registration in
            guard let view = registration.view, isAvailable(view) else { return false }
            return NSApp.isActive && view.window?.isKeyWindow == true && view.window?.firstResponder === view
        }?.key
    }

    func capture(fieldID: UUID) throws -> DictationPracticeTarget {
        guard let registration = registrations[fieldID], let view = registration.view,
              isAvailable(view), valid(view.selectedRange(), in: view.string) else {
            throw DictationPracticeFailure.unavailable
        }
        let target = DictationPracticeTarget(
            fieldID: fieldID,
            generation: registration.generation,
            originalText: view.string,
            selectedUTF16Range: view.selectedRange()
        )
        registration.capturedTarget = target
        registration.expectedText = target.originalText
        registration.expectedRange = target.selectedUTF16Range
        return target
    }

    func insert(_ text: String, target: DictationPracticeTarget) throws -> DictationInsertionOutcome {
        guard let registration = registrations[target.fieldID],
              registration.generation == target.generation, registration.capturedTarget == target,
              let view = registration.view, isAvailable(view) else {
            throw DictationPracticeFailure.unavailable
        }
        guard let original = registration.expectedText, let range = registration.expectedRange,
              view.string == original, view.selectedRange() == range,
              valid(range, in: view.string) else {
            throw DictationPracticeFailure.changed
        }
        let expected = (original as NSString).replacingCharacters(in: range, with: text)
        view.insertText(text, replacementRange: range)
        guard view.string == expected else { return .unverified }
        registration.expectedText = expected
        registration.expectedRange = view.selectedRange()
        return .verified
    }

    private func isAvailable(_ view: NSTextView) -> Bool {
        view.isEditable && view.window?.isVisible == true && !view.isHiddenOrHasHiddenAncestor
    }

    private func valid(_ range: NSRange, in text: String) -> Bool {
        range.location != NSNotFound && range.location <= text.utf16.count
            && range.length <= text.utf16.count - range.location
    }
}

struct DictationPracticeField: NSViewRepresentable {
    let fieldID: UUID

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 7, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 100)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("Practice dictation")
        scroll.documentView = textView
        context.coordinator.fieldID = fieldID
        DictationPracticeRegistry.shared.register(textView, fieldID: fieldID)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        DictationPracticeRegistry.shared.register(textView, fieldID: fieldID)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        if let fieldID = coordinator.fieldID {
            DictationPracticeRegistry.shared.unregister(fieldID: fieldID)
        }
    }

    final class Coordinator {
        var fieldID: UUID?
    }
}
