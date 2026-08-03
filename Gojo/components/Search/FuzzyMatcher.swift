import Foundation

/// Greedy subsequence fuzzy matcher used to rank search results against a
/// typed query. Pure, allocation-light, and safe to call on every keystroke.
enum FuzzyMatcher {
    private static let baseCharScore = 1.0
    private static let consecutiveBonus = 1.5
    private static let boundaryBonus = 2.0
    private static let lengthPenaltyFactor = 0.02

    /// Large flat bonus callers can add on top of `score(query:in:)` for a
    /// case-insensitive exact-prefix match, to pin those results to the top.
    static let exactPrefixBonusValue = 100.0

    /// Scores `candidate` against `query` as a greedy left-to-right
    /// subsequence match. Returns `nil` if `query` is not a subsequence of
    /// `candidate` (case-insensitive), or either string is empty.
    static func score(query: String, in candidate: String) -> Double? {
        guard !query.isEmpty, !candidate.isEmpty else { return nil }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate)
        let candidateLowerChars = Array(candidate.lowercased())

        // Case-folding can change character count for rare Unicode
        // sequences; bail out to a safe non-match rather than risk an
        // out-of-bounds index.
        guard candidateChars.count == candidateLowerChars.count else { return nil }

        var queryIndex = 0
        var total = 0.0
        var consecutiveRun = 0
        var previousMatchIndex: Int?

        for i in 0..<candidateChars.count {
            guard queryIndex < queryChars.count else { break }
            guard candidateLowerChars[i] == queryChars[queryIndex] else { continue }

            total += baseCharScore

            if let previous = previousMatchIndex, previous == i - 1 {
                consecutiveRun += 1
                total += consecutiveBonus * Double(consecutiveRun)
            } else {
                consecutiveRun = 0
            }

            if isWordBoundary(candidateChars, at: i) {
                total += boundaryBonus
            }

            previousMatchIndex = i
            queryIndex += 1
        }

        guard queryIndex == queryChars.count else { return nil }

        let lengthPenalty = Double(candidateChars.count) * lengthPenaltyFactor
        return max(0, total - lengthPenalty)
    }

    private static func isWordBoundary(_ chars: [Character], at index: Int) -> Bool {
        if index == 0 { return true }
        let previous = chars[index - 1]
        if previous == " " || previous == "-" || previous == "_" || previous == "." {
            return true
        }
        let current = chars[index]
        if previous.isLowercase, current.isUppercase {
            return true
        }
        return false
    }

    /// Flat bonus to add on top of `score(query:in:)` when `candidate`
    /// starts with `query` (case-insensitive). Zero when it doesn't.
    static func exactPrefixBonus(query: String, candidate: String) -> Double {
        guard !query.isEmpty else { return 0 }
        return candidate.lowercased().hasPrefix(query.lowercased()) ? exactPrefixBonusValue : 0
    }
}
