import Foundation

/// A single source of search results (calculator, apps, files, ...).
/// New providers are added by conforming to this protocol and registering
/// an instance in `SearchStateViewModel.providers` — no other provider
/// needs to change.
protocol SearchProvider {
    /// Stable identifier for the provider, used for section identity.
    var providerID: String { get }
    /// Section title shown in the UI when this provider has results.
    var sectionTitle: String { get }
    /// Returns results for `query`. Implementations must be cancellation
    /// aware where the work is expensive (honor `Task.isCancelled`).
    func search(query: String) async -> [SearchResult]
}
