//
//  AltTabSelection.swift
//  Gojo
//
//  Pure selection/cycling math for the per-display window switcher.
//  Kept dependency-free (Foundation only) so it can be unit-tested standalone
//  by tests/alt_tab_regression.sh.
//

import Foundation

enum AltTabSelection {
    /// The index that should be highlighted when the switcher first opens.
    /// With 2+ windows we preselect index 1 (the window behind the frontmost
    /// one) so a quick trigger-and-release switches to the previous window,
    /// matching the macOS ⌘-Tab feel. With 0 or 1 windows we select index 0.
    static func initialIndex(count: Int) -> Int {
        count >= 2 ? 1 : 0
    }

    /// Advance the selection by one step, wrapping around. `reverse` moves
    /// backwards (⇧). Returns 0 when there are no windows.
    static func advance(from index: Int, count: Int, reverse: Bool) -> Int {
        guard count > 0 else { return 0 }
        let delta = reverse ? -1 : 1
        return ((index + delta) % count + count) % count
    }
}
