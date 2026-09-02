//
//  AltTabSelection.swift
//  Gojo
//
//  Pure selection/cycling math for the per-display window switcher.
//  Kept dependency-free (Foundation only) so it can be unit-tested standalone
//  by tests/alt_tab_regression.sh.
//

import Foundation

struct AltTabRecency {
    private var orderedIDs: [String] = []

    mutating func order(freshIDs: [String]) -> [String] {
        let fresh = deduplicated(freshIDs)
        guard !fresh.isEmpty else {
            orderedIDs = []
            return orderedIDs
        }
        guard !orderedIDs.isEmpty else {
            orderedIDs = fresh
            return orderedIDs
        }

        let freshSet = Set(fresh)
        var next = [fresh[0]]
        next.append(contentsOf: orderedIDs.filter { $0 != fresh[0] && freshSet.contains($0) })
        next.append(contentsOf: fresh.filter { !next.contains($0) })
        orderedIDs = next
        return orderedIDs
    }

    mutating func promote(_ id: String) {
        orderedIDs.removeAll { $0 == id }
        orderedIDs.insert(id, at: 0)
    }

    private func deduplicated(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}

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

    static func pointerIndex(_ index: Int, count: Int) -> Int? {
        (0..<count).contains(index) ? index : nil
    }
}
