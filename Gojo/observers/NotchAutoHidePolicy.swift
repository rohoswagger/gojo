import CoreGraphics

enum NotchAutoHidePolicy {
    static func shouldHide(isFullscreen: Bool, isHovering: Bool) -> Bool {
        isFullscreen && !isHovering
    }

    static func topWindowIndex(appKitWindowFrames: [CGRect], appKitScreenFrames: [CGRect], targetAppKitScreenFrame: CGRect) -> Int? {
        appKitWindowFrames.firstIndex { windowFrame in
            var owningScreenFrame: CGRect?
            var largestIntersectionArea: CGFloat = 0
            for screenFrame in appKitScreenFrames {
                let intersection = windowFrame.intersection(screenFrame)
                guard !intersection.isNull, !intersection.isEmpty else { continue }
                let area = intersection.width * intersection.height
                if area > largestIntersectionArea {
                    owningScreenFrame = screenFrame
                    largestIntersectionArea = area
                }
            }
            return owningScreenFrame == targetAppKitScreenFrame
        }
    }

    static func coversFullHeight(appKitWindowFrame: CGRect, appKitScreenFrame: CGRect, appKitVisibleFrame: CGRect, notchWidth: CGFloat) -> Bool {
        guard !appKitWindowFrame.isEmpty, !appKitVisibleFrame.isEmpty else { return false }
        let tolerance: CGFloat = 3
        let halfWidth = notchWidth / 2
        return appKitWindowFrame.minY <= appKitVisibleFrame.minY + tolerance
            && appKitWindowFrame.maxY >= appKitVisibleFrame.maxY - tolerance
            && appKitWindowFrame.minX <= appKitScreenFrame.midX - halfWidth
            && appKitWindowFrame.maxX >= appKitScreenFrame.midX + halfWidth
    }
}
