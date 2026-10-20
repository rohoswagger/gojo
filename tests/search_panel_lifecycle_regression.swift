import AppKit
import Combine
import SwiftUI

@MainActor final class SearchStateViewModel: ObservableObject {
    static let shared = SearchStateViewModel()
    @Published var query = ""
    @Published var isSearching = false
    @Published var sections: [SearchSection] = []
    var panelHeight: CGFloat { SearchPanelLayout.headerHeight }
    func requestSearchFocus() {}
    func reset() { query = ""; sections = [] }
}

struct SearchHeaderView: View {
    var body: some View { Text("Search header fixture") }
}

struct SearchResultsSurfaceView: View {
    var body: some View { Color.gray }
}

@main struct SearchPanelLifecycleRegression {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            let controller = SearchPanelController.shared
            for _ in 0..<3 {
                controller.show()
                try? await Task.sleep(for: .milliseconds(200))
                let panels = app.windows.filter { $0.frame.width == SearchPanelLayout.width }
                guard let header = panels.first(where: { $0.canBecomeKey }),
                      let surface = panels.first(where: { !$0.canBecomeKey }) else {
                    fail("Search must create its header and backing surface")
                }
                expect(surface.parent === header, "Reopened search must keep its backing surface attached below the input window")
                surface.orderFront(nil)
                let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
                let orderedIDs = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
                guard let headerIndex = orderedIDs.firstIndex(of: header.windowNumber),
                      let surfaceIndex = orderedIDs.firstIndex(of: surface.windowNumber) else {
                    fail("Both search windows must be visible")
                }
                expect(headerIndex < surfaceIndex, "The backing surface must not intercept input above the header")
                expect(header.isKeyWindow, "Search opens ready for keyboard input")
                controller.hide()
                try? await Task.sleep(for: .milliseconds(200))
                expect(!header.isVisible && !surface.isVisible, "Dismissal removes both search windows")
            }
            print("Search native panel lifecycle regressions passed")
            app.terminate(nil)
        }
        app.run()
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fail(message) }
    }

    static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
