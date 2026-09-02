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
import SwiftUI

/// Borderless, non-activating panel that hosts `SearchPanelView`. Mirrors
/// the level/collectionBehavior conventions of `GojoWindow` so it layers
/// consistently with the rest of the app's floating surfaces.
private final class SearchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .mainMenu + 3
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

    /// Panel width is fixed; only height animates with content.
    private static let panelWidth: CGFloat = 680
    /// Top edge sits this fraction down from the screen's visible top.
    private static let topInsetFraction: CGFloat = 0.28
    private static let minHeight: CGFloat = 56

    private var panel: SearchPanel?
    private var resignKeyObserver: NSObjectProtocol?

    /// Incremented on every hide() call; a hide's fade-completion closure
    /// captures its generation and only acts if it's still current. This
    /// invalidates stale completions from a hide() that was superseded by a
    /// later show()/hide() before its fade finished.
    private var hideGeneration = 0
    /// True from the moment a hide's fade starts until its (non-stale)
    /// completion runs. Lets toggle() and updateContentHeight() recognize an
    /// in-flight hide rather than racing it.
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

        let screen = screenContainingMouse()
        positionPanel(panel, on: screen, height: Self.minHeight, animated: false)

        panel.alphaValue = 0
        centerAnchorPoint(of: panel)
        panel.contentView?.layer?.setAffineTransform(
            CGAffineTransform(scaleX: 0.98, y: 0.98)
        )

        panel.makeKeyAndOrderFront(nil)

        if reduceMotion {
            panel.alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(.identity)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
                panel.contentView?.layer?.setAffineTransform(.identity)
            }
        }

        SearchStateViewModel.shared.requestSearchFocus()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }

        hideGeneration += 1
        let generation = hideGeneration

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

    /// Called by the SwiftUI content whenever its measured height changes.
    /// Keeps the panel's top edge fixed while animating the frame.
    func updateContentHeight(_ contentHeight: CGFloat) {
        guard let panel, panel.isVisible, !isHiding else { return }
        let screen = panel.screen ?? screenContainingMouse()
        let clamped = max(Self.minHeight, contentHeight)
        positionPanel(panel, on: screen, height: clamped, animated: true)
    }

    private func panelOrMake() -> SearchPanel {
        if let panel {
            return panel
        }

        let panel = SearchPanel()
        panel.contentView = NSHostingView(rootView: SearchPanelView())
        panel.contentView?.wantsLayer = true

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

        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel, on screen: NSScreen, height: CGFloat, animated: Bool) {
        let visibleFrame = screen.visibleFrame
        let width = Self.panelWidth
        let x = visibleFrame.minX + (visibleFrame.width - width) / 2
        // AppKit's origin is bottom-left, so the top edge is computed from
        // the top of the visible frame minus the inset, then the origin.y
        // is derived by subtracting the panel height from that top edge.
        let topEdgeY = visibleFrame.maxY - visibleFrame.height * Self.topInsetFraction
        let y = topEdgeY - height

        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        guard animated, !reduceMotion else {
            panel.setFrame(newFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }
    }

    /// Re-anchors the content layer to its center so the show() scale
    /// transform grows from the middle of the panel rather than from the
    /// layer's default bottom-left anchor point. Changing `anchorPoint`
    /// shifts `position`, so `position` is recomputed to the bounds'
    /// midpoint to compensate and keep the layer visually in place.
    private func centerAnchorPoint(of panel: NSPanel) {
        guard let layer = panel.contentView?.layer else { return }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
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
