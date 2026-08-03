import Foundation

/// Pure launch-frecency math, split out of `AppSearchProvider` so it can be
/// exercised by tests with `swiftc` directly (no AppKit/Defaults). Deliberately
/// depends only on Foundation.
enum FrecencyMath {
    /// `count * exp(-elapsed / halfLife-scaled)` — roughly halves in weight
    /// every `halfLifeDays`. `now` and `lastLaunchedAt` are passed in rather
    /// than read from `Date()` so callers (and tests) can be deterministic.
    static func frecency(launchCount: Int, lastLaunchedAt: Date, now: Date, halfLifeDays: Double) -> Double {
        let elapsedDays = max(0, now.timeIntervalSince(lastLaunchedAt) / 86_400)
        let decay = exp(-elapsedDays * log(2) / halfLifeDays)
        return Double(launchCount) * decay
    }
}
