import AppKit
import Foundation

actor SystemSettingsSearchProvider: SearchProvider {
    nonisolated let providerID = "system-settings"
    nonisolated let sectionTitle = "System Settings"

    struct Entry: Sendable {
        let id: String
        let title: String
        let deepLinkIdentifier: String
        let bundleURL: URL
        let searchAliases: [String]

        init(
            id: String,
            title: String,
            deepLinkIdentifier: String,
            bundleURL: URL,
            searchAliases: [String] = []
        ) {
            self.id = id
            self.title = title
            self.deepLinkIdentifier = deepLinkIdentifier
            self.bundleURL = bundleURL
            self.searchAliases = searchAliases
        }

        var deepLinkURL: URL? {
            URL(string: "x-apple.systempreferences:\(deepLinkIdentifier)")
        }
    }

    private static let extensionDirectories = [
        URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions", isDirectory: true),
        URL(
            fileURLWithPath: "/System/Applications/System Settings.app/Contents/PlugIns",
            isDirectory: true
        ),
    ]
    private static let settingsExtensionPoint = "com.apple.Settings.extension.ui"
    private static let maxResults = 8

    private var indexedEntries: [Entry]?
    private var indexTask: Task<[Entry], Never>?
    private let openURL: (URL) -> Void

    init() {
        indexedEntries = nil
        indexTask = nil
        openURL = { url in
            NSWorkspace.shared.open(url)
        }
    }

    init(entries: [Entry], openURL: @escaping (URL) -> Void) {
        indexedEntries = entries
        indexTask = nil
        self.openURL = openURL
    }

    func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalizedQuery = Self.normalizedSearchText(trimmed)
        guard !normalizedQuery.isEmpty else { return [] }

        let entries = await loadEntries()
        guard !Task.isCancelled else { return [] }

        let scored = entries.compactMap { entry -> (entry: Entry, score: Double)? in
            let candidates = ([entry.title] + entry.searchAliases).flatMap { name in
                [name, "\(name) Settings", "\(name) System Settings", "System Settings \(name)"]
            }
            let score = candidates.compactMap { candidate -> Double? in
                let normalizedCandidate = Self.normalizedSearchText(candidate)
                guard let matchScore = FuzzyMatcher.score(query: normalizedQuery, in: normalizedCandidate) else {
                    return nil
                }
                return matchScore
                    + FuzzyMatcher.exactPrefixBonus(query: normalizedQuery, candidate: normalizedCandidate)
            }.max()
            guard let score else { return nil }
            return (entry, score)
        }

        return scored
            .sorted {
                if $0.score == $1.score {
                    return $0.entry.title.localizedStandardCompare($1.entry.title) == .orderedAscending
                }
                return $0.score > $1.score
            }
            .prefix(Self.maxResults)
            .compactMap { pair in
                makeResult(for: pair.entry, score: pair.score)
            }
    }

    private func loadEntries() async -> [Entry] {
        if let indexedEntries {
            return indexedEntries
        }

        let task: Task<[Entry], Never>
        if let indexTask {
            task = indexTask
        } else {
            task = Task.detached(priority: .utility) {
                Self.scanEntries()
            }
            indexTask = task
        }

        let entries = await task.value
        indexedEntries = entries
        indexTask = nil
        return entries
    }

    private func makeResult(for entry: Entry, score: Double) -> SearchResult? {
        guard let deepLinkURL = entry.deepLinkURL else { return nil }
        let openURL = self.openURL
        return SearchResult(
            id: "system-setting:\(entry.id)",
            kind: .systemSetting,
            title: entry.title,
            subtitle: "System Settings",
            score: score,
            iconProvider: {
                NSWorkspace.shared.icon(forFile: entry.bundleURL.path)
            },
            action: {
                openURL(deepLinkURL)
            }
        )
    }

    private static func scanEntries() -> [Entry] {
        scanEntries(in: extensionDirectories)
    }

    static func scanEntries(in directories: [URL]) -> [Entry] {
        let bundleURLs = directories.flatMap { directory in
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        var seenIDs = Set<String>()
        return bundleURLs.compactMap { bundleURL in
            guard bundleURL.pathExtension == "appex",
                  let bundle = Bundle(url: bundleURL),
                  let info = bundle.infoDictionary else {
                return nil
            }
            let localizedTitle = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            let localizedAliases = localizedRepresentationNames(bundle: bundle, info: info)
            guard let entry = entry(
                bundleURL: bundleURL,
                info: info,
                localizedTitle: localizedTitle,
                localizedAliases: localizedAliases
            ),
                  seenIDs.insert(entry.id).inserted else {
                return nil
            }
            return entry
        }
    }

    static func entry(
        bundleURL: URL,
        info: [String: Any],
        localizedTitle: String?,
        localizedAliases: [String] = []
    ) -> Entry? {
        guard let extensionAttributes = info["EXAppExtensionAttributes"] as? [String: Any],
              extensionAttributes["EXExtensionPointIdentifier"] as? String == settingsExtensionPoint,
              let settingsAttributes = extensionAttributes["SettingsExtensionAttributes"] as? [String: Any],
              settingsAttributes["allowsXAppleSystemPreferencesURLScheme"] as? Bool == true,
              let id = info["CFBundleIdentifier"] as? String,
              let localizedTitle,
              !localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let legacyIdentifiers: [String]
        if let legacyIdentifier = settingsAttributes["legacyBundleIdentifier"] as? String {
            legacyIdentifiers = [legacyIdentifier]
        } else {
            legacyIdentifiers = settingsAttributes["legacyBundleIdentifier"] as? [String] ?? []
        }
        let deepLinkIdentifier = legacyIdentifiers.count == 1 ? legacyIdentifiers[0] : id
        let identifierTitle = humanReadableIdentifier(id)
        let searchTermsTitle = (settingsAttributes["searchTermsFileName"] as? String)
            .map(humanReadableIdentifier)
        let title = isInternalTitle(localizedTitle) && !identifierTitle.isEmpty
            ? localizedAliases.last ?? identifierTitle
            : localizedTitle
        let aliases = uniqueStrings(
            [localizedTitle, identifierTitle]
                + [searchTermsTitle].compactMap { $0 }
                + localizedAliases
                + legacyIdentifiers.map(humanReadableIdentifier)
        ).filter { $0.caseInsensitiveCompare(title) != .orderedSame }

        return Entry(
            id: id,
            title: title,
            deepLinkIdentifier: deepLinkIdentifier,
            bundleURL: bundleURL,
            searchAliases: aliases
        )
    }

    private static func localizedRepresentationNames(bundle: Bundle, info: [String: Any]) -> [String] {
        guard let extensionAttributes = info["EXAppExtensionAttributes"] as? [String: Any],
              let settingsAttributes = extensionAttributes["SettingsExtensionAttributes"] as? [String: Any],
              let representations = settingsAttributes["representations"] as? [[String: Any]] else {
            return []
        }

        return representations.compactMap { representation in
            guard let key = representation["sidebar-name"] as? String else { return nil }
            let value = bundle.localizedString(forKey: key, value: nil, table: nil)
            return value == key ? nil : value
        }
    }

    private static func humanReadableIdentifier(_ identifier: String) -> String {
        let genericComponents = Set([
            "apple", "com", "extension", "preference", "preferences", "prefpane", "settings",
        ])
        let separatedIdentifier = identifier
            .replacingOccurrences(of: "SettingsExtension", with: " ")
            .replacingOccurrences(of: "Settings", with: " ")
            .replacingOccurrences(of: "Preferences", with: " ")
            .replacingOccurrences(
                of: "([A-Z])([A-Z][a-z])",
                with: "$1 $2",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "([a-z0-9])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            )
        let components = separatedIdentifier
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !genericComponents.contains($0.lowercased()) }
        return components.joined(separator: " ")
    }

    private static func normalizedSearchText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        var result = ""
        var needsSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !result.isEmpty {
                    result.append(" ")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }

        return result
    }

    private static func isInternalTitle(_ title: String) -> Bool {
        !title.contains(" ")
            && ["Extension", "Preferences", "Settings"].contains(where: title.contains)
    }

    private static func uniqueStrings(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        return strings.compactMap { string in
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
            return trimmed
        }
    }
}
