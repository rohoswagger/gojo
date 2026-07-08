//
//  PermissionsRequestView.swift
//  Gojo
//
//  Created by Alexander on 2025-06-23.
//

import AppKit
import QuartzCore
import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let onAllow: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            SunsetBackground()

            VStack(spacing: 0) {
                iconBadge
                    .padding(.top, OnboardingLayout.badgeTop)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.title)
                        .fontWeight(.semibold)

                    Text(description)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if let privacyNote = privacyNote {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.secondary)
                            Text(privacyNote)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top, OnboardingLayout.titleGap)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Spacer(minLength: 24)

                HStack {
                    Button("Not Now") { onSkip() }
                        .buttonStyle(.bordered)
                    Button("Allow Access") { onAllow() }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.bottom, OnboardingLayout.actionsBottom)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.effectiveAccent.opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 70
                    )
                )
                .frame(width: 150, height: 150)

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.effectiveAccent.opacity(0.35), lineWidth: 1))
                .frame(width: 96, height: 96)

            icon
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 38)
                .foregroundColor(.effectiveAccent)
        }
    }
}

/// Onboarding step that grants Accessibility. The step screen explains *why*,
/// then hands off to a floating "drag companion" (see `AccessibilityDragPanel`)
/// that anchors beneath the System Settings window. Once the companion is up,
/// the onboarding window steps aside so the companion is the sole focus; it
/// carries its own skip control and auto-advances the moment access is granted.
struct AccessibilityRequestView: View {
    let onGranted: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var handedOff = false
    @State private var pollTask: Task<Void, Never>?
    @State private var host: NSWindow?
    @StateObject private var companion = AccessibilityDragPanel()

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    var body: some View {
        ZStack {
            SunsetBackground()

            VStack(spacing: 0) {
                iconBadge
                    .padding(.top, OnboardingLayout.badgeTop)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 16) {
                    Text("Give Gojo the reach")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text("Gojo needs Accessibility to snap your windows and replace the volume and brightness HUDs. We'll open Settings so you can switch it on.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.secondary)
                        Text("Only used for window control and the HUDs.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal)
                }
                .padding(.top, OnboardingLayout.titleGap)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Spacer(minLength: 24)

                HStack {
                    Button("Not Now") { finish(onSkip) }
                        .buttonStyle(.bordered)
                    Button("Open Settings") { handOff() }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.bottom, OnboardingLayout.actionsBottom)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WindowReader { host = $0 })
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) { appeared = true }
            companion.onSkip = { finish(onSkip) }
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
            companion.hide()
            stepAside(false)
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.effectiveAccent.opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 70
                    )
                )
                .frame(width: 150, height: 150)

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.effectiveAccent.opacity(0.35), lineWidth: 1))
                .frame(width: 96, height: 96)

            Image(systemName: "hand.raised.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.effectiveAccent)
        }
    }

    /// Open Settings and hand the flow to the floating companion, fading the
    /// onboarding window out so the companion stands alone.
    private func handOff() {
        guard !handedOff else { return }
        handedOff = true
        NSWorkspace.shared.open(Self.settingsURL)
        stepAside(true)
        companion.show()
    }

    private func stepAside(_ aside: Bool) {
        guard let host else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            host.animator().alphaValue = aside ? 0 : 1
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                    let celebrate = companion.isVisible
                    await MainActor.run { if celebrate { companion.markGranted() } }
                    // Brief flash of the confirmation, then advance snappily.
                    try? await Task.sleep(for: .seconds(celebrate ? 0.45 : 0.05))
                    finish(onGranted)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        pollTask?.cancel()
        companion.hide()
        stepAside(false)
        // System Settings is frontmost after granting — pull the onboarding
        // window back to the foreground so the flow continues in view.
        NSApp.activate(ignoringOtherApps: true)
        host?.makeKeyAndOrderFront(nil)
        action()
    }
}

/// A compact, fixed-position floating bar pinned to the bottom-center of the
/// main screen. It presents the draggable Gojo icon as a narrow horizontal row
/// the user drags up into the Accessibility list. (macOS no longer exposes other
/// apps' window frames without Screen Recording, so we don't chase the Settings
/// window — a stable, predictable spot is both simpler and more reliable.)
@MainActor
final class AccessibilityDragPanel: ObservableObject {
    enum Phase { case dragging, granted }

    @Published var phase: Phase = .dragging
    @Published var showTip = false

    var onSkip: (() -> Void)?
    private(set) var isVisible = false

    private var panel: NSPanel?
    private var tipTimer: Timer?

    private static let size = NSSize(width: 360, height: 76)

    func show() {
        phase = .dragging
        showTip = false
        if panel == nil { build() }
        position()
        guard let panel else { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        isVisible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        startTipTimer()
    }

    func markGranted() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { phase = .granted }
        tipTimer?.invalidate()
    }

    func hide() {
        tipTimer?.invalidate(); tipTimer = nil
        isVisible = false
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.26
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    func requestSkip() { onSkip?() }

    private func build() {
        let hosting = NSHostingView(rootView: DragPanelView(panel: self))
        hosting.frame = NSRect(origin: .zero, size: Self.size)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = false  // fixed; must not swallow the icon drag
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        panel = p
    }

    /// Fixed bottom-center of the main screen, clear of the Dock.
    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let sz = Self.size
        let vis = screen.visibleFrame
        let x = vis.midX - sz.width / 2
        let y = vis.minY + 26
        panel.setFrame(NSRect(x: x, y: y, width: sz.width, height: sz.height), display: true)
    }

    private func startTipTimer() {
        tipTimer?.invalidate()
        tipTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .dragging else { return }
                withAnimation(.easeInOut(duration: 0.3)) { self.showTip = true }
            }
        }
    }
}

private struct DragPanelView: View {
    @ObservedObject var panel: AccessibilityDragPanel
    @State private var lift = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let accent = Color.effectiveAccent

    var body: some View {
        HStack(spacing: 14) {
            handle

            VStack(alignment: .leading, spacing: 2) {
                Text(granted ? "You're all set" : "Drag Gojo into the list")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !granted {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 26)
                Button { panel.requestSkip() } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(width: 360, height: 76)
        .background(background)
        // The whole bar (everything but the Skip control) is the drag handle:
        // grab anywhere and the Gojo icon lifts to the cursor.
        .overlay(alignment: .leading) {
            if !granted {
                DraggableAppIcon().frame(width: 284, height: 76)
            }
        }
    }

    private var granted: Bool { panel.phase == .granted }

    private var subtitle: String {
        if granted { return "Accessibility on — continuing…" }
        return panel.showTip ? "Or click ＋ in the list, then pick Gojo." : "Drop it onto the list above."
    }

    // Echoes the onboarding `SunsetBackground`: the same cool-slate base warmed
    // by soft sunset glows, so the floating bar reads as part of the same flow.
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return shape
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.115, green: 0.125, blue: 0.180),
                        Color(red: 0.055, green: 0.060, blue: 0.090),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RadialGradient(colors: [Color.sunsetPeach.opacity(0.16), .clear],
                               center: .bottomTrailing, startRadius: 0, endRadius: 220)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
            )
            .overlay(
                RadialGradient(colors: [accent.opacity(0.18), .clear],
                               center: .leading, startRadius: 0, endRadius: 150)
                    .blendMode(.plusLighter)
                    .clipShape(shape)
            )
            .overlay(shape.stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var handle: some View {
        ZStack {
            if granted {
                Circle()
                    .fill(Color.green.opacity(0.16))
                    .overlay(Circle().stroke(Color.green.opacity(0.5), lineWidth: 1))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(RadialGradient(colors: [accent.opacity(0.38), .clear],
                                         center: .center, startRadius: 2, endRadius: 34))
                    .frame(width: 66, height: 66)
                // Crisp SwiftUI-rendered icon (no AppKit image matte).
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: 46, height: 46)
                    .shadow(color: accent.opacity(0.45), radius: 9)
                    .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
                    .offset(y: (lift && !reduceMotion) ? -3 : 0)
            }
        }
        .frame(width: 56, height: 56)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { lift = true }
        }
    }
}

/// Turns the visible icon into a reliable AppKit drag source. Kept transparent
/// so the SwiftUI icon underneath renders crisply; SwiftUI's `.onDrag` doesn't
/// fire from a borderless, non-key panel, so we start the session by hand.
private struct DraggableAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> AppIconDragView { AppIconDragView() }
    func updateNSView(_ nsView: AppIconDragView, context: Context) {}
}

final class AppIconDragView: NSView, NSDraggingSource {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "Drag me into the Accessibility list"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        let url = Bundle.main.bundleURL as NSURL
        let item = NSDraggingItem(pasteboardWriter: url)
        let preview = NSApp.applicationIconImage ?? NSImage()
        // Lift the icon to wherever the grab started, so dragging from anywhere
        // on the bar puts the icon under the cursor.
        let side: CGFloat = 46
        let p = convert(event.locationInWindow, from: nil)
        let frame = NSRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
        item.setDraggingFrame(frame, contents: preview)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

private struct WindowReader: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onResolve(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onResolve(w) } }
    }
}
