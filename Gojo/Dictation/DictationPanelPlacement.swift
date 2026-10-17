import Foundation
import CoreGraphics

struct DictationPanelScreen: Equatable {
    let id: String
    let visibleFrame: CGRect
}

struct DictationPanelSavedPosition: Codable, Equatable {
    let horizontal: Double
    let vertical: Double

    var isValid: Bool {
        horizontal.isFinite && vertical.isFinite
            && (0...1).contains(horizontal) && (0...1).contains(vertical)
    }
}

struct DictationPanelPlacementResult: Equatable {
    let displayID: String
    let frame: CGRect
}

enum DictationPanelPlacement {
    static let defaultSize = CGSize(width: 150, height: 44)
    static let edgeMargin: CGFloat = 12
    static let bottomGap: CGFloat = 18

    static func restore(
        size: CGSize,
        screens: [DictationPanelScreen],
        preferredDisplayID: String?,
        fallbackDisplayID: String?,
        positions: [String: DictationPanelSavedPosition]
    ) -> DictationPanelPlacementResult? {
        let available = screens.filter { valid($0.visibleFrame) }
        guard let screen = available.first(where: { $0.id == preferredDisplayID })
            ?? available.first(where: { $0.id == fallbackDisplayID })
            ?? available.first else { return nil }
        let bounds = usableFrame(screen.visibleFrame)
        let fittedSize = fitted(size, inside: bounds)
        let position = positions[screen.id].flatMap { $0.isValid ? $0 : nil }
        let origin: CGPoint
        if let position {
            origin = CGPoint(
                x: bounds.minX + max(0, bounds.width - fittedSize.width) * position.horizontal,
                y: bounds.minY + max(0, bounds.height - fittedSize.height) * position.vertical
            )
        } else {
            origin = CGPoint(
                x: bounds.midX - fittedSize.width / 2,
                y: min(bounds.minY + bottomGap, bounds.maxY - fittedSize.height)
            )
        }
        return DictationPanelPlacementResult(
            displayID: screen.id,
            frame: clamped(CGRect(origin: origin, size: fittedSize), to: screen.visibleFrame)
        )
    }

    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        guard valid(visibleFrame) else { return .zero }
        let bounds = usableFrame(visibleFrame)
        let size = fitted(frame.size, inside: bounds)
        let x = frame.origin.x.isFinite ? frame.origin.x : bounds.minX
        let y = frame.origin.y.isFinite ? frame.origin.y : bounds.minY
        return CGRect(
            x: min(max(x, bounds.minX), bounds.maxX - size.width),
            y: min(max(y, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    static func savedPosition(for frame: CGRect, on screen: DictationPanelScreen) -> DictationPanelSavedPosition? {
        guard valid(screen.visibleFrame), valid(frame) else { return nil }
        let bounds = usableFrame(screen.visibleFrame)
        let frame = clamped(frame, to: screen.visibleFrame)
        let horizontalTravel = bounds.width - frame.width
        let verticalTravel = bounds.height - frame.height
        return DictationPanelSavedPosition(
            horizontal: horizontalTravel > 0 ? Double((frame.minX - bounds.minX) / horizontalTravel) : 0.5,
            vertical: verticalTravel > 0 ? Double((frame.minY - bounds.minY) / verticalTravel) : 0
        )
    }

    private static func usableFrame(_ visibleFrame: CGRect) -> CGRect {
        visibleFrame.insetBy(
            dx: min(edgeMargin, max(0, (visibleFrame.width - 1) / 2)),
            dy: min(edgeMargin, max(0, (visibleFrame.height - 1) / 2))
        )
    }

    private static func fitted(_ size: CGSize, inside bounds: CGRect) -> CGSize {
        CGSize(
            width: min(bounds.width, size.width.isFinite ? max(1, size.width) : defaultSize.width),
            height: min(bounds.height, size.height.isFinite ? max(1, size.height) : defaultSize.height)
        )
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }
}
