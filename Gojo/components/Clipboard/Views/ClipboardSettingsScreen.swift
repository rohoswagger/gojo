import Defaults
import SwiftUI

struct ClipboardSettingsScreen: View {
    @ObservedObject private var clipboard = ClipboardStateViewModel.shared
    @State private var newIgnoredBundleID = ""

    var body: some View {
        Form {
            Section {
                Toggle("Enable clipboard history", isOn: Binding(
                    get: { clipboard.historyEnabled },
                    set: { Defaults[.clipboardHistoryEnabled] = $0 }
                ))

                Stepper(value: Binding(
                    get: { clipboard.maxStoredItems },
                    set: { Defaults[.clipboardMaxEntries] = $0 }
                ), in: 20...250, step: 10) {
                    Text("Stored entries: \(clipboard.maxStoredItems)")
                }
            } header: {
                Text("General")
            } footer: {
                Text("When enabled, Gojo stores copied text in plain text on this Mac so it can be searched and reused from the notch.")
            }

            Section {
                if clipboard.ignoredBundleIDs.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(clipboard.ignoredBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(role: .destructive) {
                                clipboard.removeIgnoredBundleID(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    TextField("com.example.app", text: $newIgnoredBundleID)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        clipboard.addIgnoredBundleID(newIgnoredBundleID)
                        newIgnoredBundleID = ""
                    }
                    .disabled(newIgnoredBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Ignored apps")
            } footer: {
                Text("Password managers are ignored by default. Add any app that may expose tokens, secrets, or other sensitive copied text.")
            }
        }
        .navigationTitle("Clipboard")
    }
}
