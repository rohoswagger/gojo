import Foundation

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    var sourceAppName: String?
    var sourceBundleID: String?
    var isPinned: Bool
    var pinOrder: Int?

    init(
        id: UUID = UUID(),
        content: String,
        firstCopiedAt: Date = Date(),
        lastCopiedAt: Date = Date(),
        copyCount: Int = 1,
        sourceAppName: String?,
        sourceBundleID: String?,
        isPinned: Bool = false,
        pinOrder: Int? = nil
    ) {
        self.id = id
        self.content = content
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
        self.pinOrder = pinOrder
    }

    var normalizedContent: String {
        content.replacingOccurrences(of: "\r\n", with: "\n")
    }

    var previewLine: String {
        normalizedContent
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
            ?? normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func registerCopy(sourceAppName: String?, sourceBundleID: String?, at date: Date = Date()) {
        copyCount += 1
        lastCopiedAt = date
        if let sourceAppName, !sourceAppName.isEmpty {
            self.sourceAppName = sourceAppName
        }
        if let sourceBundleID, !sourceBundleID.isEmpty {
            self.sourceBundleID = sourceBundleID
        }
    }
}

struct ClipboardCollection {
    private(set) var items: [ClipboardItem]
    private(set) var maxStoredItems: Int

    init(items: [ClipboardItem] = [], maxStoredItems: Int = 100) {
        self.items = items
        self.maxStoredItems = max(1, maxStoredItems)
        normalizePinOrderIfNeeded()
        sortItems()
        applyEntryLimit()
    }

    var orderedItems: [ClipboardItem] {
        items
    }

    func filteredItems(matching rawQuery: String) -> [ClipboardItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }

        return items
            .compactMap { item in
                let haystacks = [
                    item.normalizedContent.lowercased(),
                    item.sourceAppName?.lowercased() ?? ""
                ]

                var score = 0
                if haystacks[0] == query { score += 300 }
                if haystacks[0].hasPrefix(query) { score += 200 }
                if haystacks[0].contains(query) { score += 100 }
                if haystacks[1].contains(query) { score += 20 }
                if item.isPinned { score += 10 }

                return score > 0 ? (item, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return Self.isOrderedBefore(lhs.0, rhs.0)
            }
            .map(\.0)
    }

    mutating func replaceItems(with items: [ClipboardItem]) {
        self.items = items
        normalizePinOrderIfNeeded()
        sortItems()
        applyEntryLimit()
    }

    mutating func setMaxStoredItems(_ value: Int) {
        maxStoredItems = max(1, value)
        applyEntryLimit()
    }

    mutating func registerCopy(
        content: String,
        sourceAppName: String?,
        sourceBundleID: String?,
        at date: Date = Date()
    ) {
        if let existingIndex = items.firstIndex(where: {
            $0.content == content
        }) {
            items[existingIndex].registerCopy(
                sourceAppName: sourceAppName,
                sourceBundleID: sourceBundleID,
                at: date
            )
        } else {
            items.append(
                ClipboardItem(
                    content: content,
                    firstCopiedAt: date,
                    lastCopiedAt: date,
                    sourceAppName: sourceAppName,
                    sourceBundleID: sourceBundleID
                )
            )
        }

        sortItems()
        applyEntryLimit()
    }

    mutating func togglePin(for id: ClipboardItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].isPinned {
            items[index].isPinned = false
            items[index].pinOrder = nil
        } else {
            items[index].isPinned = true
            items[index].pinOrder = nextPinOrder()
        }
        sortItems()
    }

    mutating func delete(_ id: ClipboardItem.ID) {
        items.removeAll { $0.id == id }
    }

    mutating func clearNonPinned() {
        items.removeAll { !$0.isPinned }
    }

    private mutating func sortItems() {
        items.sort(by: Self.isOrderedBefore(_:_:))
    }

    private static func isOrderedBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.isPinned, rhs.isPinned {
            switch (lhs.pinOrder, rhs.pinOrder) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.firstCopiedAt < rhs.firstCopiedAt
            }
        }

        return lhs.lastCopiedAt > rhs.lastCopiedAt
    }

    private mutating func applyEntryLimit() {
        while items.count > maxStoredItems {
            if let index = items.lastIndex(where: { !$0.isPinned }) {
                items.remove(at: index)
            } else {
                break
            }
        }
    }

    private mutating func normalizePinOrderIfNeeded() {
        let pinned = items.enumerated().filter { $0.element.isPinned }
        guard !pinned.isEmpty else { return }

        let orderedPinned = pinned.sorted { lhs, rhs in
            switch (lhs.element.pinOrder, rhs.element.pinOrder) {
            case let (l?, r?) where l != r:
                return l < r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }

        for (order, entry) in orderedPinned.enumerated() {
            items[entry.offset].pinOrder = order + 1
        }
    }

    private func nextPinOrder() -> Int {
        (items.compactMap(\.pinOrder).max() ?? 0) + 1
    }
}

struct ClipboardTransientInteractionState {
    var hoveredItemID: UUID?
    var isPointerOverHoveredRow = false
    var isPointerOverPreviewPanel = false
    var copiedItemID: UUID?

    mutating func setHoveredItemID(_ id: UUID?) {
        hoveredItemID = id
    }

    mutating func setPointerOverHoveredRow(_ isHovering: Bool) {
        isPointerOverHoveredRow = isHovering
    }

    mutating func setPointerOverPreviewPanel(_ isHovering: Bool) {
        isPointerOverPreviewPanel = isHovering
    }

    func shouldPresentPreview(for id: UUID) -> Bool {
        isPointerOverHoveredRow && hoveredItemID == id
    }

    func shouldHidePreview() -> Bool {
        !isPointerOverHoveredRow && !isPointerOverPreviewPanel
    }

    mutating func markCopied(_ id: UUID) {
        copiedItemID = id
    }

    mutating func clearCopied(ifMatches id: UUID) {
        if copiedItemID == id {
            copiedItemID = nil
        }
    }

    mutating func resetPreviewHover() {
        isPointerOverHoveredRow = false
        isPointerOverPreviewPanel = false
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
