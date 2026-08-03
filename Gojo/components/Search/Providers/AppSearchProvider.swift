import AppKit
import Defaults

/// Fuzzy-searches an in-memory index of installed `.app` bundles, ranked by
/// a blend of fuzzy match quality and launch frecency. The index is built
/// off-main on first use and cheaply rescanned in the background when stale.
actor AppSearchProvider: SearchProvider {
    static let shared = AppSearchProvider()

    nonisolated let providerID = "applications"
    nonisolated let sectionTitle = "Applications"

    private static let maxResults = 8
    private static let staleAfter: TimeInterval = 5 * 60
    private static let frecencyHalfLifeDays: Double = 14

    private static let searchRoots: [String] = [
        "/Applications",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]
    private static let coreServicesRoot = "/System/Library/CoreServices"

    private static let iconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        return cache
    }()

    private struct AppEntry {
        let url: URL
        let displayName: String
    }

    private var indexedApps: [AppEntry] = []
    private var lastIndexedAt: Date?
    private var isIndexing = false

    private init() {}

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await refreshIndexIfNeeded()

        var scored: [(entry: AppEntry, score: Double)] = []
        for entry in indexedApps {
            guard let matchScore = FuzzyMatcher.score(query: trimmed, in: entry.displayName) else { continue }
            let bonus = FuzzyMatcher.exactPrefixBonus(query: trimmed, candidate: entry.displayName)
            let frecency = Self.frecency(for: entry.url.path)
            let combined = (matchScore + bonus) * (1 + log(1 + frecency))
            scored.append((entry, combined))
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(Self.maxResults).map { Self.makeResult(for: $0.entry, score: $0.score) }
    }

    private func refreshIndexIfNeeded() async {
        let isStale: Bool
        if let lastIndexedAt {
            isStale = Date().timeIntervalSince(lastIndexedAt) >= Self.staleAfter
        } else {
            isStale = true
        }

        guard isStale, !isIndexing else { return }

        if indexedApps.isEmpty {
            // First use: caller is waiting on results, so index inline
            // (the scan itself still runs off-main via Task.detached).
            await performIndex()
        } else {
            // Already have something to show; refresh quietly in the background.
            isIndexing = true
            Task.detached(priority: .utility) { [weak self] in
                await self?.performIndex()
            }
        }
    }

    private func performIndex() async {
        let entries = await Task.detached(priority: .utility) {
            Self.scanApplications()
        }.value
        indexedApps = entries
        lastIndexedAt = Date()
        isIndexing = false
    }

    // MARK: - Filesystem scanning (pure, off-actor)

    private static func scanApplications() -> [AppEntry] {
        let fileManager = FileManager.default
        var entries: [AppEntry] = []
        var seenPaths = Set<String>()

        for root in searchRoots {
            collectApps(
                in: URL(fileURLWithPath: root),
                depth: 0,
                maxDepth: 2,
                fileManager: fileManager,
                into: &entries,
                seenPaths: &seenPaths
            )
        }

        if let items = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: coreServicesRoot),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for item in items where item.pathExtension == "app" {
                addAppIfNeeded(item, fileManager: fileManager, into: &entries, seenPaths: &seenPaths)
            }
        }

        return entries
    }

    private static func collectApps(
        in directory: URL,
        depth: Int,
        maxDepth: Int,
        fileManager: FileManager,
        into entries: inout [AppEntry],
        seenPaths: inout Set<String>
    ) {
        guard let items = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            if item.pathExtension == "app" {
                addAppIfNeeded(item, fileManager: fileManager, into: &entries, seenPaths: &seenPaths)
                continue
            }

            guard depth < maxDepth else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            collectApps(
                in: item,
                depth: depth + 1,
                maxDepth: maxDepth,
                fileManager: fileManager,
                into: &entries,
                seenPaths: &seenPaths
            )
        }
    }

    private static func addAppIfNeeded(
        _ url: URL,
        fileManager: FileManager,
        into entries: inout [AppEntry],
        seenPaths: inout Set<String>
    ) {
        let path = url.standardizedFileURL.path
        guard seenPaths.insert(path).inserted else { return }

        let displayName = fileManager.displayName(atPath: path)
        let strippedName = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        entries.append(AppEntry(url: url, displayName: strippedName))
    }

    // MARK: - Frecency

    /// Looks up the stored launch stats for `path` and runs them through the
    /// pure `FrecencyMath.frecency` — roughly halves in weight every
    /// `frecencyHalfLifeDays`.
    private static func frecency(for path: String) -> Double {
        guard let stat = Defaults[.searchAppLaunchStats][path] else { return 0 }
        return FrecencyMath.frecency(
            launchCount: stat.launchCount,
            lastLaunchedAt: stat.lastLaunchedAt,
            now: Date(),
            halfLifeDays: frecencyHalfLifeDays
        )
    }

    private nonisolated static func recordLaunch(path: String) {
        var stats = Defaults[.searchAppLaunchStats]
        var stat = stats[path] ?? SearchAppLaunchStat()
        stat.launchCount += 1
        stat.lastLaunchedAt = Date()
        stats[path] = stat
        Defaults[.searchAppLaunchStats] = stats
    }

    // MARK: - Icons

    private nonisolated static func icon(forPath path: String) -> NSImage? {
        let key = path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    private nonisolated static func makeResult(for entry: AppEntry, score: Double) -> SearchResult {
        let path = entry.url.path
        let url = entry.url
        return SearchResult(
            id: "app:\(path)",
            kind: .application,
            title: entry.displayName,
            subtitle: nil,
            score: score,
            iconProvider: {
                Self.icon(forPath: path)
            },
            action: {
                Task {
                    let configuration = NSWorkspace.OpenConfiguration()
                    _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                    Self.recordLaunch(path: path)
                }
            }
        )
    }
}
