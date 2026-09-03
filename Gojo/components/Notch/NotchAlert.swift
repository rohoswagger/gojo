import SwiftUI

/// A transient message shown in the closed notch.
///
/// This is the app-wide surface for telling the user that something failed or
/// needs attention while the notch is closed. Any feature can post one; the
/// dictation pipeline is the first consumer. Keep the text short — the banner
/// sits beside the physical notch and truncates rather than wrapping.
struct NotchAlert: Equatable, Identifiable, Sendable {
    enum Severity: Equatable, Sendable {
        case error
        case warning
        case info

        var symbol: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "clock.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: return Color(red: 1, green: 0.34, blue: 0.29)
            case .warning: return Color(red: 1, green: 0.72, blue: 0.23)
            case .info: return Color(red: 0.62, green: 0.76, blue: 1)
            }
        }
    }

    /// Names the feature that posted the alert so a later message from the same
    /// source replaces its predecessor instead of queueing behind it.
    enum Source: String, Equatable, Sendable {
        case dictation
    }

    let id = UUID()
    let source: Source
    let severity: Severity
    let message: String
    /// Optional short trailing hint, e.g. the shortcut to press to retry.
    let hint: String?

    init(source: Source, severity: Severity, message: String, hint: String? = nil) {
        self.source = source
        self.severity = severity
        self.message = message
        self.hint = hint
    }

    static func == (lhs: NotchAlert, rhs: NotchAlert) -> Bool {
        lhs.source == rhs.source
            && lhs.severity == rhs.severity
            && lhs.message == rhs.message
            && lhs.hint == rhs.hint
    }
}

/// Renders an alert directly beneath the physical notch.
///
/// The camera housing occupies the top strip, so the message is offset below
/// it rather than squeezed into the slivers on either side — the notch simply
/// grows taller for as long as the alert is up, and the text gets the full
/// width to read across.
struct NotchAlertView: View {
    let alert: NotchAlert
    let closedNotchWidth: CGFloat
    let notchHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width the message column needs to read comfortably without truncating.
    private static let contentWidth: CGFloat = 360

    /// Total width the notch takes while an alert is showing. The message
    /// column is centered under the housing rather than beside it.
    static func totalWidth(closedNotchWidth: CGFloat) -> CGFloat {
        max(closedNotchWidth + 48, contentWidth)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Reserve the physical notch so nothing renders behind the camera.
            Color.clear
                .frame(width: max(0, closedNotchWidth), height: notchHeight)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: alert.severity.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(alert.severity.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.message)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if let hint = alert.hint {
                        Text(hint)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 9)
            .padding(.bottom, 12)
        }
        .frame(width: Self.totalWidth(closedNotchWidth: closedNotchWidth))
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: alert)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            alert.hint.map { "\(alert.message). \($0)" } ?? alert.message
        )
    }
}
