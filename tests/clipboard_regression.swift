import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct ClipboardRegressionRunner {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_777_000_000)

        var store = ClipboardCollection(maxStoredItems: 10)
        store.registerCopy(content: "alpha", sourceAppName: "A", sourceBundleID: "a", at: base)
        store.registerCopy(content: "beta", sourceAppName: "B", sourceBundleID: "b", at: base.addingTimeInterval(10))
        store.registerCopy(content: "gamma", sourceAppName: "C", sourceBundleID: "c", at: base.addingTimeInterval(20))

        let alphaID = store.orderedItems.first(where: { $0.content == "alpha" })!.id
        let betaID = store.orderedItems.first(where: { $0.content == "beta" })!.id
        let gammaID = store.orderedItems.first(where: { $0.content == "gamma" })!.id

        assertCondition(store.orderedItems.map(\.content) == ["gamma", "beta", "alpha"], "Unpinned items should sort by recency descending")

        store.togglePin(for: betaID)
        store.togglePin(for: alphaID)
        assertCondition(store.orderedItems.map(\.content) == ["beta", "alpha", "gamma"], "Pinned items should preserve queue order (first pinned stays first)")

        store.togglePin(for: betaID)
        store.togglePin(for: betaID)
        assertCondition(store.orderedItems.map(\.content) == ["alpha", "beta", "gamma"], "Re-pinning should append to the end of the pinned queue")

        store.registerCopy(content: "gamma", sourceAppName: "C", sourceBundleID: "c", at: base.addingTimeInterval(30))
        let gamma = store.orderedItems.first(where: { $0.id == gammaID })!
        assertCondition(gamma.copyCount == 2, "Duplicate copies should increment copy count")
        assertCondition(store.orderedItems.map(\.content) == ["alpha", "beta", "gamma"], "Recopied unpinned item should stay below pinned queue")

        let filtered = store.filteredItems(matching: "a")
        assertCondition(filtered.map(\.content) == ["alpha", "beta", "gamma"], "Filtered results should respect stable pinned ordering and score ties")

        var exactStore = ClipboardCollection(maxStoredItems: 10)
        let rawClip = "  line one\n\nline two  "
        exactStore.registerCopy(content: rawClip, sourceAppName: "Exact", sourceBundleID: "exact", at: base)
        assertCondition(exactStore.orderedItems.first?.content == rawClip, "Clipboard content should be stored without trimming or whitespace mutation")

        exactStore.registerCopy(content: rawClip, sourceAppName: "Exact", sourceBundleID: "exact", at: base.addingTimeInterval(1))
        assertCondition(exactStore.orderedItems.count == 1, "Exact duplicate content should dedupe")
        assertCondition(exactStore.orderedItems.first?.copyCount == 2, "Exact duplicate copies should increment count")

        exactStore.registerCopy(content: "line one\n\nline two", sourceAppName: "Exact", sourceBundleID: "exact", at: base.addingTimeInterval(2))
        assertCondition(exactStore.orderedItems.count == 2, "Whitespace-different clipboard entries should remain distinct")

        let previewID = UUID()
        var uiState = ClipboardTransientInteractionState()
        uiState.setHoveredItemID(previewID)
        uiState.setPointerOverHoveredRow(true)
        assertCondition(uiState.shouldPresentPreview(for: previewID), "Preview should only present when the hovered row still matches the candidate item")
        uiState.setPointerOverHoveredRow(false)
        assertCondition(uiState.shouldHidePreview(), "Preview should hide once neither the row nor preview panel is hovered")

        let copiedID = UUID()
        uiState.markCopied(copiedID)
        assertCondition(uiState.copiedItemID == copiedID, "Copy feedback should track the most recently copied row")
        uiState.clearCopied(ifMatches: copiedID)
        assertCondition(uiState.copiedItemID == nil, "Copy feedback should clear when the matching row feedback expires")

        var limited = ClipboardCollection(maxStoredItems: 2)
        limited.registerCopy(content: "one", sourceAppName: nil, sourceBundleID: nil, at: base)
        limited.registerCopy(content: "two", sourceAppName: nil, sourceBundleID: nil, at: base.addingTimeInterval(10))
        limited.registerCopy(content: "three", sourceAppName: nil, sourceBundleID: nil, at: base.addingTimeInterval(20))
        assertCondition(limited.orderedItems.map(\.content) == ["three", "two"], "Entry limit should evict oldest unpinned items first")

        print("clipboard-regression-pass")
    }
}
