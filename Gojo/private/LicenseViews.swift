//
//  LicenseViews.swift
//  Gojo
//
//  Lock panel shown in the notch when the trial ends, and the License tab
//  in Settings for entering and managing a license key.
//

import SwiftUI

/// Replaces the open-notch content when the app is locked.
struct NotchLockView: View {
    @ObservedObject var licenseManager = LicenseManager.shared

    private var reason: String {
        if case .locked(let reason) = licenseManager.state { return reason }
        return ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text("Gojo is locked")
                    .font(.headline)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Buy Gojo") {
                    NSWorkspace.shared.open(LicenseConfig.purchaseURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(.effectiveAccent)
                Button("Enter License…") {
                    SettingsWindowController.shared.showWindow(tab: "License")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }
}

/// The "License" tab in Settings.
struct LicenseSettings: View {
    @ObservedObject var licenseManager = LicenseManager.shared

    @State private var keyInput = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var didCopyKey = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    statusLabel
                }
                if case .licensed(let plan) = licenseManager.state {
                    if let masked = licenseManager.licenseKeyMasked {
                        HStack {
                            Text("License key")
                            Spacer()
                            Button {
                                copyLicenseKey()
                            } label: {
                                HStack(spacing: 6) {
                                    Text(masked)
                                        .font(.body.monospaced())
                                    Image(systemName: didCopyKey ? "checkmark" : "doc.on.doc")
                                        .font(.caption.weight(.semibold))
                                }
                                .foregroundStyle(didCopyKey ? Color.green : .secondary)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(licenseManager.fullLicenseKey == nil)
                            .help(didCopyKey ? "Copied" : "Copy license key")
                        }
                    }
                    if plan == .monthly {
                        if let paidThrough = licenseManager.paidThrough {
                            HStack {
                                Text("Paid through")
                                Spacer()
                                Text(paidThrough, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Manage Subscription…") {
                            openPortal()
                        }
                        .disabled(isBusy)
                        Text("Update your payment method, view invoices, or cancel. Opens your billing portal in the browser.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button("Deactivate This Mac", role: .destructive) {
                        Task {
                            isBusy = true
                            await licenseManager.deactivate()
                            isBusy = false
                        }
                    }
                    .disabled(isBusy)
                    Text("Frees up this seat so the license can be used on another Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("License")
            }

            if !isLicensed {
                Section {
                    TextField("GOJO-XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                        .font(.body.monospaced())
                        .autocorrectionDisabled()
                        .onSubmit(activate)
                    Button(isBusy ? "Activating…" : "Activate") {
                        activate()
                    }
                    .disabled(isBusy || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Activate")
                } footer: {
                    Text("Your license key was shown after checkout and emailed to you. Each license can be active on up to 3 Macs.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Buy Gojo") {
                        NSWorkspace.shared.open(LicenseConfig.purchaseURL)
                    }
                    Text("One-time lifetime purchase, or a monthly subscription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Purchase")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("License")
    }

    private var isLicensed: Bool {
        if case .licensed = licenseManager.state { return true }
        return false
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch licenseManager.state {
        case .trial(let daysRemaining):
            Text("\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in trial")
                .foregroundStyle(.orange)
        case .licensed(let plan):
            Text("\(plan.displayName) active")
                .foregroundStyle(.green)
        case .locked:
            Text("Locked")
                .foregroundStyle(.red)
        }
    }

    private func activate() {
        guard !isBusy else { return }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await licenseManager.activate(key: keyInput)
                keyInput = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func openPortal() {
        guard !isBusy else { return }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                let url = try await licenseManager.managePortalURL()
                NSWorkspace.shared.open(url)
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }

    private func copyLicenseKey() {
        guard let key = licenseManager.fullLicenseKey else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(key, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { didCopyKey = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.2)) { didCopyKey = false }
        }
    }
}

/// Onboarding step: start the free trial or activate a purchased license.
/// Matches the visual language of PermissionRequestView (badge, title,
/// description, glass primary button on the sunset background).
struct OnboardingLicenseView: View {
    @ObservedObject var licenseManager = LicenseManager.shared
    let onContinue: () -> Void

    @State private var keyInput = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var appeared = false
    @FocusState private var keyFieldFocused: Bool

    private var isLicensed: Bool {
        if case .licensed = licenseManager.state { return true }
        return false
    }

    private var hasKeyInput: Bool {
        !keyInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var fieldStroke: Color {
        if errorMessage != nil { return .red.opacity(0.7) }
        if keyFieldFocused { return Color.effectiveAccent.opacity(0.7) }
        return .white.opacity(0.12)
    }

    var body: some View {
        ZStack {
            SunsetBackground()

            VStack(spacing: 0) {
                badge
                    .padding(.top, OnboardingLayout.badgeTop)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 16) {
                    Text(isLicensed ? "You're All Set" : "Try Gojo Free")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text(isLicensed
                        ? "Your license is active on this Mac. Enjoy Gojo!"
                        : "Everything works for the next \(LicenseConfig.trialDays) days, no strings attached. Whenever you're ready, buy Gojo once or subscribe. One license covers up to 3 Macs.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }
                .padding(.top, OnboardingLayout.titleGap)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                if !isLicensed {
                    VStack(spacing: 8) {
                        Text("Already have a license?")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("GOJO-XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                            .textFieldStyle(.plain)
                            .font(.callout.monospaced())
                            .multilineTextAlignment(.center)
                            .autocorrectionDisabled()
                            .focused($keyFieldFocused)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(fieldStroke, lineWidth: 1)
                            )
                            .frame(maxWidth: 280)
                            .animation(.easeOut(duration: 0.18), value: keyFieldFocused)
                            .onSubmit(activate)
                            .onChange(of: keyInput) { _, newValue in
                                let cleaned = newValue.uppercased()
                                if cleaned != newValue { keyInput = cleaned }
                                if errorMessage != nil { errorMessage = nil }
                            }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 22)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                }

                Spacer(minLength: 16)

                if !isLicensed {
                    Text("No account needed. You can always add your license later in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 12)
                        .opacity(appeared ? 1 : 0)
                }

                HStack {
                    if isLicensed {
                        Button("Continue") { onContinue() }
                            .buttonStyle(GlassButtonStyle())
                    } else {
                        Button("Buy Gojo") {
                            NSWorkspace.shared.open(LicenseConfig.purchaseURL)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            hasKeyInput ? activate() : onContinue()
                        } label: {
                            if isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(minWidth: 110)
                            } else {
                                Text(hasKeyInput ? "Activate" : "Start Free Trial")
                                    .frame(minWidth: 110)
                            }
                        }
                        .buttonStyle(GlassButtonStyle())
                        .disabled(isBusy)
                    }
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

    private var badge: some View {
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

            Image(systemName: isLicensed ? "checkmark.seal.fill" : "sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundColor(.effectiveAccent)
        }
    }

    private func activate() {
        guard !isBusy, hasKeyInput else { return }
        errorMessage = nil
        isBusy = true
        Task {
            do {
                try await licenseManager.activate(key: keyInput)
            } catch {
                errorMessage = error.localizedDescription
            }
            isBusy = false
        }
    }
}
