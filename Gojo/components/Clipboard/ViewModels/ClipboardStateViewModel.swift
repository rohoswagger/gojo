import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ClipboardStateViewModel: ObservableObject {
    static let shared = ClipboardStateViewModel()
    private static let hoverPreviewDelay: TimeInterval = 0.5

    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchQuery: String = ""
    @Published private(set) var historyEnabled = Defaults[.clipboardHistoryEnabled]
    @Published private(set) var maxStoredItems = Defaults[.clipboardMaxEntries]
    @Published private(set) var ignoredBundleIDs = Defaults[.clipboardIgnoredBundleIDs]
    @Published private(set) var showCopiedFlash = false
    @Published private(set) var copiedItemID: ClipboardItem.ID?
    @Published private(set) var hoveredItemID: ClipboardItem.ID?
    @Published private(set) var keepsNotchOpenOnHoverExit = false
    @Published private(set) var searchFocusRequestID = UUID()

    private let persistence = ClipboardPersistenceService.shared
    private let monitor = ClipboardMonitorService.shared
    private var collection: ClipboardCollection
    private var interactionState = ClipboardTransientInteractionState()
    private var cancellables = Set<AnyCancellable>()
    private var flashTask: Task<Void, Never>?
    private var copiedItemTask: Task<Void, Never>?
    private var hoverPreviewPanel: ClipboardHoverPreviewPanel?
    private var showPreviewWorkItem: DispatchWorkItem?
    private var hidePreviewWorkItem: DispatchWorkItem?
    private var isPointerOverHoveredRow = false
    private var isPointerOverPreviewPanel = false
    private var didStart = false

    private init() {
        let collection = ClipboardCollection(
            items: persistence.load(),
            maxStoredItems: Defaults[.clipboardMaxEntries]
        )
        self.collection = collection
        self.items = collection.orderedItems
        ClipboardImageStore.shared.pruneOrphans(
            keeping: Set(collection.orderedItems.compactMap { $0.image?.fileName })
        )
        configureMonitor()
        observeDefaults()
    }

    var isEmpty: Bool {
        filteredItems.isEmpty
    }

    var filteredItems: [ClipboardItem] {
        collection.filteredItems(matching: searchQuery)
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        configureMonitor()
        if historyEnabled {
            monitor.start()
        }
    }

    func stop() {
        monitor.stop()
        hideHoverPreview(force: true)
        flashTask?.cancel()
        flashTask = nil
        copiedItemTask?.cancel()
        copiedItemTask = nil
        copiedItemID = nil
        interactionState = ClipboardTransientInteractionState()
        didStart = false
    }

    func requestSearchFocus() {
        searchFocusRequestID = UUID()
    }

    func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general

        switch item.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(item.content, forType: .string)
        case .image:
            guard let image = item.image,
                  let data = ClipboardImageStore.shared.loadData(named: image.fileName) else {
                presentCopiedFeedback(message: "Image is no longer available")
                return
            }
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }

        monitor.syncChangeCountToCurrentPasteboard()
        presentCopiedFeedback(message: "Copied to clipboard")
        presentCopiedRowFeedback(for: item.id)
    }

    func togglePin(_ item: ClipboardItem) {
        collection.togglePin(for: item.id)
        syncItemsFromCollection()
        persistItems()
    }

    func delete(_ item: ClipboardItem) {
        if let fileName = item.image?.fileName {
            ClipboardImageStore.shared.delete(named: fileName)
        }
        collection.delete(item.id)
        syncItemsFromCollection()
        if hoveredItemID == item.id {
            hoveredItemID = nil
        }
        hideHoverPreview(force: true)
        persistItems()
    }

    func clearNonPinned() {
        for item in collection.orderedItems where !item.isPinned {
            if let fileName = item.image?.fileName {
                ClipboardImageStore.shared.delete(named: fileName)
            }
        }
        collection.clearNonPinned()
        syncItemsFromCollection()
        hoveredItemID = nil
        hideHoverPreview(force: true)
        persistItems()
    }

    func setHoveredItemID(_ id: ClipboardItem.ID?) {
        hoveredItemID = id
        interactionState.setHoveredItemID(id)
    }

    func setPointerOverHoveredRow(_ isHovering: Bool) {
        if !isHovering {
            showPreviewWorkItem?.cancel()
            showPreviewWorkItem = nil
        }
        isPointerOverHoveredRow = isHovering
        interactionState.setPointerOverHoveredRow(isHovering)
        updatePreviewVisibility()
    }

    func setPointerOverPreviewPanel(_ isHovering: Bool) {
        isPointerOverPreviewPanel = isHovering
        interactionState.setPointerOverPreviewPanel(isHovering)
        updatePreviewVisibility()
    }

    func showHoverPreview(for item: ClipboardItem, rowFrame: CGRect, windowFrame: CGRect) {
        showPreviewWorkItem?.cancel()
        hidePreviewWorkItem?.cancel()
        let panel = hoverPreviewPanel ?? ClipboardHoverPreviewPanel()
        hoverPreviewPanel = panel
        panel.onHoverChanged = { [weak self] isHovering in
            Task { @MainActor in
                self?.setPointerOverPreviewPanel(isHovering)
            }
        }

        let presentPreview = { [weak self] in
            guard let self else { return }
            panel.present(item: item, rowFrame: rowFrame, windowFrame: windowFrame)
            self.keepsNotchOpenOnHoverExit = true
        }

        if panel.isVisible {
            presentPreview()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard self.interactionState.shouldPresentPreview(for: item.id) else { return }
                presentPreview()
            }
        }
        showPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverPreviewDelay, execute: workItem)
    }

    func hideHoverPreview(force: Bool = false) {
        showPreviewWorkItem?.cancel()
        showPreviewWorkItem = nil
        hidePreviewWorkItem?.cancel()
        hoverPreviewPanel?.orderOut(nil)
        interactionState.resetPreviewHover()
        isPointerOverHoveredRow = interactionState.isPointerOverHoveredRow
        isPointerOverPreviewPanel = interactionState.isPointerOverPreviewPanel
        if force {
            keepsNotchOpenOnHoverExit = false
        } else {
            Task { @MainActor in
                self.keepsNotchOpenOnHoverExit = false
            }
        }
    }

    func addIgnoredBundleID(_ bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = Set(ignoredBundleIDs)
        next.insert(trimmed)
        Defaults[.clipboardIgnoredBundleIDs] = next.sorted()
    }

    func removeIgnoredBundleID(_ bundleID: String) {
        Defaults[.clipboardIgnoredBundleIDs] = ignoredBundleIDs.filter { $0 != bundleID }
    }

    private func configureMonitor() {
        monitor.onCapture = { [weak self] capture in
            self?.handleCapture(capture)
        }
    }

    private func observeDefaults() {
        Defaults.publisher(.clipboardHistoryEnabled)
            .sink { [weak self] change in
                guard let self else { return }
                self.historyEnabled = change.newValue
                if change.newValue {
                    self.monitor.start()
                } else {
                    self.monitor.stop()
                    self.hideHoverPreview(force: true)
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.clipboardMaxEntries)
            .sink { [weak self] change in
                guard let self else { return }
                self.collection.setMaxStoredItems(change.newValue)
                self.maxStoredItems = self.collection.maxStoredItems
                self.syncItemsFromCollection()
                self.persistItems()
            }
            .store(in: &cancellables)

        Defaults.publisher(.clipboardIgnoredBundleIDs)
            .sink { [weak self] change in
                self?.ignoredBundleIDs = change.newValue
            }
            .store(in: &cancellables)
    }

    private func handleCapture(_ capture: ClipboardCapture) {
        guard historyEnabled else { return }
        if let sourceBundleID = capture.sourceBundleID,
           sourceBundleID == Bundle.main.bundleIdentifier {
            return
        }
        if let bundleID = capture.sourceBundleID, ignoredBundleIDs.contains(bundleID) {
            return
        }

        switch capture.payload {
        case .text(let text):
            collection.registerCopy(
                content: text,
                sourceAppName: capture.sourceAppName,
                sourceBundleID: capture.sourceBundleID
            )
        case .image(let data, let sha256, let pixelWidth, let pixelHeight):
            let existingPayload = collection.orderedItems
                .first { $0.kind == .image && $0.image?.sha256 == sha256 }?
                .image
            let payload = existingPayload ?? ClipboardImagePayload(
                fileName: "\(UUID().uuidString).png",
                sha256: sha256,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                byteCount: data.count
            )
            if existingPayload == nil {
                guard ClipboardImageStore.shared.save(data, named: payload.fileName) else { return }
            }
            collection.registerCopy(
                content: "Image \(payload.dimensionsLabel)",
                kind: .image,
                image: payload,
                sourceAppName: capture.sourceAppName,
                sourceBundleID: capture.sourceBundleID
            )
        }
        syncItemsFromCollection()
        persistItems()
        presentCopiedFeedback(message: "Copied to clipboard")
    }

    private func persistItems() {
        let orderedItems = collection.orderedItems
        persistence.save(orderedItems)
        ClipboardImageStore.shared.pruneOrphans(
            keeping: Set(orderedItems.compactMap { $0.image?.fileName })
        )
    }

    private func syncItemsFromCollection() {
        items = collection.orderedItems
    }

    private func presentCopiedFeedback(message _: String) {
        showCopiedFlash = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.showCopiedFlash = false
            }
        }
    }

    private func presentCopiedRowFeedback(for id: ClipboardItem.ID) {
        copiedItemID = id
        interactionState.markCopied(id)
        copiedItemTask?.cancel()
        copiedItemTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.9))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.interactionState.clearCopied(ifMatches: id)
                if self?.interactionState.copiedItemID == nil {
                    self?.copiedItemID = nil
                }
            }
        }
    }

    private func updatePreviewVisibility() {
        if interactionState.shouldHidePreview() {
            showPreviewWorkItem?.cancel()
            showPreviewWorkItem = nil
        }
        hidePreviewWorkItem?.cancel()

        guard interactionState.shouldHidePreview() else {
            keepsNotchOpenOnHoverExit = true
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.interactionState.shouldHidePreview() {
                    self.hideHoverPreview(force: true)
                }
            }
        }
        hidePreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
    }
}
