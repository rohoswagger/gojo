//
//  AltTabSwitcherView.swift
//  Gojo
//
//  The switcher UI: a horizontal row of window cards (app icon + title) with the
//  current selection highlighted. Dark, rounded, translucent — macOS ⌘-Tab feel.
//

import SwiftUI
import Defaults

struct AltTabSwitcherView: View {
    @ObservedObject var manager = AltTabManager.shared
    @Default(.altTabShowTitles) private var showTitles

    private let cardWidth: CGFloat = 104
    private let iconSize: CGFloat = 64

    var body: some View {
        if let session = manager.session, !session.items.isEmpty {
            switcher(for: session)
                .environment(\.colorScheme, .dark)
        } else {
            EmptyView()
        }
    }

    private func switcher(for session: AltTabSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        card(item, isSelected: index == session.selectedIndex)
                            .id(item.id)
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .fixedSize()
            .animation(.easeOut(duration: 0.12), value: session.selectedIndex)
            .onChange(of: session.selectedIndex) { _, newValue in
                guard session.items.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(session.items[newValue].id, anchor: .center)
                }
            }
        }
    }

    private func card(_ item: AltTabItem, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            icon(for: item)
                .frame(width: iconSize, height: iconSize)

            if showTitles {
                Text(item.displayTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
                    .frame(width: 96)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.22) : Color.clear)
        )
        .frame(width: cardWidth)
    }

    @ViewBuilder
    private func icon(for item: AltTabItem) -> some View {
        if let nsImage = item.icon {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}
