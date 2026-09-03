//
//  SearchPanelController.swift
//  Gojo
//
//  Owns the standalone, Spotlight-style floating search panel.
//

import AppKit
import Combine
import SwiftUI

private final class SearchPanel: NSPanel {
    private let acceptsKey: Bool

    init(height: CGFloat, hasShadow: Bool, acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SearchPanelLayout.width,
                height: height
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
        self.hasShadow = hasShadow
        isOpaque = false
        backgroundColor = .clear
        isMovable = false
        becomesKeyOnlyIfNeeded = !acceptsKey
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchPanelController: NSObject {
    static let shared = SearchPanelController()

    private var headerPanel: SearchPanel?
    private var surfacePanel: SearchPanel?
    private var resignKeyObserver: NSObjectProtocol?
    private var searchHeightCancellable: AnyCancellable?
    private var resizeQueue = SearchPanelResizeQueue()
    private var hideGeneration = 0
    private var isHiding = false

    private override init() {
        super.init()
    }

    var isVisible: Bool {
        headerPanel?.isVisible ?? false
    }

    func toggle() {
        if SearchPanelSpacePolicy.shouldHideOnToggle(
            isVisible: isVisible,
            isOnActiveSpace: headerPanel?.isOnActiveSpace ?? false,
            isHiding: isHiding
        ) {
            hide()
        } else {
            show()
        }
    }

    func show() {
        let panels = panelsOrMake()

        isHiding = false
        hideGeneration += 1
        resizeQueue.cancelPending()

        positionPanels(
            headerPanel: panels.header,
            surfacePanel: panels.surface,
            on: screenContainingMouse(),
            contentHeight: SearchStateViewModel.shared.panelHeight
        )

        panels.header.alphaValue = 0
        panels.surface.alphaValue = 0
        panels.surface.orderFront(nil)
        panels.header.makeKeyAndOrderFront(nil)

        if reduceMotion {
            panels.header.alphaValue = 1
            panels.surface.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panels.header.animator().alphaValue = 1
                panels.surface.animator().alphaValue = 1
            }
        }

        SearchStateViewModel.shared.requestSearchFocus()
    }

    func hide() {
        guard let headerPanel, let surfacePanel, headerPanel.isVisible else { return }

        hideGeneration += 1
        let generation = hideGeneration
        resizeQueue.cancelPending()
        isHiding = true

        if reduceMotion {
            orderOut(headerPanel: headerPanel, surfacePanel: surfacePanel)
            SearchStateViewModel.shared.reset()
            isHiding = false
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            headerPanel.animator().alphaValue = 0
            surfacePanel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, generation == self.hideGeneration else { return }
            self.orderOut(headerPanel: headerPanel, surfacePanel: surfacePanel)
            SearchStateViewModel.shared.reset()
            self.isHiding = false
        })
    }

    func scheduleContentHeightUpdate(_ contentHeight: CGFloat) {
        guard headerPanel?.isVisible == true, !isHiding else { return }
        guard resizeQueue.enqueue(contentHeight) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.applyPendingContentHeight()
        }
    }

    private func applyPendingContentHeight() {
        guard let contentHeight = resizeQueue.takePendingHeight() else { return }
        guard let headerPanel, let surfacePanel, headerPanel.isVisible, !isHiding else { return }
        positionSurfacePanel(
            surfacePanel,
            on: headerPanel.screen ?? screenContainingMouse(),
            contentHeight: contentHeight,
            animated: true
        )
    }

    private func panelsOrMake() -> (header: SearchPanel, surface: SearchPanel) {
        if let headerPanel, let surfacePanel {
            return (headerPanel, surfacePanel)
        }

        let surfacePanel = SearchPanel(
            height: SearchPanelLayout.headerHeight,
            hasShadow: true,
            acceptsKey: false
        )
        let surfaceHostingView = NSHostingView(rootView: SearchResultsSurfaceView())
        SearchPanelHostingPolicy.configure(surfaceHostingView)
        surfacePanel.contentView = surfaceHostingView
        surfacePanel.contentView?.wantsLayer = true
        surfacePanel.contentView?.layer?.cornerRadius = SearchPanelLayout.cornerRadius
        surfacePanel.contentView?.layer?.cornerCurve = .continuous
        surfacePanel.contentView?.layer?.masksToBounds = true

        let headerPanel = SearchPanel(
            height: SearchPanelLayout.headerHeight,
            hasShadow: false,
            acceptsKey: true
        )
        let headerHostingView = NSHostingView(rootView: SearchHeaderView())
        SearchPanelHostingPolicy.configure(headerHostingView)
        headerPanel.contentView = headerHostingView
        headerPanel.addChildWindow(surfacePanel, ordered: .below)

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: headerPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard SearchPanelSpacePolicy.shouldHideAfterResigningKey(
                    isOnActiveSpace: headerPanel.isOnActiveSpace
                ) else {
                    return
                }
                self.hide()
            }
        }

        observeSearchHeight()
        self.headerPanel = headerPanel
        self.surfacePanel = surfacePanel
        return (headerPanel, surfacePanel)
    }

    private func observeSearchHeight() {
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
    }

    private func positionPanels(
        headerPanel: NSPanel,
        surfacePanel: NSPanel,
        on screen: NSScreen,
        contentHeight: CGFloat
    ) {
        let surfaceFrame = SearchPanelLayout.panelFrame(
            visibleFrame: screen.visibleFrame,
            contentHeight: contentHeight
        )
        let headerFrame = SearchPanelLayout.headerPanelFrame(visibleFrame: screen.visibleFrame)
        headerPanel.setFrame(headerFrame, display: true, animate: false)
        surfacePanel.setFrame(surfaceFrame, display: true, animate: false)
    }

    private func positionSurfacePanel(
        _ surfacePanel: NSPanel,
        on screen: NSScreen,
        contentHeight: CGFloat,
        animated: Bool
    ) {
        let frame = SearchPanelLayout.panelFrame(
            visibleFrame: screen.visibleFrame,
            contentHeight: contentHeight
        )
        guard animated, !reduceMotion else {
            surfacePanel.setFrame(frame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            context.allowsImplicitAnimation = true
            surfacePanel.animator().setFrame(frame, display: true)
        }
    }

    private func orderOut(headerPanel: NSPanel, surfacePanel: NSPanel) {
        headerPanel.orderOut(nil)
        surfacePanel.orderOut(nil)
        headerPanel.alphaValue = 1
        surfacePanel.alphaValue = 1
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
