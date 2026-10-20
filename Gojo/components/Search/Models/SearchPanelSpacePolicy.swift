import AppKit

enum SearchPanelSpacePolicy {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .moveToActiveSpace,
        .ignoresCycle,
    ]

    static func shouldHideAfterResigningKey(isKeyWindow: Bool) -> Bool {
        !isKeyWindow
    }

    static func shouldHideOnToggle(isVisible: Bool, isOnActiveSpace: Bool, isKeyWindow: Bool, isHiding: Bool) -> Bool {
        isVisible && isOnActiveSpace && isKeyWindow && !isHiding
    }
}
