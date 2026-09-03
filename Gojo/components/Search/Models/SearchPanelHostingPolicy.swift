import AppKit
import SwiftUI

enum SearchPanelHostingPolicy {
    static func configure<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.sizingOptions = []
    }
}
