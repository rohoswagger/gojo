//
//  PermissionsRequestView.swift
//  Gojo
//
//  Created by Alexander on 2025-06-23.
//

import AppKit
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

            VStack(spacing: 24) {
                iconBadge
                    .padding(.top, 32)
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
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                HStack {
                    Button("Not Now") { onSkip() }
                        .buttonStyle(.bordered)
                    Button("Allow Access") { onAllow() }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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


struct AccessibilityRequestView: View {
    let onGranted: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false
    @State private var isAuthorized = false
    @State private var openedSettings = false
    @State private var bob = false
    @State private var pollTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    var body: some View {
        ZStack {
            SunsetBackground()

            VStack(spacing: 22) {
                dragChip
                    .padding(.top, 26)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 14) {
                    Text(isAuthorized ? "Accessibility is on" : "Give Gojo the reach")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .animation(.easeInOut, value: isAuthorized)

                    Text(isAuthorized
                        ? "You're set. Window snapping and the Gojo HUD are ready to go."
                        : "Gojo needs Accessibility to snap your windows and replace the volume and brightness HUDs. Drag the Gojo icon into the list to switch it on.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                Spacer(minLength: 0)

                if !isAuthorized {
                    VStack(spacing: 14) {
                        Button {
                            openSettings()
                        } label: {
                            Label(openedSettings ? "Accessibility Settings opened" : "Open Accessibility Settings",
                                  systemImage: openedSettings ? "checkmark" : "arrow.up.forward.app")
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(openedSettings)

                        Text(openedSettings
                            ? "Now drag the Gojo icon above into the list."
                            : "Opens System Settings so you can drop Gojo in.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Button("Not now") { finish(onSkip) }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(appeared ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) { appeared = true }
            if !reduceMotion { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { bob = true } }
            startPolling()
        }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: - Draggable Gojo chip

    private var dragChip: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.effectiveAccent.opacity(0.32), .clear],
                                         center: .center, startRadius: 0, endRadius: 80))
                    .frame(width: 170, height: 170)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                    .overlay(alignment: .bottomTrailing) {
                        if isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(.white, .green)
                                .background(Circle().fill(.black.opacity(0.001)))
                                .offset(x: 4, y: 4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .offset(y: (bob && !isAuthorized) ? -6 : 0)
                    .onDrag {
                        // Vend the app bundle so dropping it into the Accessibility
                        // list adds (and enables) Gojo. Grant resolves for the helper.
                        NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider()
                    }
                    .help("Drag me into the Accessibility list")
            }
            if !isAuthorized {
                Text("Drag me")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(openedSettings ? 1 : 0.5)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isAuthorized)
    }

    // MARK: - Actions

    private func openSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
        withAnimation { openedSettings = true }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                let ok = await XPCHelperClient.shared.isAccessibilityAuthorized()
                if ok {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { isAuthorized = true }
                    }
                    try? await Task.sleep(for: .seconds(1.1))
                    finish(onGranted)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        pollTask?.cancel()
        action()
    }
}
