import AppKit

private final class MetadataItem: NSMetadataItem {
    override func value(forAttribute key: String) -> Any? {
        switch key {
        case NSMetadataItemPathKey: return "/tmp/gojo-search-example.txt"
        case NSMetadataItemContentTypeTreeKey: return ["public.text"]
        default: return nil
        }
    }
}

private final class MetadataQuery: NSMetadataQuery {
    var didStart = false
    var didStop = false
    var itemsRead = 0
    var canStart = true
    override var resultCount: Int { 10_000 }
    override var results: [Any] {
        itemsRead += resultCount
        return (0..<resultCount).map { _ in MetadataItem() }
    }
    override func result(at index: Int) -> Any {
        itemsRead += 1
        return MetadataItem()
    }
    override func start() -> Bool { didStart = true; return canStart }
    override func stop() { didStop = true }
    override func disableUpdates() {}
    override func enableUpdates() {}
}

@main
struct FileSearchCancellationRegression {
    @MainActor static func main() async {
        let cancelled = MetadataQuery()
        let cancelledTask = Task { await FileSearchProvider.gatherMatches(query: "a", metadataQuery: cancelled) }
        await waitForStart(cancelled)
        cancelledTask.cancel()
        let cancelledURLs = await cancelledTask.value
        expect(cancelled.didStop, "Cancelled searches stop Spotlight")
        expect(cancelledURLs.isEmpty, "Cancelled searches return no stale matches")
        expect(cancelled.itemsRead == 0, "Cancelled searches must not enumerate metadata on the UI thread")

        NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: cancelled)
        expect(cancelled.itemsRead == 0, "Late completion cannot collect cancelled results")

        let notStarted = MetadataQuery()
        let notStartedTask = Task { await FileSearchProvider.gatherMatches(query: "a", metadataQuery: notStarted) }
        notStartedTask.cancel()
        let notStartedURLs = await notStartedTask.value
        expect(notStartedURLs.isEmpty && !notStarted.didStart, "Already-cancelled searches do not start Spotlight")

        let failed = MetadataQuery()
        failed.canStart = false
        let failedURLs = await FileSearchProvider.gatherMatches(query: "a", metadataQuery: failed)
        expect(failedURLs.isEmpty && failed.itemsRead == 0, "Failed query starts do not collect results")

        let completed = MetadataQuery()
        let completedTask = Task { await FileSearchProvider.gatherMatches(query: "a", metadataQuery: completed) }
        await waitForStart(completed)
        NotificationCenter.default.post(name: .NSMetadataQueryDidFinishGathering, object: completed)
        expect(completed.didStop, "Gathering notifications finish without waiting for the timeout")
        let completedURLs = await completedTask.value
        expect(completed.didStop, "Completed searches stop Spotlight")
        expect(!completedURLs.isEmpty, "Completed searches retain file matches")
        expect(completed.itemsRead == 200 && completedURLs.count == 200, "Broad searches must bound metadata reads on the UI thread")
        expect(completedURLs.first?.path == "/tmp/gojo-search-example.txt", "Metadata paths become file URLs")
        print("File search cancellation and bounded gathering regressions passed")
    }

    @MainActor private static func waitForStart(_ query: MetadataQuery) async {
        let deadline = Date().addingTimeInterval(2)
        while !query.didStart && Date() < deadline { await Task.yield() }
        expect(query.didStart, "Metadata query did not start")
    }

    static func expect(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
