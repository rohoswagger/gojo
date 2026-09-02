import Combine
import Defaults
import Foundation

/// Drives the Spotlight-style search surface: owns the query, fans it out
/// to the registered `SearchProvider`s, and merges their results into
/// ordered sections as they arrive. Mirrors the shape of
/// `ClipboardStateViewModel` (singleton, `@Published private(set)` state,
/// a `searchFocusRequestID` bump for requesting keyboard focus).
@MainActor
final class SearchStateViewModel: ObservableObject {
    static let shared = SearchStateViewModel()

    private static let debounceInterval: Duration = .milliseconds(150)

    @Published var query: String = ""
    @Published private(set) var sections: [SearchSection] = []
    @Published private(set) var selectedResultID: String?
    @Published private(set) var searchFocusRequestID = UUID()

    /// Whether the most recent `selectedResultID` change came from the
    /// keyboard (arrow keys, auto-select-first-result) as opposed to a
    /// mouse hover. Views use this to decide whether to auto-scroll —
    /// scrolling in response to a hover-driven selection change would
    /// move rows under a stationary cursor and re-trigger hover, causing
    /// jitter.
    private(set) var lastSelectionWasKeyboard = true

    /// Providers are fanned out in this order and sections publish in this
    /// same fixed order (Calculator, Applications, System Settings, Files). Adding a new
    /// provider is a one-line change here — nothing else needs to know.
    private let providers: [SearchProvider] = [
        CalculatorProvider(),
        AppSearchProvider.shared,
        SystemSettingsSearchProvider(),
        FileSearchProvider(),
    ]

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeQuery()
    }

    var flattenedResults: [SearchResult] {
        sections.flatMap { $0.results }
    }

    func requestSearchFocus() {
        searchFocusRequestID = UUID()
    }

    /// Clears query, results, and selection. Called when the notch closes.
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        query = ""
        sections = []
        selectedResultID = nil
    }

    /// Sets the selection cursor directly, e.g. in response to a hover.
    func select(id: String) {
        lastSelectionWasKeyboard = false
        selectedResultID = id
    }

    /// Moves the selection cursor across the flattened result list,
    /// wrapping at either end.
    func moveSelection(by delta: Int) {
        lastSelectionWasKeyboard = true
        let flat = flattenedResults
        guard !flat.isEmpty else {
            selectedResultID = nil
            return
        }
        guard let currentID = selectedResultID,
              let currentIndex = flat.firstIndex(where: { $0.id == currentID }) else {
            selectedResultID = delta >= 0 ? flat.first?.id : flat.last?.id
            return
        }
        let count = flat.count
        let newIndex = ((currentIndex + delta) % count + count) % count
        selectedResultID = flat[newIndex].id
    }

    /// Runs the currently selected result's action. Returns `true` if a
    /// result was activated (so the caller can e.g. close the notch).
    @discardableResult
    func activateSelection() -> Bool {
        guard let currentID = selectedResultID,
              let result = flattenedResults.first(where: { $0.id == currentID }) else { return false }
        result.action()
        return true
    }

    private func observeQuery() {
        $query
            .removeDuplicates()
            .sink { [weak self] newQuery in
                self?.handleQueryChanged(newQuery)
            }
            .store(in: &cancellables)
    }

    private func handleQueryChanged(_ newQuery: String) {
        searchTask?.cancel()

        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Defaults[.searchEnabled] else {
            sections = []
            selectedResultID = nil
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.runSearch(query: newQuery)
        }
    }

    private func runSearch(query: String) async {
        guard !Task.isCancelled else { return }

        await withTaskGroup(of: (String, [SearchResult]).self) { group in
            for provider in providers {
                group.addTask {
                    let results = await provider.search(query: query)
                    return (provider.providerID, results)
                }
            }

            var resultsByProvider: [String: [SearchResult]] = [:]
            for await (providerID, results) in group {
                guard !Task.isCancelled else { return }
                resultsByProvider[providerID] = results
                publishSections(resultsByProvider: resultsByProvider)
            }
        }
    }

    private func publishSections(resultsByProvider: [String: [SearchResult]]) {
        var newSections: [SearchSection] = []
        for provider in providers {
            guard let results = resultsByProvider[provider.providerID], !results.isEmpty else { continue }
            let sorted = results.sorted { $0.score > $1.score }
            newSections.append(SearchSection(id: provider.providerID, title: provider.sectionTitle, results: sorted))
        }
        sections = newSections
        autoSelectFirstResultIfNeeded()
    }

    private func autoSelectFirstResultIfNeeded() {
        let flat = flattenedResults
        guard !flat.isEmpty else {
            selectedResultID = nil
            return
        }
        if selectedResultID == nil || !flat.contains(where: { $0.id == selectedResultID }) {
            lastSelectionWasKeyboard = true
            selectedResultID = flat.first?.id
        }
    }
}
