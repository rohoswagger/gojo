import Foundation
import SwiftUI
import AppKit

@main
struct DictationPanelPresentationRegression {
    @MainActor
    static func main() {
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
        expect(model.recoveryText == transcript, "Copy must keep the saved transcript available")
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
}
