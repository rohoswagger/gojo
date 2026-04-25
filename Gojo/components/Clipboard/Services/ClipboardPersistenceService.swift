import Foundation

final class ClipboardPersistenceService {
    static let shared = ClipboardPersistenceService()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let fileManager = FileManager.default
        let appSupport = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let directory = appSupport
            .appendingPathComponent("Gojo", isDirectory: true)
            .appendingPathComponent("Clipboard", isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        fileURL = directory.appendingPathComponent("history.json")
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? decoder.decode([ClipboardItem].self, from: data) else {
            return []
        }
        return items
    }

    func save(_ items: [ClipboardItem]) {
        do {
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ClipboardPersistenceService.save failed: %@", error.localizedDescription)
        }
    }
}
