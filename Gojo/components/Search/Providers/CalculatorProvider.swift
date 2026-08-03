import AppKit

/// Evaluates math expressions typed into search and surfaces a single,
/// very high scoring result so it pins to the top of the results list.
struct CalculatorProvider: SearchProvider {
    let providerID = "calculator"
    let sectionTitle = "Calculator"

    /// Comfortably above any fuzzy-matched score so the calculator result
    /// always sorts first when present.
    private static let pinnedScore = 10_000.0

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CalculatorEngine.looksLikeMath(trimmed) else { return [] }
        guard let value = CalculatorEngine.evaluate(trimmed) else { return [] }

        let formatted = Self.format(value)
        let title = "\(trimmed) = \(formatted)"

        return [
            SearchResult(
                id: "calculator:\(trimmed)",
                kind: .calculator,
                title: title,
                subtitle: "Press Enter to copy",
                score: Self.pinnedScore,
                iconProvider: {
                    NSImage(
                        systemSymbolName: "equal.circle",
                        accessibilityDescription: "Calculator"
                    )
                },
                action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(formatted, forType: .string)
                }
            )
        ]
    }

    /// Formats a `Double` for display: strips a trailing `.0`, limits to
    /// ~10 significant digits, and groups thousands.
    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 10
        formatter.roundingMode = .halfUp

        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
