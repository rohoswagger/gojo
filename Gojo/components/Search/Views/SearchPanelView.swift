import AppKit
import SwiftUI

/// Spotlight-style content for the standalone search panel. Results grow below
/// a fixed header and become scrollable once they reach the viewport cap.
struct SearchPanelView: View {
    @ObservedObject private var search = SearchStateViewModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFieldFocused: Bool

    private var trimmedQuery: String {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !search.sections.isEmpty
    }

    private var showsNoResults: Bool {
        !trimmedQuery.isEmpty && !search.isSearching && search.sections.isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            panelSurface(
                resultsViewportHeight: SearchPanelLayout.visibleResultsViewportHeight(
                    desiredHeight: search.resultsViewportHeight,
                    panelHeight: proxy.size.height
                )
            )
            .frame(width: SearchPanelLayout.width)
            .frame(height: proxy.size.height, alignment: .top)
        }
        .frame(width: SearchPanelLayout.width)
        .onAppear {
            focusSearchSoon()
        }
        .onChange(of: search.searchFocusRequestID) { _, _ in
            focusSearchSoon()
        }
    }

    private func panelSurface(resultsViewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            searchFieldRow
            resultContent(resultsViewportHeight: resultsViewportHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: SearchPanelLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SearchPanelLayout.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipped()
    }

    private var searchFieldRow: some View {
        HStack(spacing: SearchPanelLayout.headerSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
                .frame(
                    width: SearchPanelLayout.searchIconFrameSize,
                    height: SearchPanelLayout.searchIconFrameSize
                )

            TextField("Search", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .focused($searchFieldFocused)
                .onKeyPress(.downArrow) {
                    search.moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    search.moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    activateAndHide()
                    return .handled
                }
                .onKeyPress(.escape) {
                    handleEscape()
                    return .handled
                }

            ZStack {
                if search.isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.white.opacity(0.58))
                        .accessibilityHidden(true)
                }
            }
            .frame(
                width: SearchPanelLayout.progressIndicatorFrameSize,
                height: SearchPanelLayout.progressIndicatorFrameSize
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: search.isSearching
            )
        }
        .padding(.horizontal, SearchPanelLayout.headerHorizontalPadding)
        .frame(
            minWidth: 0,
            maxWidth: .infinity,
            minHeight: SearchPanelLayout.headerHeight,
            maxHeight: SearchPanelLayout.headerHeight,
            alignment: .leading
        )
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: SearchPanelLayout.dividerHeight)
    }

    @ViewBuilder
    private func resultContent(resultsViewportHeight: CGFloat) -> some View {
        Group {
            if hasResults {
                divider
                resultsArea
                    .frame(height: resultsViewportHeight)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity
                        )
                    )
                divider
                footer
            } else if showsNoResults {
                divider
                noResultsState
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.18),
            value: search.sections
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.18),
            value: showsNoResults
        )
    }

    private var resultsArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(search.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.5))
                                .padding(.horizontal, 18)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(section.results) { result in
                                if result.kind == .calculator, section.results.count == 1 {
                                    CalculatorResultRow(
                                        result: result,
                                        isSelected: search.selectedResultID == result.id
                                    )
                                    .id(result.id)
                                    .onTapGesture {
                                        activateAndHide(result: result)
                                    }
                                } else {
                                    SearchResultRow(
                                        result: result,
                                        isSelected: search.selectedResultID == result.id
                                    )
                                    .id(result.id)
                                    .onTapGesture {
                                        activateAndHide(result: result)
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            search.select(id: result.id)
                                        }
                                    }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .offset(y: 6)))
                    }
                }
                .padding(.vertical, 4)
            }
            .id(trimmedQuery)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .onChange(of: search.selectedResultID) { _, newValue in
                guard let newValue, search.lastSelectionWasKeyboard else { return }
                if reduceMotion {
                    proxy.scrollTo(newValue)
                } else {
                    withAnimation(.smooth(duration: 0.15)) {
                        proxy.scrollTo(newValue)
                    }
                }
            }
        }
    }

    private var noResultsState: some View {
        Text("No results for \u{201C}\(trimmedQuery)\u{201D}")
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: SearchPanelLayout.noResultsHeight)
    }

    private var selectedResultKind: SearchResultKind? {
        guard let selectedResultID = search.selectedResultID else { return nil }
        return search.flattenedResults.first(where: { $0.id == selectedResultID })?.kind
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Spacer()
            Group {
                hint(key: "↑↓", label: "Navigate")
                hint(key: "↩", label: selectedResultKind == .calculator ? "Copy" : "Open")
            }
            .opacity(hasResults ? 1 : 0)
            hint(key: "esc", label: "Dismiss")
        }
        .padding(.horizontal, 18)
        .frame(height: SearchPanelLayout.footerHeight)
    }

    private func hint(key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    private func activateAndHide(result: SearchResult? = nil) {
        if let result {
            result.action()
        } else {
            guard search.activateSelection() else { return }
        }
        SearchPanelController.shared.hide()
    }

    private func handleEscape() {
        if !search.query.isEmpty {
            search.query = ""
        } else {
            SearchPanelController.shared.hide()
        }
    }

    private func focusSearchSoon() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            searchFieldFocused = true
        }
    }

}

private struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    @State private var icon: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = result.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.52))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : .clear)
        )
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .task(id: result.id) {
            let resolvedIcon = await Task.detached(priority: .userInitiated) {
                result.iconProvider()
            }.value
            icon = resolvedIcon
        }
    }
}

private struct CalculatorResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    private var expression: String {
        result.title.components(separatedBy: " = ").first ?? result.title
    }

    private var value: String {
        guard let range = result.title.range(of: " = ") else { return result.title }
        return String(result.title[range.upperBound...])
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expression)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 12)
            Text("↩ Copy")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : .clear)
        )
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}
