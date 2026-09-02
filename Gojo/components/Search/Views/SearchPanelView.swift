import AppKit
import SwiftUI

/// Spotlight-style content for the standalone search panel. Owns no window
/// state itself — `SearchPanelController` positions and animates the panel
/// this view is hosted in, driven by the height this view reports.
struct SearchPanelView: View {
    @ObservedObject private var search = SearchStateViewModel.shared
    @FocusState private var searchFieldFocused: Bool

    private var trimmedQuery: String {
        search.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasResults: Bool {
        !search.sections.isEmpty
    }

    private var showsNoResults: Bool {
        !trimmedQuery.isEmpty && search.sections.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            searchFieldRow

            if showsNoResults {
                divider
                noResultsState
            } else if hasResults {
                divider
                resultsArea
                divider
                footer
            }
        }
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height) { _, newHeight in
                        SearchPanelController.shared.updateContentHeight(newHeight)
                    }
                    .onAppear {
                        SearchPanelController.shared.updateContentHeight(proxy.size.height)
                    }
            }
        )
        .onAppear {
            focusSearchSoon()
        }
        .onChange(of: search.searchFocusRequestID) { _, _ in
            focusSearchSoon()
        }
    }

    private var searchFieldRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))

            TextField("Search", text: $search.query)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white)
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
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
    }

    private var resultsArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(search.sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.4))
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
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 420)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: search.selectedResultID) { _, newValue in
                guard let newValue, search.lastSelectionWasKeyboard else { return }
                withAnimation(.smooth(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var noResultsState: some View {
        Text("No results for \u{201C}\(trimmedQuery)\u{201D}")
            .font(.system(size: 13))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 60)
    }

    private var selectedResultKind: SearchResultKind? {
        guard let selectedResultID = search.selectedResultID else { return nil }
        return search.flattenedResults.first(where: { $0.id == selectedResultID })?.kind
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Spacer()
            hint(key: "↑↓", label: "Navigate")
            hint(key: "↩", label: selectedResultKind == .calculator ? "Copy" : "Open")
            hint(key: "esc", label: "Dismiss")
        }
        .padding(.horizontal, 18)
        .frame(height: 28)
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
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : .clear)
                .padding(.horizontal, 6)
        )
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
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.14) : .clear)
                .padding(.horizontal, 6)
        )
        .contentShape(Rectangle())
    }
}
