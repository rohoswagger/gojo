import AppKit

/// Extensible kind tag for a search result. New providers should add a new
/// case here rather than repurposing an existing one.
enum SearchResultKind: String, Equatable {
    case application
    case file
    case systemSetting
    case calculator
}

/// A single row surfaced by a `SearchProvider`. Icons are fetched lazily via
/// `iconProvider` so providers can index large numbers of results cheaply.
struct SearchResult: Identifiable {
    /// Stable identity across searches, e.g. a provider-prefixed path or
    /// expression string. Used for selection tracking and diffing.
    let id: String
    let kind: SearchResultKind
    let title: String
    let subtitle: String?
    let score: Double
    let iconProvider: () -> NSImage?
    let action: () -> Void

    init(
        id: String,
        kind: SearchResultKind,
        title: String,
        subtitle: String? = nil,
        score: Double,
        iconProvider: @escaping () -> NSImage? = { nil },
        action: @escaping () -> Void
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.score = score
        self.iconProvider = iconProvider
        self.action = action
    }
}

extension SearchResult: Equatable {
    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// A titled group of results shown together in the UI, e.g. "Applications".
struct SearchSection: Identifiable, Equatable {
    let id: String
    let title: String
    let results: [SearchResult]
}
