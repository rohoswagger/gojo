import AppKit
import SwiftUI

struct SettingsWindowCloseObserver: ViewModifier {
    weak var window: NSWindow?
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
                guard let window, let closedWindow = notification.object as? NSWindow,
                      closedWindow === window else { return }
                onClose()
            }
    }
}
