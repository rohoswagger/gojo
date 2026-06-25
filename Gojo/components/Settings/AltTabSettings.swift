//
//  AltTabSettings.swift
//  Gojo
//
//  Settings panel for the per-display window switcher (alt-tab).
//

import Defaults
import SwiftUI

struct AltTabSettings: View {
    @Default(.altTabEnabled) var altTabEnabled
    @Default(.altTabModifier) var altTabModifier
    @Default(.altTabReverseWithShift) var altTabReverseWithShift
    @Default(.altTabCurrentDisplayOnly) var altTabCurrentDisplayOnly
    @Default(.altTabShowTitles) var altTabShowTitles

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { Defaults[.altTabEnabled] },
                    set: {
                        Defaults[.altTabEnabled] = $0
                        if $0 { AltTabManager.shared.enableFromSettings() }
                    }
                )) {
                    Text("Enable window switcher")
                }
                Text("Replaces the system ⌘-Tab and shows only windows on your active display. Requires Accessibility permission, granted via Gojo's helper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("General")
            }

            Section {
                Picker("Trigger modifier", selection: $altTabModifier) {
                    ForEach(AltTabModifierKey.allCases) { modifier in
                        Text("\(modifier.symbol)  \(modifier.rawValue)").tag(modifier)
                    }
                }
                Defaults.Toggle(key: .altTabReverseWithShift) {
                    Text("Hold ⇧ to cycle backwards")
                }
                Defaults.Toggle(key: .altTabCurrentDisplayOnly) {
                    Text("Only show windows on the active display")
                }
                Defaults.Toggle(key: .altTabShowTitles) {
                    Text("Show window titles")
                }
            } header: {
                Text("Behavior")
            } footer: {
                Text("When the trigger modifier is Command, Gojo disables the macOS app switcher while the window switcher is enabled, and restores it when disabled.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .disabled(!altTabEnabled)
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Window Switcher")
    }
}

#Preview {
    AltTabSettings()
}
