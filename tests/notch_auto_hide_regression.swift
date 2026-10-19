import CoreGraphics

@main
struct NotchAutoHideRegression {
    static func main() {
        expect(hidden(true, false), "Fullscreen hides while the pointer is away")
        expect(!hidden(true, true), "Hover reveals a hidden notch")
        expect(hidden(true, false), "Leaving the notch hides it again")
        expect(!hidden(false, false), "Leaving fullscreen restores the notch")
        expect(!hidden(false, true), "Normal notch behavior remains visible on hover")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        expect(covers(screen, screen, visible), "Native fullscreen fills the height")
        expect(covers(visible, screen, visible), "Maximized windows fill the usable height")
        expect(covers(CGRect(x: 200, y: 72, width: 1000, height: 801), screen, visible), "Small window-manager rounding differences are accepted")
        expect(!covers(CGRect(x: 0, y: 200, width: 1440, height: 675), screen, visible), "A window missing the bottom does not hide the notch")
        expect(!covers(CGRect(x: 0, y: 70, width: 1440, height: 600), screen, visible), "A window missing the top does not hide the notch")
        expect(!covers(CGRect(x: 0, y: 70, width: 400, height: 805), screen, visible), "A full-height window beside the notch does not hide it")
        expect(!covers(CGRect(x: 710, y: 70, width: 20, height: 805), screen, visible), "A narrow window must cover the entire notch width")
        expect(!covers(.zero, screen, visible), "Empty window bounds are ignored")

        let secondary = CGRect(x: -1920, y: -240, width: 1920, height: 1080)
        let secondaryVisible = CGRect(x: -1920, y: -180, width: 1920, height: 995)
        let rightDisplay = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let screenFrames = [screen, secondary, rightDisplay]
        expect(covers(secondaryVisible, secondary, secondaryVisible), "Negative display origins work")
        expect(!covers(visible, secondary, secondaryVisible), "A window on another display does not hide this notch")
        let frames = [visible, secondaryVisible]
        expect(topWindow(frames, screen, screenFrames) == 0, "The primary display selects its own top window")
        expect(topWindow(frames, secondary, screenFrames) == 1, "Focus on another display does not replace this display's top window")
        expect(topWindow(frames.reversed(), screen, screenFrames) == 1, "Reordering windows on another display preserves the primary window")
        expect(topWindow([CGRect(x: 50, y: 100, width: 300, height: 300), visible], screen, screenFrames) == 0, "A smaller foreground window takes precedence over a maximized background window")
        expect(topWindow([], screen, screenFrames) == nil, "A display without app windows does not auto-hide")
        let neighboringWindow = CGRect(x: 1439, y: 200, width: 700, height: 500)
        let overlappingFrames = [neighboringWindow, visible]
        let primaryIndex = topWindow(overlappingFrames, screen, screenFrames)
        expect(primaryIndex == 1, "A one-point overlap from the neighboring display must not replace the primary display's maximized window")
        expect(topWindow(overlappingFrames, rightDisplay, screenFrames) == 0, "The mostly neighboring window belongs to the neighboring display")
        expect(hidden(covers(overlappingFrames[primaryIndex!], screen, visible), false), "The primary display remains auto-hidden behind a neighboring window's sliver")
        expect(topWindow([CGRect(x: -699, y: 200, width: 700, height: 500), visible], screen, screenFrames) == 1, "A one-point overlap from a negative-origin display preserves the primary window")
        let aboveDisplay = CGRect(x: 0, y: 900, width: 1440, height: 900)
        expect(topWindow([CGRect(x: 200, y: 899, width: 700, height: 500), visible], screen, [screen, aboveDisplay]) == 1, "A one-point overlap from a vertically arranged display preserves the primary window")
        expect(topWindow([.zero, .null, CGRect(x: 5000, y: 0, width: 300, height: 300)], screen, screenFrames) == nil, "Empty and offscreen windows do not claim a display")
        expect(topWindow([visible], screen, []) == nil, "No window has an owner when no displays are available")
        let sideDock = CGRect(x: 80, y: 0, width: 1360, height: 875)
        expect(covers(CGRect(x: 620, y: 0, width: 200, height: 875), screen, sideDock), "A side Dock does not shift the notch's horizontal position")
        print("Notch auto-hide regressions passed")
    }

    static func hidden(_ fullscreen: Bool, _ hover: Bool) -> Bool {
        NotchAutoHidePolicy.shouldHide(isFullscreen: fullscreen, isHovering: hover)
    }

    static func covers(_ window: CGRect, _ screen: CGRect, _ visible: CGRect) -> Bool {
        NotchAutoHidePolicy.coversFullHeight(appKitWindowFrame: window, appKitScreenFrame: screen, appKitVisibleFrame: visible, notchWidth: 185)
    }

    static func topWindow(_ frames: [CGRect], _ target: CGRect, _ screens: [CGRect]) -> Int? {
        NotchAutoHidePolicy.topWindowIndex(appKitWindowFrames: frames, appKitScreenFrames: screens, targetAppKitScreenFrame: target)
    }

    static func expect(_ result: Bool, _ message: String) {
        guard result else { fatalError(message) }
    }
}
