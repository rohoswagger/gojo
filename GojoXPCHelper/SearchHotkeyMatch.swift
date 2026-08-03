//
//  SearchHotkeyMatch.swift
//  GojoXPCHelper
//
//  Pure ⌘Space match predicate, split out of SearchHotkeyTapService so it can
//  be exercised by tests with `swiftc` directly. Deliberately depends only on
//  CoreGraphics — no Foundation, no other Gojo types — so it compiles and
//  links standalone.
//

import CoreGraphics

enum SearchHotkeyMatch {
    /// Virtual keycode for the space bar (kVK_Space). Hardcoded rather than
    /// imported from Carbon/HIToolbox to keep this file dependency-free.
    static let spaceKeyCode: Int64 = 49

    /// Whether a keyDown event's keycode and masked modifier flags represent
    /// a plain ⌘Space (no Shift/Option/Control). Does not consider autorepeat
    /// or any suppression state — that's the caller's concern.
    static func isCommandSpace(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        return keyCode == spaceKeyCode && flags.intersection(relevantModifiers) == .maskCommand
    }
}
