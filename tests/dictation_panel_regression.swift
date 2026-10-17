import Foundation
import CoreGraphics

@main
struct DictationPanelRegression {
    static func main() {
        let primary = DictationPanelScreen(id: "primary", visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805))
        let left = DictationPanelScreen(id: "left", visibleFrame: CGRect(x: -1920, y: -240, width: 1920, height: 1080))
        let size = DictationPanelPlacement.defaultSize
        let initial = restore(size, [primary, left], "left", "primary", [:])
        expect(initial.displayID == "left", "Session display is used for initial placement")
        expect(initial.frame == CGRect(x: -1035, y: -210, width: 150, height: 44), "Bottom center uses AppKit coordinates on a negative-origin display")

        let outside = CGRect(x: -3000, y: 1200, width: 216, height: 44)
        let clamped = DictationPanelPlacement.clamped(outside, to: left.visibleFrame)
        expect(clamped == CGRect(x: -1908, y: 784, width: 216, height: 44), "All panel edges are clamped to the visible display")
        let saved = DictationPanelPlacement.savedPosition(for: clamped, on: left)!
        expect(saved == DictationPanelSavedPosition(horizontal: 0, vertical: 1), "A completed drag saves normalized travel")

        let resizedLeft = DictationPanelScreen(id: "left", visibleFrame: CGRect(x: -1280, y: 0, width: 1280, height: 720))
        let restored = restore(size, [primary, resizedLeft], "left", "primary", ["left": saved])
        expect(restored.frame == CGRect(x: -1268, y: 664, width: 150, height: 44), "Normalized placement survives display resolution changes")
        let centered = DictationPanelSavedPosition(horizontal: 0.5, vertical: 0.5)
        let middle = restore(size, [primary], "primary", nil, ["primary": centered])
        expect(middle.frame == CGRect(x: 645, y: 450.5, width: 150, height: 44), "Normalized midpoint restores exactly")

        let disconnected = restore(size, [primary], "left", "primary", ["left": saved])
        expect(disconnected.displayID == "primary", "A disconnected display falls back to the session display")
        expect(disconnected.frame == CGRect(x: 645, y: 100, width: 150, height: 44), "Disconnected display coordinates are not applied to the fallback")

        let tiny = DictationPanelScreen(id: "tiny", visibleFrame: CGRect(x: -5, y: 8, width: 80, height: 60))
        let small = restore(size, [tiny], "tiny", nil, [:])
        expect(tiny.visibleFrame.contains(small.frame), "A tiny visible frame contains the entire fitted panel")
        expect(small.frame == CGRect(x: 7, y: 20, width: 56, height: 36), "Oversized panels shrink to the available frame")

        for invalid in [
            DictationPanelSavedPosition(horizontal: .nan, vertical: 0),
            DictationPanelSavedPosition(horizontal: .infinity, vertical: 0),
            DictationPanelSavedPosition(horizontal: -0.2, vertical: 0.5),
            DictationPanelSavedPosition(horizontal: 0.5, vertical: 1.1)
        ] {
            let result = restore(size, [primary], "primary", nil, ["primary": invalid])
            expect(result.frame == disconnected.frame, "Invalid preference values use the bottom-center default")
        }
        let malformed = DictationPanelPlacement.clamped(CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 216, height: 44), to: primary.visibleFrame)
        expect(malformed == CGRect(x: 12, y: 82, width: 216, height: 44), "Nonfinite origins are sanitized at the placement boundary")
        expect(DictationPanelPlacement.restore(size: size, screens: [], preferredDisplayID: nil, fallbackDisplayID: nil, positions: [:]) == nil, "No displays returns no placement")
        let invalidScreen = DictationPanelScreen(id: "invalid", visibleFrame: CGRect(x: 0, y: 0, width: 0, height: 0))
        expect(restore(size, [invalidScreen, primary], "invalid", nil, [:]).displayID == "primary", "Invalid display geometry is ignored")
        print("Dictation panel placement regressions passed")
    }

    private static func restore(
        _ size: CGSize,
        _ screens: [DictationPanelScreen],
        _ preferred: String?,
        _ fallback: String?,
        _ positions: [String: DictationPanelSavedPosition]
    ) -> DictationPanelPlacementResult {
        DictationPanelPlacement.restore(size: size, screens: screens, preferredDisplayID: preferred, fallbackDisplayID: fallback, positions: positions)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
