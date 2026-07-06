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

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    statusLabel
                }
                if case .licensed = licenseManager.state {
                    if let masked = licenseManager.licenseKeyMasked {
                        HStack {
                            Text("License key")
                            Spacer()
                            Text(masked)
                                .foregroundStyle(.secondary)
                                .font(.body.monospaced())
                        }
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
            Text("Trial — \(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left")
                .foregroundStyle(.orange)
        case .licensed(let plan):
            Text("\(plan.displayName) — active")
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
}
