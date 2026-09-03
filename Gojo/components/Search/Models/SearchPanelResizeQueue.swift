import CoreGraphics

struct SearchPanelResizeQueue {
    private(set) var pendingHeight: CGFloat?
    private(set) var isFlushScheduled = false

    mutating func enqueue(_ height: CGFloat) -> Bool {
        pendingHeight = height
        guard !isFlushScheduled else { return false }
        isFlushScheduled = true
        return true
    }

    mutating func takePendingHeight() -> CGFloat? {
        guard isFlushScheduled else { return nil }
        isFlushScheduled = false
        defer { pendingHeight = nil }
        return pendingHeight
    }

    mutating func cancelPending() {
        pendingHeight = nil
        isFlushScheduled = false
    }
}
