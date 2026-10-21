import Foundation
import SwiftUI
import AppKit
import Vision

@main
struct DictationPanelPresentationRegression {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        verifyPopoverOrdering()
        let resolved = DictationPanelModel()
        let resolvedBoard = NSPasteboard(name: .init("gojo.recovery-resolution." + UUID().uuidString))
        resolved.recoveryText = "Completed transcript"
        resolved.recoveryMessage = "No selected field"
        resolved.showsDetails = true
        expect(resolved.copyRecoveryText(to: resolvedBoard), "Completed transcript must copy")
        expect(resolvedBoard.string(forType: .string) == "Completed transcript", "Copy must write the exact transcript")
        expect(resolved.recoveryText.isEmpty && resolved.recoveryMessage == nil && !resolved.showsDetails,
               "Successful copy must consume the saved transcript and close its details")
        resolvedBoard.clearContents()
        expect(!resolved.updateRecoveryText("Completed transcript", message: "Delayed update"),
               "A delayed pre-clear update is not a resolution")
        resolved.showsDetails = true
        expect(resolved.updateRecoveryText("", message: nil), "The authoritative clear must resolve a delayed update")
        expect(resolved.recoveryText.isEmpty && !resolved.showsDetails,
               "The authoritative clear must close restored details")
        expect(!resolved.updateRecoveryText("", message: nil), "Initial empty updates must not dismiss newly opened controls")
        resolved.recoveryText = "Keep on copy failure"
        resolved.recoveryMessage = "Saved text"
        resolved.showsDetails = true
        expect(!resolved.copyRecoveryText(write: { _ in false }), "Failed clipboard writes must report failure")
        expect(resolved.recoveryText == "Keep on copy failure" && resolved.recoveryMessage == "Saved text" && resolved.showsDetails,
               "Failed copies must retain the transcript and its open details")
        expect(!resolved.clearRecoveryText(matching: "Old transcript"), "Stale discard must not clear newer text")
        expect(resolved.clearRecoveryText(matching: "Keep on copy failure"), "Discard must acknowledge the shown transcript")
        expect(resolved.recoveryText.isEmpty && resolved.recoveryMessage == nil && !resolved.showsDetails,
               "Discard must clear saved text and close its details")
        resolved.recoveryText = "Copied snapshot"
        expect(resolved.copyRecoveryText(write: { text in
            expect(text == "Copied snapshot", "Clipboard must receive the captured snapshot")
            resolved.recoveryText = "Newer transcript"
            return true
        }), "The captured clipboard write must succeed")
        expect(resolved.recoveryText == "Newer transcript", "Copy completion must preserve a newer transcript")
        let model = DictationPanelModel()
        model.present(.error(.captureFailed("Microphone unavailable")))
        let firstErrorNotice = model.attentionIdentity
        model.showsDetails = false
        model.present(.error(.captureFailed("Microphone unavailable")))
        expect(firstErrorNotice != nil && model.attentionIdentity != firstErrorNotice,
               "Repeating the same failure must present a new error notice")
        model.present(.idle)
        expect(model.attentionIdentity == nil, "Clearing an error must remove its notice")
        model.isPreview = true
        model.recoveryText = "Synthetic preview text"
        model.recoveryMessage = "Preview message"
        model.samples = Array(repeating: 1, count: 80)
        model.showsDetails = true
        model.leavePreview(recoveryText: "Actual saved phrase", recoveryMessage: "Field changed")
        expect(!model.isPreview && !model.showsDetails, "A real session must leave preview presentation")
        expect(model.recoveryText == "Actual saved phrase" && model.recoveryMessage == "Field changed",
               "A real session must replace synthetic recovery with its actual saved text")
        expect(model.samples == Array(repeating: Float.zero, count: 80), "Preview audio must not leak into a real waveform")
        model.recoveryText = ""
        model.recoveryMessage = nil
        model.activationMode = .holdToTalk
        model.state = .succeeded("Finished")
        expect(model.shouldHideWhenFinished, "Push-to-talk controls must disappear after successful insertion")
        model.state = .idle
        expect(model.shouldHideWhenFinished, "An empty or cancelled hold must also disappear")
        model.state = .listening
        expect(!model.shouldHideWhenFinished, "An active hold must remain visible")
        model.state = .error(.microphonePermissionDenied)
        expect(model.shouldHideWhenFinished, "Errors must dismiss after their message is shown")
        model.state = .succeeded("Finished")
        model.recoveryText = "Uninserted phrase"
        expect(!model.shouldHideWhenFinished, "Saved text must remain available for copying")
        model.recoveryText = ""
        model.activationMode = .voiceMode
        expect(!model.shouldHideWhenFinished, "Locked voice controls must remain visible after finishing")
        model.state = .error(.captureFailed("unavailable"))
        model.recoveryText = "Uninserted phrase"
        expect(!model.shouldHideWhenFinished, "Errors with saved text must remain available for copying")
        expect(model.recoveryText == "Uninserted phrase", "Dismissing an error must not discard saved text")
        let states: [DictationState] = [
            .idle, .requestingPermission, .listening, .pausing, .paused,
            .transcribing, .inserting, .succeeded("done"),
            .error(.accessibilityPermissionDenied), .error(.microphonePermissionDenied),
            .error(.captureFailed("unavailable"))
        ]
        for state in states {
            model.state = state
            model.recoveryText = ""
            expect(model.size == CGSize(width: 150, height: 44), "Every state without recovery must keep the compact capsule size")
            model.recoveryText = String(repeating: "Saved phrase. ", count: 100)
            expect(model.size == CGSize(width: 150, height: 44), "Saved text must keep the compact capsule size")
            expect(!model.shouldHideWhenFinished, "Saved text must prevent automatic dismissal in every state")
            let recoveryNotice = model.attentionIdentity
            expect(recoveryNotice != nil, "Saved text must open the transcript popover in every state")
            model.recoveryMessage = "A different status message"
            expect(model.attentionIdentity == recoveryNotice, "Status changes must not reopen the transcript popover")
            model.recoveryText += "New phrase."
            expect(model.attentionIdentity != recoveryNotice, "New saved text must reopen the transcript popover")
            model.recoveryText = ""
            expect(model.size == CGSize(width: 150, height: 44), "Discarding recovery must preserve the compact capsule size")
        }
        let transcript = (1...60).map { "Phrase \($0). café 日本語 🎙️" }.joined(separator: "\n")
        let pasteboard = NSPasteboard(name: .init("gojo.dictation-panel-regression." + UUID().uuidString))
        defer { pasteboard.clearContents() }
        model.recoveryText = transcript
        expect(model.copyRecoveryText(to: pasteboard), "Copy must report a successful pasteboard write")
        expect(pasteboard.string(forType: .string) == transcript, "Copy must preserve the full multiline Unicode transcript")
        expect(model.recoveryText.isEmpty, "Successful copy must clear the saved transcript")
        model.recoveryText = ""
        expect(!model.copyRecoveryText(to: pasteboard), "Copy must fail when no saved transcript exists")
        expect(pasteboard.string(forType: .string) == transcript, "An empty recovery must not erase the pasteboard")
        let copyLabel = NSHostingView(rootView: DictationPanelCopyLabel(isCopied: false)
            .font(.system(size: 11, weight: .medium)))
        let initialCopySize = copyLabel.fittingSize
        copyLabel.rootView = DictationPanelCopyLabel(isCopied: true)
            .font(.system(size: 11, weight: .medium))
        let copiedSize = copyLabel.fittingSize
        expect(initialCopySize.width > 0 && initialCopySize.height == 26,
               "Copy must reserve a real button area with a fixed height")
        expect(copiedSize == initialCopySize,
               "Copy and Copied must have identical rendered dimensions")
        let previewID = UUID()
        model.present(.listening)
        model.provisionalPreview = .init(sessionID: previewID, revision: 1, text: "First real recognition", isWindowed: false)
        let draftIdentity = model.attentionIdentity
        model.provisionalPreview = .init(sessionID: previewID, revision: 2, text: "Updated recognition", isWindowed: true)
        expect(model.attentionIdentity == draftIdentity, "Draft revisions must retain one attention identity per capture")
        expect(!model.copyRecoveryText(to: pasteboard), "A draft alone must never be copied as completed text")
        expect(pasteboard.string(forType: .string) == transcript, "Preview must leave the clipboard unchanged")
        model.recoveryText = "Older saved text"
        expect(model.attentionIdentity?.hasPrefix("recovery:") == true, "Saved text must take attention priority over draft recognition")
        model.recoveryText = ""
        model.provisionalPreview = nil
        for (reason, message) in [(DictationEmptyReason.tooShort, "Recording too short"), (.noSpeech, "No speech detected"), (.noWordsRecognized, "No words recognized")] {
            model.emptyCompletion = reason
            model.completionAttentionID = UUID()
            model.present(.idle)
            expect(model.title == message, "Typed empty completions must explain why there is no text")
            expect(model.attentionIdentity?.hasPrefix("empty:") == true, "Empty outcomes must be visible without sound feedback")
            expect(!model.shouldHideWhenFinished, "Idle must not dismiss an empty outcome before it is shown")
            expect(model.size == CGSize(width: 150, height: 44), "Empty outcomes must retain the compact capsule")
        }
        model.emptyCompletion = nil
        model.completionAttentionID = nil

        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        expect(frontmostBefore != nil && frontmostBefore != ProcessInfo.processInfo.processIdentifier,
               "Focus proof requires an external frontmost application")
        expect(!NSApp.isActive, "The draft host must begin inactive")
        let focusModel = DictationPanelModel()
        focusModel.present(.listening)
        let floating = DictationFloatingPanel(rootView: DictationPanelView(model: focusModel, command: { _ in }, dragEnded: {}))
        floating.setFrameOrigin(NSPoint(x: 60, y: 60))
        floating.orderFrontRegardless()
        focusModel.provisionalPreview = .init(sessionID: UUID(), revision: 1, text: "Recognized speech in the existing details popover", isWindowed: false)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        expect(focusModel.showsDetails, "The first draft in a capture must open details when opted in")
        expect(!floating.isKeyWindow && NSApp.keyWindow == nil, "Automatic draft details must not acquire a key window")
        expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostBefore, "Automatic draft details must preserve the frontmost application")
        expect(!NSApp.isActive, "Automatic draft details must not activate Gojo")
        print("Draft auto-open focus proof passed. External frontmost PID \(frontmostBefore!), host active=\(NSApp.isActive), key window=\(NSApp.keyWindow != nil).")
        verifyPopover(name: "draft", required: ["Draft preview", "Recognized speech"], absent: ["Copy", "Discard"])
        focusModel.showsDetails = false
        let activePreviewID = focusModel.provisionalPreview!.sessionID
        focusModel.provisionalPreview = .init(sessionID: activePreviewID, revision: 2, text: "Later recognized words", isWindowed: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        expect(!focusModel.showsDetails, "A later draft revision must not reopen manually dismissed details")
        focusModel.provisionalPreview = .init(sessionID: UUID(), revision: 1, text: "Recent recognized words", isWindowed: true)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        expect(focusModel.showsDetails, "A new capture must have its own automatic draft presentation")
        verifyPopover(name: "recent-speech", required: ["Recent speech", "Recent recognized words"], absent: ["Copy", "Discard"])
        focusModel.recoveryText = "Saved phrase has priority over draft recognition."
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        verifyPopover(name: "recovery-priority", required: ["Dictated text", "Saved phrase", "Copy", "Discard"], absent: ["Recent speech"])
        focusModel.recoveryText = ""
        focusModel.provisionalPreview = nil
        focusModel.present(.idle)
        focusModel.emptyCompletion = .noSpeech
        focusModel.completionAttentionID = UUID()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        verifyPopover(name: "no-speech", required: ["No speech detected", "Try again"], absent: ["Copy", "Discard"])
        expect(!NSApp.isActive && NSApp.keyWindow == nil, "Recovery and quiet empty feedback must also preserve target focus")
        focusModel.showsDetails = false
        floating.orderOut(nil)
        model.state = .error(.accessibilityPermissionDenied)
        expect(model.permissionSettingsURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", "Accessibility errors must open Accessibility settings")
        model.state = .error(.microphonePermissionDenied)
        expect(model.permissionSettingsURL?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone", "Microphone errors must open microphone settings")
        model.state = .error(.transcriptionFailed("unavailable"))
        expect(model.permissionSettingsURL == nil, "Model failures must not send users to unrelated permission settings")
        func waveform(_ samples: [Float], time: TimeInterval? = 0, recording: Bool = true) -> [CGFloat] {
            DictationPanelWaveformShape.heights(samples: samples, isRecording: recording, time: time, height: 26)
        }
        let quiet = waveform(Array(repeating: 0.02, count: 15))
        let loud = waveform(Array(repeating: 0.3, count: 15))
        expect(loud.count == 15, "The waveform must retain fifteen bars")
        expect(zip(loud, quiet).allSatisfy { $0 > $1 }, "Every bar must respond to speech intensity")
        let mediumSpeech = waveform(Array(repeating: 0.2, count: 15))
        let strongSpeech = waveform(Array(repeating: 0.4, count: 15))
        expect(zip(strongSpeech, mediumSpeech).allSatisfy { $0 > $1 * 1.5 }, "Speech below fifty percent must retain dynamic range")
        expect(waveform(Array(repeating: 0.5, count: 15)) == waveform(Array(repeating: 1, count: 15)), "Fifty percent microphone level must reach full visual intensity")
        expect(Set(loud).count > 10, "Speech must have jagged peaks rather than a uniform meter")
        expect(waveform([]).allSatisfy { $0 == 1.5 }, "Missing audio must stay flat")
        expect(waveform(Array(repeating: 0, count: 15)).allSatisfy { $0 == 1.5 }, "Silence must not animate")
        expect(waveform([0.8], recording: false).allSatisfy { $0 == 1.5 }, "Inactive states must stay flat")
        let nextFrame = waveform(Array(repeating: 0.3, count: 15), time: 1.0 / 30)
        expect(zip(loud, nextFrame).allSatisfy { abs($0 - $1) < 1.2 }, "The energetic ripple must keep frame changes below 1.2 points")
        let later = waveform(Array(repeating: 0.3, count: 15), time: 0.5)
        expect(zip(loud, later).contains { abs($0 - $1) > 0.5 }, "Speech must carry a visible traveling ripple")
        expect(waveform([0.3, 0.3], time: nil) == waveform(Array(repeating: 0.3, count: 15), time: nil), "Reduced motion must remove propagation and time variation")
        print("Dictation panel presentation regressions passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor
    private static var visiblePopover: NSWindow? {
        (NSWindow.windowNumbers(options: []) ?? []).lazy
            .compactMap { NSApp.window(withWindowNumber: $0.intValue) }
            .first { $0.isVisible && $0.className.contains("Popover") }
    }

    @MainActor
    private static func verifyPopoverOrdering() {
        let frame = NSRect(x: 60, y: 60, width: 320, height: 100)
        let outgoing = OrderingPopoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let incoming = OrderingPopoverPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        defer {
            outgoing.orderOut(nil)
            incoming.orderOut(nil)
        }
        for (panel, text) in [(outgoing, "Outgoing draft"), (incoming, "Current speech")] {
            panel.appearance = NSAppearance(named: .aqua)
            panel.title = text
            let label = NSTextField(labelWithString: text)
            label.drawsBackground = true
            label.font = .systemFont(ofSize: 20)
            label.frame = NSRect(x: 20, y: 35, width: 280, height: 30)
            panel.contentView?.addSubview(label)
            panel.orderFrontRegardless()
        }
        incoming.order(.above, relativeTo: outgoing.windowNumber)
        expect(outgoing.isVisible && incoming.isVisible && outgoing.frame == incoming.frame,
               "Ordering proof requires two overlapping visible native popovers")
        print("Overlap selection chose \(visiblePopover?.title ?? "none"); expected Current speech.")
        verifyPopover(name: "overlap-incoming", required: ["Current speech"], absent: ["Outgoing draft"])
        expect(visiblePopover === incoming, "The incoming frontmost popover must be selected")
        outgoing.order(.above, relativeTo: incoming.windowNumber)
        verifyPopover(name: "overlap-reordered", required: ["Outgoing draft"], absent: ["Current speech"])
        expect(visiblePopover === outgoing, "Selection must follow native order when overlapping popovers are reordered")
    }

    @MainActor
    private static func verifyPopover(name: String, required: [String], absent: [String]) {
        let orderedWindowNumbers = NSWindow.windowNumbers(options: []) ?? []
        guard let popover = visiblePopover,
              let view = popover.contentView else { fatalError("The production details popover must actually be visible for \(name)") }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Could not allocate panel render") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage, let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode panel render") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
            let rendered = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".omx/dictation-panel/render", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try data.write(to: output.appendingPathComponent(name + ".png"))
            try rendered.write(to: output.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
            let popovers = "selected=\(popover.windowNumber) ordered=\(orderedWindowNumbers)\n" + NSApp.windows.filter { $0.className.contains("Popover") }
                .map { "window=\($0.windowNumber) visible=\($0.isVisible) frame=\($0.frame)" }.joined(separator: "\n")
            try popovers.write(to: output.appendingPathComponent(name + "-windows.txt"), atomically: true, encoding: .utf8)
            for text in required { expect(rendered.localizedCaseInsensitiveContains(text), "\(name) must render \(text)") }
            let lines = rendered.components(separatedBy: .newlines)
            for text in absent { expect(!lines.contains(text), "\(name) must not render \(text)") }
        } catch { fatalError("Panel render failed: \(error)") }
    }
}

private final class OrderingPopoverPanel: NSPanel {}
