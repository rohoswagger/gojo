import SwiftUI

enum DictationNotchPhase: Equatable {
    case arming
    case listening
    case transcribing
    case inserting
    case success
    case error

    var isProcessing: Bool {
        self == .transcribing || self == .inserting
    }
}

@MainActor
final class DictationNotchActivityModel: ObservableObject {
    @Published private(set) var phase: DictationNotchPhase?

    private var hideTask: Task<Void, Never>?

    func update(state: DictationState, shortcutStarting: Bool) {
        hideTask?.cancel()
        hideTask = nil

        if shortcutStarting {
            phase = .arming
            return
        }

        switch state {
        case .requestingPermission:
            phase = .arming
        case .listening:
            phase = .listening
        case .transcribing:
            phase = .transcribing
        case .inserting:
            phase = .inserting
        case .succeeded:
            phase = .success
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                self?.phase = nil
                self?.hideTask = nil
            }
        case .error:
            phase = .error
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.4))
                guard !Task.isCancelled else { return }
                self?.phase = nil
                self?.hideTask = nil
            }
        case .idle:
            phase = nil
        }
    }
}

struct DictationNotchActivity: View {
    let phase: DictationNotchPhase
    let audioLevel: Double
    let closedNotchWidth: CGFloat
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func sideWidth(for height: CGFloat) -> CGFloat {
        min(36, max(30, height))
    }

    var body: some View {
        HStack(spacing: 0) {
            recordControl
                .frame(width: Self.sideWidth(for: height), height: height)

            Color.black
                .frame(width: max(0, closedNotchWidth), height: height)

            trailingActivity
                .frame(width: Self.sideWidth(for: height), height: height)
        }
        .frame(height: height)
        .opacity(phase == .success ? 0 : 1)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.14), value: phase)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .error ? "Dictation failed" : "Dictation active")
        .accessibilityHidden(phase != .error)
    }

    private var recordControl: some View {
        ZStack {
            Circle()
                .strokeBorder(recordColor.opacity(recordOpacity), lineWidth: 1.25)
                .frame(width: 13, height: 13)

            Circle()
                .fill(Color.black)
                .frame(width: 10, height: 10)

            Circle()
                .fill(recordColor.opacity(phase.isProcessing ? 0 : recordOpacity))
                .frame(width: 6.5, height: 6.5)
        }
    }

    private var recordColor: Color {
        phase.isProcessing
            ? Color(red: 0.96, green: 0.96, blue: 0.97)
            : Color(red: 1, green: 0.27, blue: 0.23)
    }

    @ViewBuilder
    private var trailingActivity: some View {
        if phase == .error {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.34, blue: 0.29))
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(
                            with: .scale(scale: 0.82, anchor: .leading)
                        ),
                        removal: .opacity
                    )
                )
        } else {
            waveform
        }
    }

    @ViewBuilder
    private var waveform: some View {
        if phase.isProcessing && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                waveformBars { index in
                    processingHeight(for: index, at: context.date)
                }
            }
        } else {
            waveformBars { index in
                staticHeight(for: index)
            }
            .animation(.linear(duration: reduceMotion ? 0 : 0.08), value: audioLevel)
        }
    }

    private func waveformBars(
        heightForIndex: @escaping (Int) -> CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0 ..< 4, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(waveformOpacity))
                    .frame(width: 2, height: heightForIndex(index))
            }
        }
        .frame(width: 14, height: 14)
    }

    private var recordOpacity: Double {
        switch phase {
        case .arming: 0.42
        case .transcribing, .inserting: 0.72
        case .listening: 1
        case .error: 0.72
        case .success: 0
        }
    }

    private var waveformOpacity: Double {
        switch phase {
        case .arming: 0.38
        case .transcribing, .inserting: 0.76
        case .listening: 0.94
        case .success, .error: 0
        }
    }

    private func staticHeight(for index: Int) -> CGFloat {
        if phase == .arming || reduceMotion {
            return [4, 7, 9, 5][index]
        }

        let normalizedLevel = min(1, max(0, audioLevel))
        let shapedLevel = sqrt(normalizedLevel)
        let weights = [0.62, 0.88, 1.0, 0.72]
        return min(14, 4 + CGFloat(shapedLevel * 10 * weights[index]))
    }

    private func processingHeight(for index: Int, at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
        let phaseOffset = Double(index) * 0.18
        let wave = (sin((elapsed * 7.5) - phaseOffset) + 1) / 2
        return 4 + CGFloat(wave * 8)
    }
}
