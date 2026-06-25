//
//  TabSelectionView.swift
//  Gojo
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Clipboard", icon: "doc.on.clipboard.fill", view: .clipboard),
    TabModel(label: "Windows", icon: "macwindow", view: .windows),
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = GojoViewCoordinator.shared
    @Default(.shelfEnabled) var shelfEnabled
    @Default(.clipboardHistoryEnabled) var clipboardHistoryEnabled
    @Namespace var animation

    /// Only show tabs whose feature is enabled in Settings.
    private var visibleTabs: [TabModel] {
        tabs.filter { tab in
            switch tab.view {
            case .shelf: return shelfEnabled
            case .clipboard: return clipboardHistoryEnabled
            default: return true
            }
        }
    }

    /// If the current tab was just disabled, fall back to Home.
    private func ensureValidTab() {
        if !visibleTabs.contains(where: { $0.view == coordinator.currentView }) {
            coordinator.currentView = .home
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
        .onAppear { ensureValidTab() }
        .onChange(of: shelfEnabled) { _, _ in ensureValidTab() }
        .onChange(of: clipboardHistoryEnabled) { _, _ in ensureValidTab() }
    }
}

#Preview {
    GojoHeader().environmentObject(GojoViewModel())
}
