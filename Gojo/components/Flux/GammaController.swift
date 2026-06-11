//
//  GammaController.swift
//  Gojo
//
//  Applies Flux white-point scaling to all active displays via the
//  CoreGraphics gamma formula API. WindowServer reverts these settings
//  automatically when the process exits, but we restore explicitly too.
//

import CoreGraphics
import Foundation

final class GammaController {
    private(set) var isModified = false

    func apply(_ rgb: FluxRGB) {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount) == .success,
              displayCount > 0
        else { return }

        for display in displays.prefix(Int(displayCount)) {
            CGSetDisplayTransferByFormula(
                display,
                0, CGGammaValue(rgb.red), 1,
                0, CGGammaValue(rgb.green), 1,
                0, CGGammaValue(rgb.blue), 1
            )
        }
        isModified = true
    }

    func restore() {
        guard isModified else { return }
        CGDisplayRestoreColorSyncSettings()
        isModified = false
    }
}
