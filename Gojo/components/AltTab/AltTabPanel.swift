//
//  AltTabPanel.swift
//  Gojo
//
//  Borderless, non-activating floating panel that hosts the window switcher.
//  Mirrors the ClipboardHoverPreviewPanel pattern. It never becomes key/main so
//  it doesn't change the frontmost app while the user cycles — the selected
//  window is only raised on commit.
//

import AppKit
import SwiftUI

final class AltTabPanel: NSPanel {
    private let hostingView = NSHostingView(rootView: AltTabSwitcherView())

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 180),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(on screen: NSScreen) {
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let maxWidth = screen.visibleFrame.width * 0.9
        let width = min(max(fitting.width, 1), maxWidth)
        let height = max(fitting.height, 1)

        let visible = screen.visibleFrame
        let originX = visible.minX + (visible.width - width) / 2
        let originY = visible.minY + (visible.height - height) / 2

        setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
        orderFrontRegardless()
    }

    func dismiss() {
        orderOut(nil)
    }
}
