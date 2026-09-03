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

/// Renders an alert across the closed notch: message on the left, the physical
/// notch cutout in the middle, severity glyph on the right. The layout mirrors
/// the battery notification so both read as the same system.
struct NotchAlertView: View {
    let alert: NotchAlert
    let closedNotchWidth: CGFloat
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Width added to each side of the notch cutout for the banner content.
    static let sideWidth: CGFloat = 132

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: alert.severity.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(alert.severity.tint)

                Text(alert.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 12)
            .frame(width: Self.sideWidth, alignment: .leading)

            Color.black
                .frame(width: max(0, closedNotchWidth), height: height)

            HStack {
                if let hint = alert.hint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.trailing, 12)
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .frame(height: height)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: alert)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            alert.hint.map { "\(alert.message). \($0)" } ?? alert.message
        )
    }
}
