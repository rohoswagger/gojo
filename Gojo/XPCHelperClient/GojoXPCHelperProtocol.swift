//
//  GojoXPCHelperProtocol.swift
//  GojoXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol GojoXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    /// Starts (or, if already running, is a no-op for) the ⌘Space CGEvent tap
    /// that intercepts Spotlight's hotkey. Must run in this helper because the
    /// main Gojo.app is sandboxed and cannot create a global keyboard event tap
    /// even when Accessibility-trusted — only this unsandboxed helper can.
    /// `token` is a per-start random string the caller generates; it is echoed
    /// back in the toggle notification's userInfo so the app-side observer can
    /// authenticate the notification and ignore ones from other processes.
    /// Replies with whether the tap is active after the call.
    func startSearchHotkeyInterception(_ token: String, with reply: @escaping (Bool) -> Void)
    /// Stops the ⌘Space event tap started by `startSearchHotkeyInterception`.
    func stopSearchHotkeyInterception()
    /// Captures the currently focused editable text element and returns an opaque,
    /// one-shot token. Replies with `authorized`, `success`, and either `token` or
    /// a stable `error` string.
    func captureFocusedTextTarget(_ promptIfNeeded: Bool,
        preferredTarget: NSDictionary?,
        with reply: @escaping (NSDictionary) -> Void)
    /// Inserts text into a native element only when it is still focused. Browser
    /// and custom-editor replies identify the captured app and window for paste.
    /// Replies with `authorized`, `success`, `method`, and an optional `error`.
    func insertText(_ text: String, token: String, with reply: @escaping (NSDictionary) -> Void)
    func focusedWindowSnapshot(_ promptIfNeeded: Bool, with reply: @escaping (NSDictionary) -> Void)
    func setFocusedWindowFrame(_ normalFrame: NSDictionary, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    /// Replies with a dict: `{"success": Bool, "frame": NSDictionary?}` where `frame`
    /// is the window's actual resulting frame read straight back from AX (no
    /// CGWindowList lag). Absent when the move failed.
    func setWindowFrame(_ normalFrame: NSDictionary, pid: NSNumber, windowID: NSNumber?, with reply: @escaping (NSDictionary) -> Void)
    func raiseWindow(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (Bool) -> Void)
    func enumerateWindows(forScreen screenUUID: NSString?, with reply: @escaping (NSArray) -> Void)
    /// Given an array of `{"pid": NSNumber, "windowID": NSNumber}` dictionaries,
    /// replies with a dictionary mapping the windowID (as a decimal String) to the
    /// window's AX title. Windows whose title can't be read are omitted.
    func windowTitles(_ requests: NSArray, with reply: @escaping (NSDictionary) -> Void)
    /// Replies with the same `{"success", "frame"?}` dict shape as `setWindowFrame`.
    func performZoom(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (NSDictionary) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
}
