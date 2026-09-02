//
//  GojoXPCHelper.swift
//  GojoXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics
import AppKit
import os.log

/// Lightweight window-management diagnostics. Capture together with the main
/// app's logs via:
///   /usr/bin/log stream --predicate 'subsystem BEGINSWITH "rohoswagger.gojo"' --style compact
private let gojoHelperDebugLog = OSLog(subsystem: "rohoswagger.gojo.helper", category: "debug")
private func helperDebug(_ message: String) {
    os_log("%{public}@", log: gojoHelperDebugLog, type: .default, "[GOJO-HELPER] " + message)
}

private enum CapturedTextTargetKind: Equatable {
    case accessibility
    case applicationPaste
    case applicationUnicode
}

private struct CapturedTextTarget {
    let element: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID?
    let displayID: CGDirectDisplayID?
    let allowsPasteFallback: Bool
    let kind: CapturedTextTargetKind
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]
    let isComplete: Bool

    init(pasteboard: NSPasteboard) {
        var capturedItems: [[NSPasteboard.PasteboardType: Data]] = []
        var capturedEveryType = true
        for item in pasteboard.pasteboardItems ?? [] {
            var capturedItem: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    capturedEveryType = false
                    continue
                }
                capturedItem[type] = data
            }
            capturedItems.append(capturedItem)
        }
        items = capturedItems
        isComplete = capturedEveryType
    }

    @discardableResult
    func restore(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        guard !items.isEmpty else { return true }

        let restoredItems = items.map { storedItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in storedItem {
                item.setData(data, forType: type)
            }
            return item
        }
        return pasteboard.writeObjects(restoredItems)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

class GojoXPCHelper: NSObject, GojoXPCHelperProtocol {
    private enum TextTargetResolution {
        case editable(AXUIElement, allowsPasteFallback: Bool)
        case secure
        case nonEditable
    }

    private var activationObserver: Any?
    private var lastWindowTargetApplication: NSRunningApplication?
    private var capturedTextTargets: [String: CapturedTextTarget] = [:]

    private static let pasteKeyCode: CGKeyCode = 9
    private static let transientPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )
    private static let protectedContentAttribute = "AXContainsProtectedContent"
    private static let isFocusedAttribute = kAXFocusedAttribute as String

    override init() {
        super.init()

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.rememberTargetApplicationIfNeeded(app)
        }

        if let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            rememberTargetApplicationIfNeeded(frontmostApplication)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }

    @objc func startSearchHotkeyInterception(_ token: String, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            reply(SearchHotkeyTapService.shared.start(token: token))
        }
    }

    @objc func stopSearchHotkeyInterception() {
        DispatchQueue.main.async {
            SearchHotkeyTapService.shared.stop()
        }
    }

    @objc func captureFocusedTextTarget(
        _ promptIfNeeded: Bool,
        preferredTarget: NSDictionary?,
        with reply: @escaping (NSDictionary) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                reply([
                    "authorized": false,
                    "success": false,
                    "error": "helperUnavailable",
                ])
                return
            }

            // A new capture attempt supersedes every earlier destination, even
            // when the new focus is invalid or authorization was revoked.
            self.capturedTextTargets.removeAll(keepingCapacity: true)
            guard self.ensureAccessibilityAuthorizationSync(promptIfNeeded: promptIfNeeded) else {
                reply(self.textCaptureFailure(authorized: false, error: "permissionMissing"))
                return
            }
            let topmostApplication = self.topmostTargetApplication()
            let focusedElements = self.focusedTextTargetCandidates(
                preferredApplication: topmostApplication
            )
            let preferredApplicationTarget = preferredTarget.flatMap(
                self.applicationPasteTarget(from:)
            )
            if let preferredApplicationTarget,
               WindowTargetResolver.shouldUsePreferredApplicationPasteTarget(
                   preferredPID: preferredApplicationTarget.pid,
                   focusedCandidatePIDs: focusedElements.compactMap(self.elementPID)
               ) {
                let token = UUID().uuidString
                self.capturedTextTargets[token] = preferredApplicationTarget
                helperDebug(
                    "captureFocusedTextTarget using main-app application paste target"
                        + " pid=\(preferredApplicationTarget.pid)"
                        + " windowID=\(preferredApplicationTarget.windowID.map { String($0) } ?? "none")"
                )
                var captureReply: [String: Any] = [
                    "authorized": true,
                    "success": true,
                    "token": token,
                    "pid": NSNumber(value: preferredApplicationTarget.pid),
                    "windowID": NSNumber(value: preferredApplicationTarget.windowID ?? 0),
                ]
                if let displayID = preferredApplicationTarget.displayID {
                    captureReply["displayID"] = NSNumber(value: displayID)
                }
                reply(NSDictionary(dictionary: captureReply))
                return
            }
            guard !focusedElements.isEmpty else {
                let target = preferredApplicationTarget
                    ?? (preferredTarget == nil ? self.topmostApplicationPasteTarget() : nil)
                if let target {
                    let token = UUID().uuidString
                    self.capturedTextTargets[token] = target
                    helperDebug(
                        "captureFocusedTextTarget using main-app application paste target"
                            + " pid=\(target.pid)"
                            + " windowID=\(target.windowID.map { String($0) } ?? "none")"
                    )
                    var captureReply: [String: Any] = [
                        "authorized": true,
                        "success": true,
                        "token": token,
                        "pid": NSNumber(value: target.pid),
                        "windowID": NSNumber(value: target.windowID ?? 0),
                    ]
                    if let displayID = target.displayID {
                        captureReply["displayID"] = NSNumber(value: displayID)
                    }
                    reply(NSDictionary(dictionary: captureReply))
                    return
                }
                reply(self.textCaptureFailure(authorized: true, error: "noFocusedTextTarget"))
                return
            }

            for focusedElement in focusedElements {
                var focusedPID = pid_t(0)
                AXUIElementGetPid(focusedElement, &focusedPID)
                let focusedRole = self.copyString(
                    focusedElement,
                    attribute: kAXRoleAttribute as String
                ) ?? "unknown"
                let focusedSubrole = self.copyString(
                    focusedElement,
                    attribute: kAXSubroleAttribute as String
                ) ?? "none"
                helperDebug(
                    "captureFocusedTextTarget pid=\(focusedPID) role=\(focusedRole) subrole=\(focusedSubrole) selectedTextSettable=\(self.isAttributeSettable(focusedElement, attribute: kAXSelectedTextAttribute as String)) selectedRangeSettable=\(self.isAttributeSettable(focusedElement, attribute: kAXSelectedTextRangeAttribute as String)) valueSettable=\(self.isAttributeSettable(focusedElement, attribute: kAXValueAttribute as String))"
                )

                switch self.resolveEditableTextTarget(from: focusedElement) {
                case .secure:
                    reply(self.textCaptureFailure(authorized: true, error: "secureTextTarget"))
                    return
                case .nonEditable:
                    guard let target = self.applicationPasteTarget(focusedElement) else {
                        continue
                    }
                    let token = UUID().uuidString
                    self.capturedTextTargets[token] = target
                    helperDebug(
                        "captureFocusedTextTarget using application paste target"
                            + " pid=\(target.pid)"
                            + " windowID=\(target.windowID.map { String($0) } ?? "none")"
                    )
                    var captureReply: [String: Any] = [
                        "authorized": true,
                        "success": true,
                        "token": token,
                        "pid": NSNumber(value: target.pid),
                        "windowID": NSNumber(value: target.windowID ?? 0),
                    ]
                    if let displayID = target.displayID {
                        captureReply["displayID"] = NSNumber(value: displayID)
                    }
                    reply(NSDictionary(dictionary: captureReply))
                    return
                case let .editable(element, allowsPasteFallback):
                    var pid = pid_t(0)
                    guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else {
                        continue
                    }

                    let token = UUID().uuidString
                    self.capturedTextTargets[token] = CapturedTextTarget(
                        element: element,
                        pid: pid,
                        windowID: self.windowID(of: element),
                        displayID: self.frame(of: element).flatMap(self.displayID(containing:)),
                        allowsPasteFallback: allowsPasteFallback,
                        kind: .accessibility
                    )
                    var captureReply: [String: Any] = [
                        "authorized": true,
                        "success": true,
                        "token": token,
                        "pid": NSNumber(value: pid),
                    ]
                    if let windowID = self.windowID(of: element) {
                        captureReply["windowID"] = NSNumber(value: windowID)
                    }
                    if let frame = self.frame(of: element),
                       let displayID = self.displayID(containing: frame) {
                        captureReply["displayID"] = NSNumber(value: displayID)
                    }
                    reply(NSDictionary(dictionary: captureReply))
                    return
                }
            }

            if let target = preferredApplicationTarget,
               target.kind == .applicationUnicode {
                let token = UUID().uuidString
                self.capturedTextTargets[token] = target
                helperDebug(
                    "captureFocusedTextTarget using opaque application target"
                        + " pid=\(target.pid)"
                        + " windowID=\(target.windowID.map { String($0) } ?? "none")"
                )
                var captureReply: [String: Any] = [
                    "authorized": true,
                    "success": true,
                    "token": token,
                    "pid": NSNumber(value: target.pid),
                    "windowID": NSNumber(value: target.windowID ?? 0),
                ]
                if let displayID = target.displayID {
                    captureReply["displayID"] = NSNumber(value: displayID)
                }
                reply(NSDictionary(dictionary: captureReply))
                return
            }

            reply(self.textCaptureFailure(authorized: true, error: "nonEditableTarget"))
        }
    }

    @objc func insertText(
        _ text: String,
        token: String,
        with reply: @escaping (NSDictionary) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                reply([
                    "authorized": false,
                    "success": false,
                    "method": "none",
                    "error": "helperUnavailable",
                ])
                return
            }
            guard AXIsProcessTrusted() else {
                self.capturedTextTargets.removeValue(forKey: token)
                reply(self.textInsertionFailure(authorized: false, error: "permissionMissing"))
                return
            }
            guard !text.isEmpty else {
                self.capturedTextTargets.removeValue(forKey: token)
                reply(self.textInsertionFailure(authorized: true, error: "emptyText"))
                return
            }
            guard let target = self.capturedTextTargets.removeValue(forKey: token) else {
                reply(self.textInsertionFailure(authorized: true, error: "invalidToken"))
                return
            }
            if target.kind == .applicationPaste {
                guard let windowID = target.windowID else {
                    reply(self.textInsertionFailure(authorized: true, error: "focusChanged"))
                    return
                }
                let applicationPasteReply: [String: Any] = [
                    "authorized": true,
                    "success": false,
                    "method": "application-paste",
                    "verified": false,
                    "error": "applicationPasteRequired",
                    "pid": NSNumber(value: target.pid),
                    "windowID": NSNumber(value: windowID),
                ]
                reply(NSDictionary(dictionary: applicationPasteReply))
                return
            }
            if target.kind == .applicationUnicode {
                guard let windowID = target.windowID else {
                    reply(self.textInsertionFailure(authorized: true, error: "focusChanged"))
                    return
                }
                guard !self.hasSecureFocusedAncestry(for: target.pid) else {
                    reply(self.textInsertionFailure(authorized: true, error: "secureTextTarget"))
                    return
                }
                reply([
                    "authorized": true,
                    "success": false,
                    "method": "application-unicode",
                    "verified": false,
                    "error": "applicationUnicodeRequired",
                    "pid": NSNumber(value: target.pid),
                    "windowID": NSNumber(value: windowID),
                ])
                return
            }

            guard self.isStillFocused(target) else {
                reply(self.textInsertionFailure(authorized: true, error: "focusChanged"))
                return
            }

            let accessibilityExpectation = self.pasteMutationExpectation(
                text,
                into: target.element
            )
            let axResult = AXUIElementSetAttributeValue(
                target.element,
                kAXSelectedTextAttribute as CFString,
                text as CFString
            )
            if axResult == .success {
                guard let accessibilityExpectation else {
                    reply([
                        "authorized": true,
                        "success": false,
                        "method": "accessibility",
                        "verified": false,
                        "error": "axInsertionNotConfirmed",
                    ])
                    return
                }
                self.waitForAccessibilityConfirmation(
                    expectation: accessibilityExpectation,
                    target: target,
                    attemptsRemaining: 20,
                    reply: reply
                )
                return
            }

            guard target.allowsPasteFallback else {
                reply(self.textInsertionFailure(authorized: true, error: "axInsertionFailed"))
                return
            }
            self.insertWithGuardedPaste(text, target: target, reply: reply)
        }
    }

    @objc func focusedWindowSnapshot(_ promptIfNeeded: Bool, with reply: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                reply(["authorized": false, "error": "helperUnavailable"])
                return
            }

            guard self.ensureAccessibilityAuthorizationSync(promptIfNeeded: promptIfNeeded) else {
                reply(["authorized": false, "error": "permissionMissing"])
                return
            }

            guard let snapshot = self.focusedWindowSnapshotDictionary() else {
                reply(["authorized": true, "error": "noFocusedWindow"])
                return
            }

            reply(snapshot)
        }
    }

    @objc func setFocusedWindowFrame(_ normalFrame: NSDictionary, windowID: NSNumber?, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  AXIsProcessTrusted(),
                  let frame = CGRect(dictionaryRepresentation: normalFrame as CFDictionary),
                  let app = self.targetApplication() else {
                helperDebug("setFocusedWindowFrame: guard failed (untrusted, bad frame, or no target app)")
                reply(false)
                return
            }

            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let windowElement = self.bestWindowElement(
                for: appElement,
                preferredWindowID: windowID.map { CGWindowID(truncating: $0) }
            ) else {
                helperDebug("setFocusedWindowFrame: no AX window for \(app.localizedName ?? "?") windowID=\(windowID.map(String.init(describing:)) ?? "nil")")
                reply(false)
                return
            }

            let result = self.setAXFrame(frame.gojoHelperScreenFlipped, for: windowElement, pid: app.processIdentifier)
            helperDebug("setFocusedWindowFrame \(app.localizedName ?? "?") → \(result ? "ok" : "FAILED") frame=\(frame)")
            reply(result)
        }
    }

    @objc func setWindowFrame(_ normalFrame: NSDictionary, pid: NSNumber, windowID: NSNumber?, with reply: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  AXIsProcessTrusted(),
                  let frame = CGRect(dictionaryRepresentation: normalFrame as CFDictionary) else {
                helperDebug("setWindowFrame: guard failed (untrusted or bad frame)")
                reply(["success": false])
                return
            }

            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            guard let windowElement = self.windowElement(for: appElement, exactWindowID: cgID)
                ?? self.bestWindowElement(for: appElement, preferredWindowID: cgID) else {
                helperDebug("setWindowFrame: no AX window for pid=\(pidValue) windowID=\(cgID.map(String.init(describing:)) ?? "nil")")
                reply(["success": false])
                return
            }
            let success = self.setAXFrame(frame.gojoHelperScreenFlipped, for: windowElement, pid: pidValue)
            helperDebug("setWindowFrame pid=\(pidValue) windowID=\(cgID.map(String.init(describing:)) ?? "nil") → \(success ? "ok" : "FAILED") frame=\(frame)")
            reply(self.frameMutationReply(success: success, element: windowElement))
        }
    }

    @objc func performZoom(_ pid: NSNumber, windowID: NSNumber?, with reply: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply(["success": false])
                return
            }
            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            guard let windowElement = self.windowElement(for: appElement, exactWindowID: cgID)
                ?? self.bestWindowElement(for: appElement, preferredWindowID: cgID) else {
                reply(["success": false])
                return
            }

            var buttonValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(windowElement, kAXZoomButtonAttribute as CFString, &buttonValue) == .success,
                  let value = buttonValue,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else {
                reply(["success": false])
                return
            }
            let zoomButton = value as! AXUIElement
            let success = AXUIElementPerformAction(zoomButton, kAXPressAction as CFString) == .success
            reply(self.frameMutationReply(success: success, element: windowElement))
        }
    }

    /// Reply for a frame mutation: success plus the element's actual resulting
    /// frame, read straight back from AX (the source of truth we just wrote) and
    /// flipped to AppKit/normalFrame coords. Avoids CGWindowList's post-write lag.
    private func frameMutationReply(success: Bool, element: AXUIElement) -> NSDictionary {
        var dict: [String: Any] = ["success": success]
        if success, let axFrame = frame(of: element) {
            dict["frame"] = axFrame.gojoHelperScreenFlipped.dictionaryRepresentation as NSDictionary
        }
        return dict as NSDictionary
    }

    @objc func raiseWindow(_ pid: NSNumber, windowID: NSNumber?, allowApplicationFallback: Bool, with reply: @escaping (Bool) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply(false)
                return
            }
            let pidValue = pid_t(truncating: pid)
            let appElement = AXUIElementCreateApplication(pidValue)
            let cgID = windowID.map { CGWindowID(truncating: $0) }
            let exactElement = self.activationWindowElement(for: appElement, exactWindowID: cgID)
            // Callers that requested a specific window and opted out of the
            // fallback get that window or nothing; the rest keep the historical
            // "best window of the app" behaviour when the lookup misses.
            guard let element = WindowTargetResolver.windowActivationTarget(
                requestedWindowID: allowApplicationFallback ? nil : cgID,
                exactMatch: exactElement,
                fallback: self.activationFallbackElement(
                    for: appElement,
                    exactElement: exactElement,
                    windowID: cgID
                )
            ) else {
                helperDebug("raiseWindow: no window resolved for pid \(pidValue) window \(cgID.map(String.init) ?? "none")")
                reply(false)
                return
            }

            // A minimized window is still the exact window the user picked, so
            // restore it instead of failing the raise.
            if self.copyBool(element, attribute: kAXMinimizedAttribute) == true {
                AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }

            let raiseResult = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            let mainResult = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
            let focusedResult = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard raiseResult == .success || mainResult == .success || focusedResult == .success else {
                helperDebug("raiseWindow: every window operation failed for pid \(pidValue)")
                reply(false)
                return
            }

            // Foregrounding the owning process is best-effort: the picked window
            // is already raised and focused, so an app that refuses kAXFrontmost
            // must not turn a successful raise into a reported failure.
            let frontmostResult = AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            if frontmostResult != .success {
                helperDebug("raiseWindow: kAXFrontmost failed (\(frontmostResult.rawValue)) for pid \(pidValue)")
            }
            reply(true)
        }
    }

    @objc func enumerateWindows(forScreen screenUUID: NSString?, with reply: @escaping (NSArray) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply([] as NSArray)
                return
            }

            let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
            let snapshots = self.topWindowSnapshots()
            let excludedBundleIDs: Set<String> = [
                "rohoswagger.gojo",
                "rohoswagger.gojo.GojoXPCHelper",
                Bundle.main.bundleIdentifier ?? ""
            ].filter { !$0.isEmpty }.reduce(into: Set<String>()) { $0.insert($1) }

            var seen: Set<UInt32> = []
            let results: [NSDictionary] = snapshots.compactMap { snapshot -> NSDictionary? in
                guard WindowTargetResolver.isTopLevelWindow(snapshot, ownPID: ownPID) else { return nil }
                guard snapshot.bounds.width >= 200, snapshot.bounds.height >= 120 else { return nil }
                guard let app = NSRunningApplication(processIdentifier: snapshot.pid),
                      app.activationPolicy == .regular,
                      WindowTargetResolver.isTargetApplication(
                        WindowTargetApplicationSnapshot(
                            pid: app.processIdentifier,
                            bundleIdentifier: app.bundleIdentifier,
                            activationPolicy: .regular,
                            isTerminated: app.isTerminated
                        ),
                        ownPID: ownPID,
                        excludedBundleIDs: excludedBundleIDs
                      ) else { return nil }

                if let wid = snapshot.windowID {
                    guard seen.insert(wid).inserted else { return nil }
                }

                let normalFrame = snapshot.bounds.gojoHelperScreenFlipped
                let dict: [String: Any] = [
                    "pid": NSNumber(value: snapshot.pid),
                    "windowID": snapshot.windowID.map { NSNumber(value: $0) } as Any,
                    "appName": app.localizedName ?? snapshot.ownerName ?? "App",
                    "bundleIdentifier": app.bundleIdentifier ?? "",
                    "bounds": NSDictionary(dictionary: snapshot.bounds.dictionaryRepresentation as NSDictionary),
                    "normalFrame": NSDictionary(dictionary: normalFrame.dictionaryRepresentation as NSDictionary)
                ]
                return dict as NSDictionary
            }

            reply(results as NSArray)
        }
    }

    @objc func windowTitles(_ requests: NSArray, with reply: @escaping (NSDictionary) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, AXIsProcessTrusted() else {
                reply([:] as NSDictionary)
                return
            }
            var result: [String: String] = [:]
            for case let request as NSDictionary in requests {
                guard let pidNum = request["pid"] as? NSNumber,
                      let widNum = request["windowID"] as? NSNumber else { continue }
                let pid = pid_t(truncating: pidNum)
                let wid = CGWindowID(truncating: widNum)
                let appElement = AXUIElementCreateApplication(pid)
                guard let element = self.windowElement(for: appElement, exactWindowID: wid),
                      let title = self.copyString(element, attribute: kAXTitleAttribute as String),
                      !title.isEmpty else { continue }
                result[String(wid)] = title
            }
            reply(result as NSDictionary)
        }
    }

    private func windowElement(for appElement: AXUIElement, exactWindowID: CGWindowID?) -> AXUIElement? {
        guard let cgID = exactWindowID else { return nil }
        guard let windows = copyElements(appElement, attribute: kAXWindowsAttribute) else { return nil }
        return windows.first { isUsableWindow($0) && windowID(of: $0) == cgID }
    }

    /// Only reached when the caller allows the application fallback: the exact
    /// window if we found it, otherwise the app's best window.
    private func activationFallbackElement(
        for appElement: AXUIElement,
        exactElement: AXUIElement?,
        windowID: CGWindowID?
    ) -> AXUIElement? {
        if let exactElement {
            return exactElement
        }
        return bestWindowElement(for: appElement, preferredWindowID: windowID)
    }

    /// The window matching `exactWindowID` without the usable-window filter,
    /// which rejects minimized windows. Activation still wants the window the
    /// user picked from the switcher when it is minimized — the caller restores
    /// it before raising.
    private func activationWindowElement(for appElement: AXUIElement, exactWindowID: CGWindowID?) -> AXUIElement? {
        guard let cgID = exactWindowID else { return nil }
        guard let windows = copyElements(appElement, attribute: kAXWindowsAttribute) else { return nil }
        return windows.first { windowID(of: $0) == cgID }
    }

    private func ensureAccessibilityAuthorizationSync(promptIfNeeded: Bool) -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }
        return AXIsProcessTrusted()
    }

    private func focusedTextTargetCandidates(
        preferredApplication: NSRunningApplication?
    ) -> [AXUIElement] {
        let systemWide = AXUIElementCreateSystemWide()
        let systemFocused = copyElement(
            systemWide,
            attribute: kAXFocusedUIElementAttribute as String
        )
        let focusedApplication = copyElement(
            systemWide,
            attribute: kAXFocusedApplicationAttribute as String
        )
        let applicationFocused = focusedApplication.flatMap {
            copyElement(
                $0,
                attribute: kAXFocusedUIElementAttribute as String
            )
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostFocused = frontmost.flatMap {
            focusedUIElement(in: $0.processIdentifier)
        }
        let preferredFocused = preferredApplication.flatMap {
            focusedUIElement(in: $0.processIdentifier)
        }

        helperDebug(
            "focused candidates system=\(debugElementDescription(systemFocused))"
                + " application=\(debugElementDescription(applicationFocused))"
                + " frontmost=\(frontmost?.bundleIdentifier ?? frontmost?.localizedName ?? "none")"
                + ":\(frontmost?.processIdentifier ?? 0)"
                + " focused=\(debugElementDescription(frontmostFocused))"
                + " preferred=\(debugElementDescription(preferredFocused))"
        )

        var candidates: [AXUIElement] = []
        for element in [
            systemFocused,
            applicationFocused,
            frontmostFocused,
            preferredFocused,
        ].compactMap({ $0 }) {
            let resolvedElement = focusedDescendantTextTarget(from: element)
                ?? element
            var pid = pid_t(0)
            guard AXUIElementGetPid(resolvedElement, &pid) == .success,
                  let application = NSRunningApplication(processIdentifier: pid),
                  isTargetApplication(application),
                  !candidates.contains(where: { CFEqual($0, resolvedElement) }) else {
                continue
            }
            candidates.append(resolvedElement)
        }
        return candidates
    }

    private func focusedDescendantTextTarget(
        from coarseElement: AXUIElement
    ) -> AXUIElement? {
        let role = copyString(
            coarseElement,
            attribute: kAXRoleAttribute as String
        ) ?? ""
        guard role == "AXWebArea"
                || role == kAXGroupRole as String
                || role == "AXGenericElement"
                || role == "AXUnknown" else {
            return nil
        }

        if let nestedFocusedElement = copyElement(
            coarseElement,
            attribute: kAXFocusedUIElementAttribute as String
        ),
        !CFEqual(nestedFocusedElement, coarseElement),
        isFocusedEditableTextTarget(nestedFocusedElement) {
            return nestedFocusedElement
        }

        var stack: [(element: AXUIElement, depth: Int)] = [(coarseElement, 0)]
        var visited: [AXUIElement] = []
        var bestMatch: (element: AXUIElement, depth: Int)?

        while let candidate = stack.popLast(), visited.count < 256 {
            guard candidate.depth <= 12,
                  !visited.contains(where: { CFEqual($0, candidate.element) }) else {
                continue
            }
            visited.append(candidate.element)

            if candidate.depth > 0,
               copyBool(
                   candidate.element,
                   attribute: Self.isFocusedAttribute
               ) == true,
               isFocusedEditableTextTarget(candidate.element),
               candidate.depth > (bestMatch?.depth ?? -1) {
                bestMatch = candidate
            }

            let children = copyElements(
                candidate.element,
                attribute: kAXChildrenAttribute as String
            ) ?? []
            for child in children.reversed() {
                stack.append((child, candidate.depth + 1))
            }
        }

        return bestMatch?.element
    }

    private func isFocusedEditableTextTarget(_ element: AXUIElement) -> Bool {
        switch DictationTextTargetPolicy.decision(
            for: textTargetCapabilities(for: element)
        ) {
        case .directAccessibility, .guardedApplicationPaste:
            return true
        case .reject:
            return false
        }
    }

    private func focusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        let systemFocused = copyElement(
            systemWide,
            attribute: kAXFocusedUIElementAttribute as String
        )
        let focusedApplication = copyElement(
            systemWide,
            attribute: kAXFocusedApplicationAttribute as String
        )
        let applicationFocused = focusedApplication.flatMap {
            copyElement(
                $0,
                attribute: kAXFocusedUIElementAttribute as String
            )
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let frontmostFocused = frontmost.flatMap {
            copyElement(
                AXUIElementCreateApplication($0.processIdentifier),
                attribute: kAXFocusedUIElementAttribute as String
            )
        }

        helperDebug(
            "focused candidates system=\(debugElementDescription(systemFocused))"
                + " application=\(debugElementDescription(applicationFocused))"
                + " frontmost=\(frontmost?.bundleIdentifier ?? frontmost?.localizedName ?? "none")"
                + ":\(frontmost?.processIdentifier ?? 0)"
                + " focused=\(debugElementDescription(frontmostFocused))"
        )

        if let systemFocused {
            return systemFocused
        }
        if let applicationFocused {
            return applicationFocused
        }
        if let frontmostFocused {
            return frontmostFocused
        }
        guard let frontmost else {
            helperDebug("captureFocusedTextTarget: no focused AX element and no frontmost app")
            return nil
        }
        helperDebug(
            "captureFocusedTextTarget: no focused AX element frontmost=\(frontmost.bundleIdentifier ?? frontmost.localizedName ?? "unknown"):\(frontmost.processIdentifier)"
        )
        return nil
    }

    private func debugElementDescription(_ element: AXUIElement?) -> String {
        guard let element else { return "nil" }
        var pid = pid_t(0)
        AXUIElementGetPid(element, &pid)
        let role = copyString(element, attribute: kAXRoleAttribute as String) ?? "unknown"
        let subrole = copyString(element, attribute: kAXSubroleAttribute as String) ?? "none"
        return "\(pid):\(role):\(subrole)"
    }

    private func resolveEditableTextTarget(from focusedElement: AXUIElement) -> TextTargetResolution {
        var candidate: AXUIElement? = focusedElement
        var editableTarget: (element: AXUIElement, allowsPasteFallback: Bool)?

        // Web and custom controls sometimes focus a descendant of the element
        // that owns AXSelectedText. Walk only a bounded ancestor chain, but scan
        // the full chain for inherited protection before accepting a descendant.
        for _ in 0..<8 {
            guard let element = candidate else { break }
            if isSecureTextElement(element) {
                return .secure
            }
            if editableTarget == nil,
               let allowsPasteFallback = editableTextCapabilities(for: element) {
                editableTarget = (element, allowsPasteFallback)
            }
            candidate = copyElement(element, attribute: kAXParentAttribute as String)
        }

        if let editableTarget {
            return .editable(
                editableTarget.element,
                allowsPasteFallback: editableTarget.allowsPasteFallback
            )
        }
        return .nonEditable
    }

    private func applicationPasteTarget(_ focusedElement: AXUIElement) -> CapturedTextTarget? {
        guard supportsGuardedApplicationPaste(from: focusedElement) else {
            return nil
        }
        var focusedPID = pid_t(0)
        guard AXUIElementGetPid(focusedElement, &focusedPID) == .success,
              focusedPID != 0,
              let application = NSRunningApplication(processIdentifier: focusedPID),
              application.processIdentifier != 0,
              isTargetApplication(application) else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let kind: CapturedTextTargetKind = .applicationUnicode
        let focusedFrame = frame(of: focusedElement)
        let capturedWindowID = windowID(of: focusedElement)
            ?? focusedFrame.flatMap {
                WindowTargetResolver.windowID(
                    containing: $0,
                    targetPID: application.processIdentifier,
                    topWindows: topWindowSnapshots(),
                    ownPID: pid_t(ProcessInfo.processInfo.processIdentifier)
                )
            }
        guard let capturedWindowID else {
            return nil
        }

        return CapturedTextTarget(
            element: appElement,
            pid: application.processIdentifier,
            windowID: capturedWindowID,
            displayID: focusedFrame.flatMap(displayID(containing:)),
            allowsPasteFallback: true,
            kind: kind
        )
    }

    private func topmostTargetApplication() -> NSRunningApplication? {
        for window in topWindowSnapshots() {
            guard let application = NSRunningApplication(
                processIdentifier: window.pid
            ), isTargetApplication(application) else {
                continue
            }
            return application
        }
        return nil
    }

    private func topmostApplicationPasteTarget() -> CapturedTextTarget? {
        let topWindows = topWindowSnapshots()
        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        for window in topWindows where applicationsByPID[window.pid] == nil {
            applicationsByPID[window.pid] = NSRunningApplication(
                processIdentifier: window.pid
            )
        }
        let target = WindowTargetResolver.topmostApplicationPasteTarget(
            topWindows: topWindows,
            applicationsByPID: applicationsByPID.compactMapValues(applicationSnapshot),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            excludedBundleIDs: excludedWindowTargetBundleIDs,
            allowedBundleIDs: nil
        )
        guard let target,
              let window = topWindows.first(where: {
                  $0.pid == target.pid && $0.windowID == target.windowID
              }) else {
            return nil
        }
        return CapturedTextTarget(
            element: AXUIElementCreateApplication(target.pid),
            pid: target.pid,
            windowID: target.windowID,
            displayID: displayID(containing: window.bounds),
            allowsPasteFallback: true,
            kind: .applicationUnicode
        )
    }

    private func applicationPasteTarget(
        from preferredTarget: NSDictionary
    ) -> CapturedTextTarget? {
        guard let pidNumber = preferredTarget["pid"] as? NSNumber,
              let windowIDNumber = preferredTarget["windowID"] as? NSNumber else {
            return nil
        }
        let pid = pid_t(pidNumber.int32Value)
        let windowID = CGWindowID(truncating: windowIDNumber)
        guard pid != 0,
              windowID != 0,
              let application = NSRunningApplication(processIdentifier: pid),
              isTargetApplication(application) else {
            return nil
        }
        let displayID = (preferredTarget["displayID"] as? NSNumber).map {
            CGDirectDisplayID(truncating: $0)
        }
        return CapturedTextTarget(
            element: AXUIElementCreateApplication(pid),
            pid: pid,
            windowID: windowID,
            displayID: displayID,
            allowsPasteFallback: true,
            kind: .applicationUnicode
        )
    }

    private func isSecureTextElement(_ element: AXUIElement) -> Bool {
        if copyBool(element, attribute: Self.protectedContentAttribute) == true {
            return true
        }

        let role = copyString(element, attribute: kAXRoleAttribute as String) ?? ""
        let subrole = copyString(element, attribute: kAXSubroleAttribute as String) ?? ""
        let secureSubrole = kAXSecureTextFieldSubrole as String
        return subrole == secureSubrole
            || role.localizedCaseInsensitiveContains("secure")
            || subrole.localizedCaseInsensitiveContains("secure")
    }

    private func hasSecureFocusedAncestry(for expectedPID: pid_t) -> Bool {
        guard let coarseElement = activeFocusedUIElement(for: expectedPID) else {
            return false
        }
        var candidate: AXUIElement? = focusedDescendantTextTarget(from: coarseElement)
            ?? coarseElement
        for _ in 0..<8 {
            guard let element = candidate else { return false }
            if isSecureTextElement(element) { return true }
            candidate = copyElement(element, attribute: kAXParentAttribute as String)
        }
        return false
    }

    /// Returns nil for controls that cannot support verified direct insertion.
    /// Opaque editors use a guarded app-level insertion path.
    private func editableTextCapabilities(for element: AXUIElement) -> Bool? {
        switch DictationTextTargetPolicy.decision(
            for: textTargetCapabilities(for: element)
        ) {
        case .directAccessibility:
            return true
        case .guardedApplicationPaste:
            return nil
        case .reject:
            return nil
        }
    }

    private func supportsGuardedApplicationPaste(
        from focusedElement: AXUIElement
    ) -> Bool {
        var candidate: AXUIElement? = focusedElement
        var foundCustomEditor = false

        for _ in 0..<8 {
            guard let element = candidate else { break }
            if isSecureTextElement(element) {
                return false
            }

            let capabilities = textTargetCapabilities(for: element)
            if DictationTextTargetPolicy.blocksAncestorFallback(role: capabilities.role) {
                return false
            }
            switch DictationTextTargetPolicy.decision(for: capabilities) {
            case .guardedApplicationPaste:
                foundCustomEditor = true
            case .directAccessibility, .reject:
                break
            }
            candidate = copyElement(element, attribute: kAXParentAttribute as String)
        }

        return foundCustomEditor
    }

    private func textTargetCapabilities(
        for element: AXUIElement
    ) -> DictationTextTargetCapabilities {
        DictationTextTargetCapabilities(
            role: copyString(element, attribute: kAXRoleAttribute as String) ?? "",
            isEnabled: copyBool(
                element,
                attribute: kAXEnabledAttribute as String
            ) != false,
            isSelectedTextSettable: isAttributeSettable(
                element,
                attribute: kAXSelectedTextAttribute as String
            ),
            isSelectedTextRangeSettable: isAttributeSettable(
                element,
                attribute: kAXSelectedTextRangeAttribute as String
            ),
            isValueSettable: isAttributeSettable(
                element,
                attribute: kAXValueAttribute as String
            )
        )
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private func isStillFocused(_ target: CapturedTextTarget) -> Bool {
        guard let coarseFocusedElement = activeFocusedUIElement(for: target.pid) else {
            return false
        }
        let focusedElement = focusedDescendantTextTarget(from: coarseFocusedElement)
            ?? coarseFocusedElement
        guard case let .editable(currentElement, _) = resolveEditableTextTarget(from: focusedElement) else {
            return false
        }

        var currentPID = pid_t(0)
        guard AXUIElementGetPid(currentElement, &currentPID) == .success,
              currentPID == target.pid else {
            return false
        }
        guard CFEqual(currentElement, target.element) else {
            return false
        }
        return isElement(
            focusedElement,
            inCapturedWindowID: target.windowID
        )
    }

    private func activeFocusedUIElement(for expectedPID: pid_t) -> AXUIElement? {
        if let systemFocusedElement = systemFocusedUIElement(),
           let systemFocusedPID = elementPID(systemFocusedElement) {
            if systemFocusedPID == expectedPID {
                return systemFocusedElement
            }
            guard isGojoHostApplication(pid: systemFocusedPID) else {
                return nil
            }
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == expectedPID,
              let applicationFocusedElement = focusedUIElement(in: expectedPID),
              elementPID(applicationFocusedElement) == expectedPID else {
            return nil
        }
        helperDebug(
            "focus validation using frontmost fallback"
                + " pid=\(expectedPID)"
                + " element=\(debugElementDescription(applicationFocusedElement))"
        )
        return applicationFocusedElement
    }

    private func isGojoHostApplication(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            == "rohoswagger.gojo"
    }

    private func systemFocusedUIElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        if let systemFocusedElement = copyElement(
            systemWide,
            attribute: kAXFocusedUIElementAttribute as String
        ) {
            return systemFocusedElement
        }

        guard let focusedApplication = copyElement(
            systemWide,
            attribute: kAXFocusedApplicationAttribute as String
        ) else {
            return nil
        }
        return copyElement(
            focusedApplication,
            attribute: kAXFocusedUIElementAttribute as String
        )
    }

    private func elementPID(_ element: AXUIElement) -> pid_t? {
        var pid = pid_t(0)
        guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else {
            return nil
        }
        return pid
    }

    private func isElement(
        _ element: AXUIElement,
        inCapturedWindowID expectedWindowID: CGWindowID?
    ) -> Bool {
        guard let expectedWindowID else { return true }
        return windowID(of: element) == expectedWindowID
    }

    private func focusedUIElement(in pid: pid_t) -> AXUIElement? {
        copyElement(
            AXUIElementCreateApplication(pid),
            attribute: kAXFocusedUIElementAttribute as String
        )
    }

    private func insertWithGuardedPaste(
        _ text: String,
        target: CapturedTextTarget,
        reply: @escaping (NSDictionary) -> Void
    ) {
        guard isStillFocused(target) else {
            reply(textInsertionFailure(authorized: true, error: "focusChanged"))
            return
        }
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.pasteKeyCode,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.pasteKeyCode,
                keyDown: false
              ) else {
            reply(textInsertionFailure(authorized: true, error: "pasteEventUnavailable"))
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        guard snapshot.isComplete else {
            reply(textInsertionFailure(authorized: true, error: "clipboardSnapshotUnavailable"))
            return
        }
        let transcriptItem = NSPasteboardItem()
        transcriptItem.setString(text, forType: .string)
        transcriptItem.setData(Data(), forType: Self.transientPasteboardType)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([transcriptItem]) else {
            _ = snapshot.restore(to: pasteboard)
            reply(textInsertionFailure(authorized: true, error: "pasteboardWriteFailed"))
            return
        }
        let injectedChangeCount = pasteboard.changeCount

        // Re-check after touching the pasteboard and immediately before sending
        // Cmd-V. This closes the last focus-change window before the side effect.
        guard isStillFocused(target) else {
            if pasteboard.changeCount == injectedChangeCount {
                _ = snapshot.restore(to: pasteboard)
            }
            reply(textInsertionFailure(authorized: true, error: "focusChanged"))
            return
        }
        guard let expectation = pasteMutationExpectation(text, into: target.element) else {
            if pasteboard.changeCount == injectedChangeCount {
                _ = snapshot.restore(to: pasteboard)
            }
            reply(textInsertionFailure(authorized: true, error: "pasteVerificationUnavailable"))
            return
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        waitForPasteConfirmation(
            expectation: expectation,
            target: target,
            pasteboard: pasteboard,
            injectedChangeCount: injectedChangeCount,
            snapshot: snapshot,
            attemptsRemaining: 20,
            reply: reply
        )
    }

    private func waitForAccessibilityConfirmation(
        expectation: PasteMutationExpectation,
        target: CapturedTextTarget,
        attemptsRemaining: Int,
        reply: @escaping (NSDictionary) -> Void
    ) {
        if expectation.confirms(
            currentValue: copyString(target.element, attribute: kAXValueAttribute as String)
        ) {
            reply([
                "authorized": true,
                "success": true,
                "method": "accessibility",
                "verified": true,
            ])
            return
        }
        guard attemptsRemaining > 0 else {
            let currentValue = copyString(
                target.element,
                attribute: kAXValueAttribute as String
            )
            if target.allowsPasteFallback,
               expectation.confirmsNoMutation(currentValue: currentValue),
               isStillFocused(target) {
                insertWithGuardedPaste(
                    expectation.insertionText,
                    target: target,
                    reply: reply
                )
                return
            }
            reply([
                "authorized": true,
                "success": false,
                "method": "accessibility",
                "verified": false,
                "error": "axInsertionNotConfirmed",
            ])
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForAccessibilityConfirmation(
                expectation: expectation,
                target: target,
                attemptsRemaining: attemptsRemaining - 1,
                reply: reply
            )
        }
    }

    private func waitForPasteConfirmation(
        expectation: PasteMutationExpectation,
        target: CapturedTextTarget,
        pasteboard: NSPasteboard,
        injectedChangeCount: Int,
        snapshot: PasteboardSnapshot,
        attemptsRemaining: Int,
        reply: @escaping (NSDictionary) -> Void
    ) {
        if expectation.confirms(
            currentValue: copyString(target.element, attribute: kAXValueAttribute as String)
        ) {
            let shouldRestore = pasteboard.changeCount == injectedChangeCount
            let restored = shouldRestore ? snapshot.restore(to: pasteboard) : false
            reply([
                "authorized": true,
                "success": true,
                "method": "paste",
                "verified": true,
                "clipboardRestored": restored,
            ])
            return
        }
        guard attemptsRemaining > 0 else {
            // Keep the transcript on the clipboard when consumption is not
            // confirmed. Restoring here could make a delayed Cmd-V insert the
            // user's previous clipboard contents.
            reply([
                "authorized": true,
                "success": false,
                "method": "paste",
                "verified": false,
                "clipboardRestored": false,
                "error": "pasteNotConfirmed",
            ])
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForPasteConfirmation(
                expectation: expectation,
                target: target,
                pasteboard: pasteboard,
                injectedChangeCount: injectedChangeCount,
                snapshot: snapshot,
                attemptsRemaining: attemptsRemaining - 1,
                reply: reply
            )
        }
    }

    private func pasteMutationExpectation(
        _ text: String,
        into element: AXUIElement
    ) -> PasteMutationExpectation? {
        guard let originalValue = copyString(element, attribute: kAXValueAttribute as String),
              let selectedRange = copyCFRange(
                  element,
                  attribute: kAXSelectedTextRangeAttribute as String
              ) else {
            return nil
        }
        return PasteMutationExpectation(
            originalValue: originalValue,
            selectedRange: selectedRange,
            insertionText: text
        )
    }

    private func textCaptureFailure(authorized: Bool, error: String) -> NSDictionary {
        [
            "authorized": authorized,
            "success": false,
            "error": error,
        ]
    }

    private func textInsertionFailure(authorized: Bool, error: String) -> NSDictionary {
        [
            "authorized": authorized,
            "success": false,
            "method": "none",
            "error": error,
        ]
    }

    private func focusedWindowSnapshotDictionary() -> NSDictionary? {
        guard let app = targetApplication() else {
            return nil
        }

        rememberTargetApplicationIfNeeded(app)

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let preferredWindowID = preferredTopWindowID(for: app.processIdentifier)
        guard let windowElement = bestWindowElement(for: appElement, preferredWindowID: preferredWindowID),
              let axFrame = frame(of: windowElement),
              !axFrame.isNull,
              axFrame.width > 0,
              axFrame.height > 0 else {
            return nil
        }

        let normalFrame = axFrame.gojoHelperScreenFlipped
        let windowID = windowID(of: windowElement) ?? preferredWindowID
        var snapshot: [String: Any] = [
            "authorized": true,
            "pid": NSNumber(value: app.processIdentifier),
            "appName": app.localizedName ?? "Focused app",
            "axFrame": axFrame.dictionaryRepresentation as NSDictionary,
            "normalFrame": normalFrame.dictionaryRepresentation as NSDictionary
        ]

        if let windowID {
            snapshot["windowID"] = NSNumber(value: windowID)
        }

        if let bundleIdentifier = app.bundleIdentifier {
            snapshot["bundleIdentifier"] = bundleIdentifier
        }
        if let title = copyString(windowElement, attribute: kAXTitleAttribute) {
            snapshot["title"] = title
        }

        return snapshot as NSDictionary
    }

    private func targetApplication() -> NSRunningApplication? {
        let frontmost = focusedApplication() ?? NSWorkspace.shared.frontmostApplication
        let topWindows = topWindowSnapshots()

        var applicationsByPID: [pid_t: NSRunningApplication] = [:]
        [frontmost, lastWindowTargetApplication].compactMap { $0 }.forEach { app in
            applicationsByPID[app.processIdentifier] = app
        }
        for window in topWindows where applicationsByPID[window.pid] == nil {
            applicationsByPID[window.pid] = NSRunningApplication(processIdentifier: window.pid)
        }

        let selectedPID = WindowTargetResolver.resolve(
            frontmost: frontmost.flatMap(applicationSnapshot),
            lastTarget: lastWindowTargetApplication.flatMap(applicationSnapshot),
            topWindows: topWindows,
            applicationsByPID: applicationsByPID.compactMapValues(applicationSnapshot),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            excludedBundleIDs: excludedWindowTargetBundleIDs
        )

        guard let selectedPID,
              let app = applicationsByPID[selectedPID] ?? NSRunningApplication(processIdentifier: selectedPID),
              isTargetApplication(app) else {
            return nil
        }

        rememberTargetApplicationIfNeeded(app)
        return app
    }

    private func focusedApplication() -> NSRunningApplication? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedApplicationElement = copyElement(systemWideElement, attribute: kAXFocusedApplicationAttribute) else {
            return nil
        }

        var pid = pid_t(0)
        guard AXUIElementGetPid(focusedApplicationElement, &pid) == .success else {
            return nil
        }

        return NSRunningApplication(processIdentifier: pid)
    }

    private var excludedWindowTargetBundleIDs: Set<String> {
        Set([
            Bundle.main.bundleIdentifier,
            "rohoswagger.gojo"
        ].compactMap { $0 })
    }

    private func rememberTargetApplicationIfNeeded(_ app: NSRunningApplication) {
        guard isTargetApplication(app) else { return }
        lastWindowTargetApplication = app
    }

    private func isTargetApplication(_ app: NSRunningApplication) -> Bool {
        WindowTargetResolver.isTargetApplication(
            applicationSnapshot(for: app),
            ownPID: pid_t(ProcessInfo.processInfo.processIdentifier),
            excludedBundleIDs: excludedWindowTargetBundleIDs
        )
    }

    private func applicationSnapshot(for app: NSRunningApplication) -> WindowTargetApplicationSnapshot {
        WindowTargetApplicationSnapshot(
            pid: app.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            activationPolicy: windowTargetActivationPolicy(for: app.activationPolicy),
            isTerminated: app.isTerminated
        )
    }

    private func windowTargetActivationPolicy(for policy: NSApplication.ActivationPolicy) -> WindowTargetActivationPolicy {
        switch policy {
        case .regular:
            return .regular
        case .accessory:
            return .accessory
        case .prohibited:
            return .prohibited
        @unknown default:
            return .unknown
        }
    }

    private func topWindowSnapshots() -> [WindowTargetWindowSnapshot] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return windowList.compactMap(WindowTargetWindowSnapshot.init(cgWindowInfo:))
            .filter { WindowTargetResolver.isTopLevelWindow($0, ownPID: ownPID) }
    }

    private func preferredTopWindowID(for pid: pid_t) -> CGWindowID? {
        topWindowSnapshots().first { $0.pid == pid }?.windowID
    }

    private func bestWindowElement(for appElement: AXUIElement, preferredWindowID: CGWindowID? = nil) -> AXUIElement? {
        let directCandidates = [
            copyElement(appElement, attribute: kAXFocusedWindowAttribute),
            copyElement(appElement, attribute: kAXMainWindowAttribute)
        ]

        for candidate in directCandidates.compactMap({ $0 }) where isUsableWindow(candidate) {
            return candidate
        }

        if let preferredWindowID,
           let matchingWindow = copyElements(appElement, attribute: kAXWindowsAttribute)?
            .first(where: { isUsableWindow($0) && windowID(of: $0) == preferredWindowID }) {
            return matchingWindow
        }

        return copyElements(appElement, attribute: kAXWindowsAttribute)?
            .first(where: isUsableWindow)
    }

    private func isUsableWindow(_ element: AXUIElement) -> Bool {
        if let role = copyString(element, attribute: kAXRoleAttribute), role != kAXWindowRole as String {
            return false
        }
        if copyBool(element, attribute: kAXMinimizedAttribute) == true {
            return false
        }
        guard let frame = frame(of: element), !frame.isNull, frame.width > 0, frame.height > 0 else {
            return false
        }
        return true
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let position = copyCGPoint(element, attribute: kAXPositionAttribute),
              let size = copyCGSize(element, attribute: kAXSizeAttribute) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success else { return nil }
        return windowID
    }

    private func displayID(containing frame: CGRect) -> CGDirectDisplayID? {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else {
            return nil
        }

        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return nil
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let result = displays.withUnsafeMutableBufferPointer { buffer in
            CGGetOnlineDisplayList(
                displayCount,
                buffer.baseAddress,
                &displayCount
            )
        }
        guard result == .success else { return nil }

        let availableDisplays = Array(displays.prefix(Int(displayCount)))
        let displayBounds = availableDisplays.map(CGDisplayBounds)
        guard let index = WindowTargetResolver.displayIndex(
            containing: frame,
            displayBounds: displayBounds
        ) else {
            return nil
        }
        return availableDisplays[index]
    }

    private func setAXFrame(_ frame: CGRect, for element: AXUIElement, pid: pid_t) -> Bool {
        var size = frame.size
        var position = frame.origin

        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let positionValue = AXValueCreate(.cgPoint, &position) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        let enhancedUIWasEnabled = copyBool(appElement, attribute: "AXEnhancedUserInterface")
        if enhancedUIWasEnabled == true {
            setBool(false, element: appElement, attribute: "AXEnhancedUserInterface")
        }

        let firstSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        let positionResult = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, positionValue)
        let secondSizeResult = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)

        if enhancedUIWasEnabled == true {
            setBool(true, element: appElement, attribute: "AXEnhancedUserInterface")
        }

        let succeeded = firstSizeResult == .success && positionResult == .success && secondSizeResult == .success
        if !succeeded {
            // Per-attribute AX error codes (e.g. position=-25200 kAXErrorFailure on
            // windows that refuse repositioning) — keep: this is the line that
            // pinpoints why a move was rejected.
            helperDebug("setAXFrame FAILED pid=\(pid) size1=\(firstSizeResult.rawValue) pos=\(positionResult.rawValue) size2=\(secondSizeResult.rawValue) enhancedUI=\(enhancedUIWasEnabled.map(String.init(describing:)) ?? "nil")")
        }
        return succeeded
    }

    private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? [AXUIElement]
    }

    private func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func copyBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private func copyCFRange(_ element: AXUIElement, attribute: String) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    @discardableResult
    private func setBool(_ value: Bool, element: AXUIElement, attribute: String) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value as CFBoolean) == .success
    }

    private func copyCGPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(axValue, .cgPoint, &point)
        return point
    }

    private func copyCGSize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else { return nil }
        var size = CGSize.zero
        AXValueGetValue(axValue, .cgSize, &size)
        return size
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

private extension CGRect {
    var gojoHelperScreenFlipped: CGRect {
        guard !isNull else { return self }
        let maxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(origin: CGPoint(x: origin.x, y: maxY - self.maxY), size: size)
    }
}
