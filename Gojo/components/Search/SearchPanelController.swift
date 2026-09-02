//
//  SearchPanelController.swift
//  Gojo
//
//  Owns the standalone, Spotlight-style floating search panel. Replaces the
//  old in-notch Search tab: this is a borderless, non-activating NSPanel
//  positioned above the screen containing the mouse, independent of any
//  notch window.
//

import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that hosts `SearchPanelView`. Mirrors
/// the level/collectionBehavior conventions of `GojoWindow` so it layers
/// consistently with the rest of the app's floating surfaces.
private final class SearchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SearchPanelLayout.width,
                height: SearchPanelLayout.headerHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .mainMenu + 3
        animationBehavior = .none
        collectionBehavior = SearchPanelSpacePolicy.collectionBehavior
        isReleasedWhenClosed = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchPanelController: NSObject {
    static let shared = SearchPanelController()

    private var panel: SearchPanel?
    private var resignKeyObserver: NSObjectProtocol?
    private var searchHeightCancellable: AnyCancellable?
    private var resizeQueue = SearchPanelResizeQueue()

    /// Incremented on every hide() call; a hide's fade-completion closure
    /// captures its generation and only acts if it's still current. This
    /// invalidates stale completions from a hide() that was superseded by a
    /// later show()/hide() before its fade finished.
    private var hideGeneration = 0
    /// True from the moment a hide's fade starts until its (non-stale)
    /// completion runs. Lets toggle() recognize an in-flight hide rather than
    /// racing it.
    private var isHiding = false

    private override init() {
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle() {
        if SearchPanelSpacePolicy.shouldHideOnToggle(
            isVisible: isVisible,
            isOnActiveSpace: panel?.isOnActiveSpace ?? false,
            isHiding: isHiding
        ) {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panel = panelOrMake()

        // Invalidate any pending hide completion and cancel the in-flight
        // hide state so a reopen mid-fade behaves cleanly.
        isHiding = false
        hideGeneration += 1
        resizeQueue.cancelPending()

        let screen = screenContainingMouse()
        positionPanel(
            panel,
            on: screen,
            contentHeight: SearchStateViewModel.shared.panelHeight
        )

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        if reduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
            }
        }

        SearchStateViewModel.shared.requestSearchFocus()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }

        hideGeneration += 1
        let generation = hideGeneration
        resizeQueue.cancelPending()

        if reduceMotion {
            isHiding = true
            panel.orderOut(nil)
            SearchStateViewModel.shared.reset()
            isHiding = false
            return
        }

        isHiding = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            SearchStateViewModel.shared.reset()
            self.isHiding = false
        })
    }

    func scheduleContentHeightUpdate(_ contentHeight: CGFloat) {
        guard panel?.isVisible == true, !isHiding else { return }
        guard resizeQueue.enqueue(contentHeight) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.applyPendingContentHeight()
        }
    }

    private func applyPendingContentHeight() {
        guard let contentHeight = resizeQueue.takePendingHeight() else { return }
        guard let panel, panel.isVisible, !isHiding else { return }
        positionPanel(
            panel,
            on: panel.screen ?? screenContainingMouse(),
            contentHeight: contentHeight
        )
    }

    private func panelOrMake() -> SearchPanel {
        if let panel {
            return panel
        }

        let panel = SearchPanel()
        let hostingView = NSHostingView(rootView: SearchPanelView())
        SearchPanelHostingPolicy.configure(hostingView)
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = SearchPanelLayout.cornerRadius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard SearchPanelSpacePolicy.shouldHideAfterResigningKey(
                    isOnActiveSpace: panel.isOnActiveSpace
                ) else {
                    return
                }
                self.hide()
            }
        }

        let search = SearchStateViewModel.shared
        searchHeightCancellable = Publishers.CombineLatest3(
            search.$query,
            search.$isSearching,
            search.$sections
        )
            .map { query, isSearching, sections in
                let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let metrics = sections.map { section in
                    SearchPanelLayout.SectionMetrics(
                        resultCount: section.results.count,
                        usesCalculatorRow: section.results.count == 1
                            && section.results[0].kind == .calculator
                    )
                }
                return SearchPanelLayout.panelHeight(
                    hasQuery: hasQuery,
                    isSearching: isSearching,
                    sections: metrics
                )
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] contentHeight in
                self?.scheduleContentHeightUpdate(contentHeight)
            }

        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen, contentHeight: CGFloat) {
        let frame = SearchPanelLayout.panelFrame(
            visibleFrame: screen.visibleFrame,
            contentHeight: contentHeight
        )
        panel.setFrame(frame, display: true, animate: false)
    }

    private func screenContainingMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
