import AppKit
import Foundation

/// Name-only file search backed by `NSMetadataQuery` (Spotlight). App
/// bundles are excluded since `AppSearchProvider` already covers those.
/// The app is sandboxed, so results are limited to what Spotlight can see
/// for this process — that's expected and not something this provider
/// works around.
struct FileSearchProvider: SearchProvider {
    let providerID = "files"
    let sectionTitle = "Files"

    private static let maxResults = 10
    private static let gatherTimeout: TimeInterval = 1.5
    private static let applicationBundleType = "com.apple.application-bundle"

    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let urls = await Self.gatherMatches(query: trimmed)
        guard !Task.isCancelled else { return [] }

        let home = NSHomeDirectory()
        var scored: [(url: URL, score: Double)] = []
        for url in urls {
            let displayName = url.lastPathComponent
            let matchScore = FuzzyMatcher.score(query: trimmed, in: displayName)
                ?? FuzzyMatcher.exactPrefixBonus(query: trimmed, candidate: displayName)
            scored.append((url, matchScore))
        }
        scored.sort { $0.score > $1.score }

        return scored.prefix(Self.maxResults).map { pair in
            Self.makeResult(url: pair.url, score: pair.score, homeDirectory: home)
        }
    }

    // MARK: - NSMetadataQuery

    /// Guards a completion callback so it only ever fires once, whether it
    /// arrives from `DidFinishGathering`, the timeout, or cancellation.
    private final class CompletionGuard: @unchecked Sendable {
        private let lock = NSLock()
        private var didFinish = false

        func finishOnce(_ work: () -> Void) {
            lock.lock()
            let alreadyFinished = didFinish
            didFinish = true
            lock.unlock()
            guard !alreadyFinished else { return }
            work()
        }
    }

    /// Holds a reference to the in-flight `finish` closure so the
    /// `onCancel` handler — which runs outside the `withCheckedContinuation`
    /// closure that defines `finish` — can trigger the same completion path
    /// instead of only stopping the query and waiting out the timeout.
    private final class FinishBox: @unchecked Sendable {
        var finish: (() -> Void)?
    }

    @MainActor
    private static func gatherMatches(query: String) async -> [URL] {
        let metadataQuery = NSMetadataQuery()
        metadataQuery.predicate = NSPredicate(format: "kMDItemDisplayName CONTAINS[cd] %@", query)
        metadataQuery.searchScopes = [NSMetadataQueryUserHomeScope]
        metadataQuery.valueListAttributes = [
            NSMetadataItemDisplayNameKey,
            NSMetadataItemContentTypeTreeKey,
            NSMetadataItemPathKey,
        ]

        let finishBox = FinishBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[URL], Never>) in
                let completionGuard = CompletionGuard()
                var observer: NSObjectProtocol?

                let finish: () -> Void = {
                    completionGuard.finishOnce {
                        metadataQuery.stop()
                        if let observer {
                            NotificationCenter.default.removeObserver(observer)
                        }
                        let urls = Self.extractURLs(from: metadataQuery)
                        continuation.resume(returning: urls)
                    }
                }
                finishBox.finish = finish

                observer = NotificationCenter.default.addObserver(
                    forName: .NSMetadataQueryDidFinishGathering,
                    object: metadataQuery,
                    queue: .main
                ) { _ in
                    finish()
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + gatherTimeout) {
                    finish()
                }

                metadataQuery.start()
            }
        } onCancel: {
            // Runs off the cancelling thread; hop to main since `finish`
            // touches the MainActor-only `metadataQuery` and posts to
            // `continuation`. `completionGuard` inside `finish` keeps this
            // safe if it races `DidFinishGathering`/the timeout.
            Task { @MainActor in
                finishBox.finish?()
            }
        }
    }

    private static func extractURLs(from query: NSMetadataQuery) -> [URL] {
        query.disableUpdates()
        defer { query.enableUpdates() }

        var urls: [URL] = []
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            if let typeTree = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String],
               typeTree.contains(applicationBundleType) {
                continue
            }
            urls.append(URL(fileURLWithPath: path))
        }
        return urls
    }

    // MARK: - Result building

    private static func makeResult(url: URL, score: Double, homeDirectory: String) -> SearchResult {
        let path = url.path
        let displayName = url.lastPathComponent
        return SearchResult(
            id: "file:\(path)",
            kind: .file,
            title: displayName,
            subtitle: abbreviatedPath(for: url, homeDirectory: homeDirectory),
            score: score,
            iconProvider: {
                Self.icon(forPath: path)
            },
            action: {
                NSWorkspace.shared.open(url)
            }
        )
    }

    private static func abbreviatedPath(for url: URL, homeDirectory: String) -> String {
        let directory = url.deletingLastPathComponent().path
        guard directory.hasPrefix(homeDirectory) else { return directory }
        let relative = directory.dropFirst(homeDirectory.count)
        return relative.isEmpty ? "~" : "~\(relative)"
    }

    private static func icon(forPath path: String) -> NSImage? {
        let key = path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }
}
