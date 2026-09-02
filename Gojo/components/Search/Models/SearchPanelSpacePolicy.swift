import AppKit

enum SearchPanelSpacePolicy {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .moveToActiveSpace,
        .ignoresCycle,
    ]

    static func shouldHideAfterResigningKey(isOnActiveSpace: Bool) -> Bool {
        isOnActiveSpace
    }

    static func shouldHideOnToggle(isVisible: Bool, isOnActiveSpace: Bool, isHiding: Bool) -> Bool {
        isVisible && isOnActiveSpace && !isHiding
    }
}
