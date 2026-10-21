import AppKit
import SwiftUI

@MainActor
final class DictationPanelModel: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var samples = Array(repeating: Float.zero, count: 80)
    @Published var targetApplicationName: String?
    @Published var recoveryText = ""
    @Published var recoveryMessage: String?
    @Published var activationMode = DictationActivationMode.saved()
    @Published var isPreview = false
    @Published var showsDetails = false
    @Published var provisionalPreview: DictationProvisionalPreview?
    @Published var activeIntent: DictationSessionIntent?
    @Published var automaticallyOpensDraft = true
    @Published var emptyCompletion: DictationEmptyReason?
    @Published var completionAttentionID: UUID?
    @Published private(set) var errorPresentationID = UUID()

    func present(_ state: DictationState) {
        self.state = state
        if case .error = state { errorPresentationID = UUID() }
    }

    var attentionIdentity: String? {
        if !recoveryText.isEmpty { return "recovery:" + recoveryText }
        if case .error = state { return errorPresentationID.uuidString }
        if emptyCompletion != nil, let id = completionAttentionID { return "empty:" + id.uuidString }
        if let preview = provisionalPreview { return "draft:" + preview.sessionID.uuidString }
        return nil
    }

    func leavePreview(recoveryText: String, recoveryMessage: String?) {
        isPreview = false
        self.recoveryText = recoveryText
        self.recoveryMessage = recoveryMessage
        showsDetails = false
        provisionalPreview = nil
        clearWaveform()
    }

    var isHandsFree: Bool { activationMode == .voiceMode }

    var shouldHideWhenFinished: Bool {
        guard recoveryText.isEmpty, emptyCompletion == nil else { return false }
        if case .error = state { return true }
        guard !isHandsFree else { return false }
        switch state {
        case .idle, .succeeded: return true
        default: return false
        }
    }

    var title: String {
        if let emptyCompletionMessage { return emptyCompletionMessage }
        switch state {
        case .idle: return "Ready to dictate"
        case .requestingPermission: return "Getting ready"
        case .listening: return "Recording"
        case .pausing: return "Finishing phrase"
        case .paused: return "Paused"
        case .transcribing: return "Transcribing"
        case .inserting: return "Adding text"
        case .succeeded: return "Done"
        case .error: return "Could not dictate"
        }
    }

    var isProcessing: Bool {
        switch state {
        case .requestingPermission, .pausing, .transcribing, .inserting: return true
        default: return false
        }
    }

    var errorMessage: String? {
        guard case .error(let failure) = state else { return nil }
        return failure.localizedDescription
    }

    var emptyCompletionMessage: String? {
        switch emptyCompletion {
        case .tooShort: return "Recording too short"
        case .noSpeech: return "No speech detected"
        case .noWordsRecognized: return "No words recognized"
        case nil: return nil
        }
    }

    var size: CGSize {
        DictationPanelPlacement.defaultSize
    }

    func copyRecoveryText(to pasteboard: NSPasteboard = .general) -> Bool {
        copyRecoveryText { text in
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    func copyRecoveryText(write: (String) -> Bool) -> Bool {
        let text = recoveryText
        guard !text.isEmpty, write(text) else { return false }
        clearRecoveryText(matching: text)
        return true
    }

    @discardableResult
    func clearRecoveryText(matching text: String) -> Bool {
        guard !text.isEmpty, recoveryText == text else { return false }
        recoveryText = ""
        recoveryMessage = nil
        showsDetails = false
        return true
    }

    var permissionSettingsURL: URL? {
        switch state {
        case .error(.accessibilityPermissionDenied):
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .error(.microphonePermissionDenied):
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        default:
            return nil
        }
    }

    func appendAudioLevel(_ level: Float) {
        samples.removeFirst()
        samples.append(level.isFinite ? min(1, max(0, level)) : 0)
    }

    func clearWaveform() {
        samples = Array(repeating: 0, count: 80)
    }
}

enum DictationPanelCommand {
    case start, pause, resume, finish, dismiss, settings
    case clearRecovery(String)
}

struct DictationPanelCopyLabel: View {
    let isCopied: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            label("Copy", icon: "doc.on.doc")
                .opacity(isCopied ? 0 : 1)
                .accessibilityHidden(isCopied)
            label("Copied", icon: "checkmark")
                .opacity(isCopied ? 1 : 0)
                .accessibilityHidden(!isCopied)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
    }

    private func label(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 14, height: 14)
            Text(title)
        }
    }
}

private enum DictationPanelInk {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.08)
    static let text = Color(red: 0.95, green: 0.95, blue: 0.92)
    static let secondary = Color(red: 0.68, green: 0.68, blue: 0.66)
}

struct DictationPanelView: View {
    @ObservedObject var model: DictationPanelModel
    let command: (DictationPanelCommand) -> Void
    let dragEnded: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    @State private var isSpinning = false
    @State private var copiedRecoveryText: String?
    @State private var detailsHovered = false
    @State private var dismissedErrorID: UUID?
    @State private var openedDraftSessionID: UUID?

    var body: some View {
        capsule
        .frame(width: model.size.width, height: model.size.height)
        .background(DictationPanelInk.background, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(contrast == .increased ? 0.65 : 0.18), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .onHover { isHovered = $0 }
        .onChange(of: model.recoveryText) { copiedRecoveryText = nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.isPreview ? "Gojo dictation preview" : "Gojo dictation controls")
        .help(model.isPreview ? "Preview · " + model.title : model.title)
        .task(id: model.attentionIdentity) {
            guard model.attentionIdentity != nil else {
                model.showsDetails = false
                return
            }
            if model.recoveryText.isEmpty, model.errorMessage != nil,
               dismissedErrorID == model.errorPresentationID { return }
            if model.recoveryText.isEmpty, model.errorMessage == nil, model.emptyCompletion == nil,
               let preview = model.provisionalPreview {
                guard model.automaticallyOpensDraft, openedDraftSessionID != preview.sessionID else { return }
                openedDraftSessionID = preview.sessionID
                model.showsDetails = true
                return
            }
            model.showsDetails = true
            guard model.recoveryText.isEmpty else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                while detailsHovered {
                    try await Task.sleep(for: .milliseconds(200))
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    model.showsDetails = false
                }
            } catch {}
        }
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            icon("xmark", label: "Close voice controls", hint: "Cancel pending text and close.") { command(.dismiss) }
            waveformControl
                .frame(maxWidth: .infinity)
                .popover(isPresented: $model.showsDetails, arrowEdge: .top) { details }
            primaryAction
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .overlay(alignment: .top) {
            DictationPanelDragHandle(dragEnded: dragEnded)
                .frame(height: 7)
                .padding(.horizontal, 32)
        }
        .overlay(alignment: .bottom) {
            DictationPanelDragHandle(dragEnded: dragEnded)
                .frame(height: 7)
                .padding(.horizontal, 32)
        }
        .contextMenu {
            if model.state == .listening, model.isHandsFree {
                Button("Pause") { command(.pause) }
            }
            if model.state == .paused {
                Button("Resume") { command(.resume) }
                Button("Finish") { command(.finish) }
            }
            Button("Cancel") { command(.dismiss) }
        }
    }

    private var waveformControl: some View {
        Button {
            if needsAttention { model.showsDetails = true }
            else if model.state == .listening, model.isHandsFree { command(.pause) }
            else if model.state == .paused { command(.resume) }
        } label: {
            ZStack {
                DictationPanelWaveform(samples: model.samples, isRecording: model.state == .listening)
                    .frame(height: 26)
                    .opacity(model.isProcessing ? 0.25 : 1)
                if model.errorMessage != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                } else if !model.recoveryText.isEmpty {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DictationPanelInk.text)
                        .frame(width: 22, height: 22)
                        .background(DictationPanelInk.background, in: Circle())
                } else if model.isProcessing {
                    if reduceMotion {
                        Image(systemName: "ellipsis").foregroundStyle(DictationPanelInk.text)
                    } else {
                        Circle()
                            .trim(from: 0.12, to: 0.82)
                            .stroke(DictationPanelInk.text, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                            .frame(width: 12, height: 12)
                            .rotationEffect(.degrees(isSpinning ? 360 : 0))
                            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: isSpinning)
                            .onAppear { isSpinning = true }
                            .onDisappear { isSpinning = false }
                    }
                } else if model.state == .listening, model.isHandsFree, isHovered {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DictationPanelInk.text)
                        .frame(width: 22, height: 22)
                        .background(DictationPanelInk.background.opacity(0.9), in: Circle())
                }
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!needsAttention && model.state != .paused && !(model.state == .listening && model.isHandsFree))
        .help(model.errorMessage ?? (needsAttention ? "View dictation details" : model.state == .paused ? "Resume listening" : model.isHandsFree ? "Pause listening" : model.title))
        .accessibilityLabel(needsAttention ? "View dictation details" : model.state == .paused ? "Resume voice mode" : model.isHandsFree ? "Pause voice mode" : "Microphone waveform")
        .accessibilityValue(model.isPreview ? "Preview · " + model.title : model.title)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.state {
        case .idle:
            icon("mic.fill", label: "Start voice mode", hint: "Keep listening between phrases.", prominent: true) { command(.start) }
        case .succeeded:
            if model.shouldHideWhenFinished {
                icon("checkmark", label: "Text inserted", hint: "Dictation complete.", prominent: true) {}
                    .disabled(true)
            } else {
                icon("mic.fill", label: "Start voice mode", hint: "Keep listening between phrases.", prominent: true) { command(.start) }
            }
        case .error:
            if model.permissionSettingsURL != nil {
                icon("gearshape", label: "Open permission settings", hint: "Open the permission Gojo needs.", prominent: true) { command(.settings) }
            } else {
                Color.clear.frame(width: 26, height: 26).accessibilityHidden(true)
            }
        case .paused:
            icon("play.fill", label: "Resume voice mode", hint: "Turn the microphone back on.", prominent: true) { command(.resume) }
        case .listening, .pausing:
            icon("checkmark", label: "Finish dictation", hint: "Stop and add the remaining text.", prominent: true) { command(.finish) }
        case .requestingPermission, .transcribing, .inserting:
            icon("checkmark", label: "Finishing dictation", hint: "Text is being processed.", prominent: true) {}
                .disabled(true)
        }
    }

    private var needsAttention: Bool { model.attentionIdentity != nil }

    private var details: some View {
        Group {
            if !model.recoveryText.isEmpty {
                recovery
            } else if model.errorMessage == nil, model.emptyCompletion == nil,
                      let preview = model.provisionalPreview {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(preview.isWindowed ? "Recent speech" : "Draft preview")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if let intent = model.activeIntent {
                            Text(intent.label).font(.system(size: 11))
                        }
                    }
                    .foregroundStyle(DictationPanelInk.secondary)
                    ScrollView(.vertical) {
                        Text(preview.text)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    Text("Your full recording is transcribed when you finish.")
                        .font(.system(size: 11))
                        .foregroundStyle(DictationPanelInk.secondary)
                        .frame(height: 26)
                }
                .padding(16)
                .frame(width: 312)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.emptyCompletionMessage ?? (model.permissionSettingsURL == nil ? "Dictation needs attention" : "Permission needed"))
                        .font(.system(size: 13, weight: .semibold))
                    if let message = model.errorMessage {
                        Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                    if model.emptyCompletion != nil {
                        Text("Try again and speak a little longer.")
                            .font(.system(size: 12))
                    }
                    if model.permissionSettingsURL != nil {
                        detailButton("Open Settings") { model.showsDetails = false; command(.settings) }
                    }
                }
                .padding(16)
                .frame(width: 280)
            }
        }
        .foregroundStyle(DictationPanelInk.text)
        .background(DictationPanelInk.background)
        .onHover { detailsHovered = $0 }
        .preferredColorScheme(.dark)
    }

    private func detailButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DictationPanelInk.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dictated text")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DictationPanelInk.secondary)
            Text("Make sure a text field is selected before dictating.")
                .font(.system(size: 11))
                .foregroundStyle(DictationPanelInk.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView(.vertical) {
                Text(model.recoveryText)
                    .font(.system(size: 12))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
            HStack {
                Button {
                    let text = model.recoveryText
                    copiedRecoveryText = nil
                    if model.copyRecoveryText() {
                        copiedRecoveryText = text
                        dismissedErrorID = model.errorPresentationID
                        command(.clearRecovery(text))
                    }
                } label: {
                    DictationPanelCopyLabel(isCopied: copiedRecoveryText == model.recoveryText)
                }
                .accessibilityLabel(copiedRecoveryText == model.recoveryText ? "Copied" : "Copy dictated text")
                Spacer()
                Button("Discard") {
                    dismissedErrorID = model.errorPresentationID
                    command(.clearRecovery(model.recoveryText))
                }
                .foregroundStyle(DictationPanelInk.secondary)
                .frame(height: 26)
            }
            .font(.system(size: 11, weight: .medium))
            .buttonStyle(.plain)
            .frame(height: 26)
        }
        .foregroundStyle(DictationPanelInk.text)
        .padding(16)
        .frame(width: 312)
    }

    private func icon(_ symbol: String, label: String, hint: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DictationPanelInk.text)
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(prominent ? 0.15 : isHovered ? 0.065 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

enum DictationPanelWaveformShape {
    static func heights(samples: [Float], isRecording: Bool, time: TimeInterval?, height: CGFloat) -> [CGFloat] {
        let latest = CGFloat(samples.last ?? 0)
        let previous = CGFloat(samples.dropLast().last ?? samples.last ?? 0)
        let current = latest * 0.85 + previous * 0.15
        guard isRecording, current > 0 else { return Array(repeating: 1.5, count: 15) }
        return (0..<15).map { index in
            let distance = abs(index - 7)
            let delay = time == nil ? 0 : distance / 2
            let sampleIndex = max(0, samples.count - 1 - delay)
            let delayed = CGFloat(samples[sampleIndex])
            let level = pow(min(1, (current * 0.85 + delayed * 0.15) / 0.5), 1.1)
            let seed = sin(Double(index + 1) * 12.9898) * 43758.5453
            let texture = 0.45 + 0.55 * (seed - floor(seed))
            let ripple = time.map { 0.82 + 0.18 * sin($0 * 6.8 - Double(distance) * 0.8) } ?? 1
            return max(1.5, level * CGFloat(texture * ripple) * height)
        }
    }
}

private struct DictationPanelWaveform: View {
    let samples: [Float]
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isRecording || samples.last == 0 || reduceMotion)) { timeline in
            Canvas { context, size in
                let heights = DictationPanelWaveformShape.heights(
                    samples: samples, isRecording: isRecording,
                    time: reduceMotion ? nil : timeline.date.timeIntervalSinceReferenceDate,
                    height: size.height
                )
                let step = size.width / CGFloat(heights.count)
                for (index, height) in heights.enumerated() {
                    let width = min(1.25, step * 0.6)
                    let rect = CGRect(x: CGFloat(index) * step, y: (size.height - height) / 2, width: width, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(isRecording ? DictationPanelInk.text : DictationPanelInk.secondary.opacity(0.5)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DictationPanelDragHandle: NSViewRepresentable {
    let dragEnded: () -> Void

    func makeNSView(context: Context) -> DictationPanelDragView {
        let view = DictationPanelDragView()
        view.dragEnded = dragEnded
        return view
    }

    func updateNSView(_ view: DictationPanelDragView, context: Context) {
        view.dragEnded = dragEnded
    }
}

private final class DictationPanelDragView: NSView {
    var dragEnded: (() -> Void)?
    private var dragOrigin: CGPoint?
    private var windowOrigin: CGPoint?
    private var moved = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Move dictation controls")
        setAccessibilityHelp("Drag the top or bottom edge to move the window. Its position is saved when you release it.")
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        windowOrigin = window?.frame.origin
        moved = false
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin, let windowOrigin else { return }
        let location = NSEvent.mouseLocation
        let delta = CGPoint(x: location.x - dragOrigin.x, y: location.y - dragOrigin.y)
        moved = moved || abs(delta.x) + abs(delta.y) > 2
        window?.setFrameOrigin(CGPoint(x: windowOrigin.x + delta.x, y: windowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.pop()
        dragOrigin = nil
        windowOrigin = nil
        if moved { dragEnded?() }
    }
}
