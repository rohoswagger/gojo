import Foundation
import Cocoa
@preconcurrency import AsyncXPCConnection
import os

private let dictationPasteLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "application-paste"
)

private struct DictationCaptureTargetHint: Sendable {
    let pid: pid_t
    let windowID: CGWindowID
    let displayID: CGDirectDisplayID?

    var xpcDictionary: NSDictionary {
        var result: [String: Any] = [
            "pid": NSNumber(value: pid),
            "windowID": NSNumber(value: windowID),
        ]
        if let displayID {
            result["displayID"] = NSNumber(value: displayID)
        }
        return NSDictionary(dictionary: result)
    }
}

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

private struct DictationPasteboardSnapshot {
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

@MainActor
private final class DictationApplicationInsertionService {
    static let shared = DictationApplicationInsertionService()

    private static let commandKeyCode: CGKeyCode = 0x37
    private static let pasteKeyCode: CGKeyCode = 0x09
    private static let transientPasteboardType = NSPasteboard.PasteboardType(
        "org.nspasteboard.TransientType"
    )
    private static let protectedContentAttribute = "AXContainsProtectedContent"
    private static let isFocusedAttribute = "AXFocused"

    private init() {}

    // Retained for future scoped compatibility targets that cannot receive
    // Unicode events. Current opaque dictation targets use insertUnicode so
    // dictated text never has to touch the global clipboard.
    // Adapted from Pindrop's MIT-licensed OutputManager. The keyboard events
    // must come from Gojo, the process the user grants Accessibility access to.
    func insert(
        _ text: String,
        target: DictationApplicationPasteTarget
    ) async -> NSDictionary {
        guard let targetApplication = NSRunningApplication(processIdentifier: target.pid),
              !targetApplication.isTerminated else {
            return failure("focusChanged")
        }
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let commandDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.commandKeyCode,
                keyDown: true
              ),
              let pasteDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.pasteKeyCode,
                keyDown: true
              ),
              let pasteUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.pasteKeyCode,
                keyDown: false
              ),
              let commandUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: Self.commandKeyCode,
                keyDown: false
              ) else {
            return failure("pasteEventUnavailable")
        }

        commandDown.flags = .maskCommand
        pasteDown.flags = .maskCommand
        pasteUp.flags = .maskCommand

        let pasteboard = NSPasteboard.general
        let snapshot = DictationPasteboardSnapshot(pasteboard: pasteboard)
        guard snapshot.isComplete else {
            return failure("clipboardSnapshotUnavailable")
        }
        guard isTargetProcessFrontmost(target.pid),
              isCapturedWindowFrontmost(
                  targetPID: target.pid,
                  targetWindowID: target.windowID
              ) else {
            return failure("focusChanged")
        }

        let transcriptItem = NSPasteboardItem()
        transcriptItem.setString(text, forType: .string)
        transcriptItem.setData(Data(), forType: Self.transientPasteboardType)

        pasteboard.clearContents()
        guard pasteboard.writeObjects([transcriptItem]) else {
            _ = snapshot.restore(to: pasteboard)
            return failure("pasteboardWriteFailed")
        }
        let injectedChangeCount = pasteboard.changeCount
        var commandIsDown = false
        var pasteIsDown = false
        var pasteEventPosted = false

        do {
            try await Task.sleep(for: .milliseconds(80))

            guard isTargetProcessFrontmost(target.pid),
                  isCapturedWindowFrontmost(
                    targetPID: target.pid,
                    targetWindowID: target.windowID
                  ),
                  pasteboard.changeCount == injectedChangeCount,
                  pasteboard.string(forType: .string) == text else {
                if pasteboard.changeCount == injectedChangeCount {
                    _ = snapshot.restore(to: pasteboard)
                }
                return failure("focusChanged")
            }

            commandDown.post(tap: .cghidEventTap)
            commandIsDown = true
            try await Task.sleep(for: .milliseconds(50))
            guard isTargetProcessFrontmost(target.pid),
                  isCapturedWindowFrontmost(
                    targetPID: target.pid,
                    targetWindowID: target.windowID
                  ) else {
                commandUp.post(tap: .cghidEventTap)
                commandIsDown = false
                if pasteboard.changeCount == injectedChangeCount {
                    _ = snapshot.restore(to: pasteboard)
                }
                return failure("focusChanged")
            }
            pasteDown.post(tap: .cghidEventTap)
            pasteIsDown = true
            pasteEventPosted = true
            try await Task.sleep(for: .milliseconds(50))
            pasteUp.post(tap: .cghidEventTap)
            pasteIsDown = false
            try await Task.sleep(for: .milliseconds(50))
            commandUp.post(tap: .cghidEventTap)
            commandIsDown = false
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            if pasteIsDown {
                pasteUp.post(tap: .cghidEventTap)
            }
            if commandIsDown {
                commandUp.post(tap: .cghidEventTap)
            }
            if !pasteEventPosted,
               pasteboard.changeCount == injectedChangeCount {
                _ = snapshot.restore(to: pasteboard)
            }
            return failure("insertionCancelled")
        }

        return [
            "authorized": true,
            "success": true,
            "method": "application-paste",
            "verified": false,
            "clipboardRestored": false,
        ]
    }

    func insertUnicode(
        _ text: String,
        target: DictationApplicationPasteTarget
    ) async -> NSDictionary {
        guard let targetApplication = NSRunningApplication(
            processIdentifier: target.pid
        ), !targetApplication.isTerminated else {
            return unicodeFailure("focusChanged")
        }
        let chunks = DictationUnicodeTextInjector.chunks(for: text)
        guard !chunks.isEmpty, chunks.joined() == text else {
            return unicodeFailure("unicodeChunkUnavailable")
        }
        var postedChunkCount = 0
        for (index, chunk) in chunks.enumerated() {
            guard isTargetProcessFrontmost(target.pid),
                  isCapturedWindowFrontmost(
                    targetPID: target.pid,
                    targetWindowID: target.windowID
                  ) else {
                let failure = DictationUnicodeTextInjector.failure(
                    afterPostedChunks: postedChunkCount,
                    fallbackCode: "focusChanged"
                )
                return unicodeFailure(
                    failure.code,
                    partialInsertion: failure.isPartialInsertion
                )
            }
            guard !hasSecureFocusedAncestry(target.pid) else {
                let failure = DictationUnicodeTextInjector.failure(
                    afterPostedChunks: postedChunkCount,
                    fallbackCode: "secureTextTarget"
                )
                return unicodeFailure(
                    failure.code,
                    partialInsertion: failure.isPartialInsertion
                )
            }
            guard DictationUnicodeTextInjector.post(chunk) else {
                let failure = DictationUnicodeTextInjector.failure(
                    afterPostedChunks: postedChunkCount,
                    fallbackCode: "unicodeEventUnavailable"
                )
                return unicodeFailure(
                    failure.code,
                    partialInsertion: failure.isPartialInsertion
                )
            }
            postedChunkCount += 1

            if index < chunks.index(before: chunks.endIndex) {
                do {
                    try await Task.sleep(for: .milliseconds(2))
                } catch {
                    return unicodeFailure(
                        "partialInsertion",
                        partialInsertion: true
                    )
                }
            }
        }

        return [
            "authorized": true,
            "success": true,
            "method": "application-unicode",
            "verified": false,
        ]
    }

    private func failure(_ error: String) -> NSDictionary {
        [
            "authorized": true,
            "success": false,
            "method": "application-paste",
            "verified": false,
            "error": error,
        ]
    }

    private func unicodeFailure(
        _ error: String,
        partialInsertion: Bool = false
    ) -> NSDictionary {
        let result: [String: Any] = [
            "authorized": true,
            "success": false,
            "method": "application-unicode",
            "verified": false,
            "error": error,
        ]
        guard partialInsertion else {
            return NSDictionary(dictionary: result)
        }
        return NSDictionary(
            dictionary: result.merging(
                ["partialInsertion": true],
                uniquingKeysWith: { _, newValue in newValue }
            )
        )
    }

    private func isCapturedWindowFrontmost(
        targetPID: pid_t,
        targetWindowID: CGWindowID
    ) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let topWindows = windowList
            .compactMap(WindowTargetWindowSnapshot.init(cgWindowInfo:))
        let matches = WindowTargetResolver.isCapturedWindowTopmost(
            targetPID: targetPID,
            targetWindowID: targetWindowID,
            topWindows: topWindows,
            ownPID: ownPID
        )
        if matches {
            return true
        }
        if isTargetProcessFrontmost(targetPID),
           capturedAccessibilityWindowIsActive(
               targetPID: targetPID,
               targetWindowID: targetWindowID
           ) {
            return true
        }
        let targetCandidates = topWindows.filter { $0.pid == targetPID }
        let candidates = targetCandidates
            .map {
                "\($0.windowID.map { String($0) } ?? "none")"
                    + ":\(Int($0.bounds.width))x\(Int($0.bounds.height))"
                    + ":layer\($0.layer)"
            }
            .joined(separator: ",")
        let message = "window mismatch pid=\(targetPID)"
            + " captured=\(targetWindowID)"
            + " candidates=\(candidates)"
        dictationPasteLogger.error("\(message, privacy: .public)")
        return false
    }

    private func isTargetProcessFrontmost(_ targetPID: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        if let focusedApplication = copyElement(
            systemWide,
            attribute: kAXFocusedApplicationAttribute as String
        ) {
            var focusedPID = pid_t(0)
            if AXUIElementGetPid(focusedApplication, &focusedPID) == .success {
                if focusedPID == targetPID {
                    return true
                }
                guard focusedPID == pid_t(ProcessInfo.processInfo.processIdentifier) else {
                    return false
                }
            }
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
    }

    private func capturedAccessibilityWindowIsActive(
        targetPID: pid_t,
        targetWindowID: CGWindowID
    ) -> Bool {
        let appElement = AXUIElementCreateApplication(targetPID)
        let candidates = [
            copyElement(appElement, attribute: kAXFocusedWindowAttribute as String),
            copyElement(appElement, attribute: kAXMainWindowAttribute as String)
        ]
        return candidates.compactMap { $0 }.contains { windowID(of: $0) == targetWindowID }
    }

    private func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func hasSecureFocusedAncestry(_ expectedPID: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(expectedPID)
        guard let coarseElement = copyElement(
            application,
            attribute: kAXFocusedUIElementAttribute as String
        ) else {
            return false
        }
        var candidate: AXUIElement? = focusedDescendant(from: coarseElement)
            ?? coarseElement
        for _ in 0..<8 {
            guard let element = candidate else { return false }
            if copyBool(element, attribute: Self.protectedContentAttribute) == true {
                return true
            }
            let role = copyString(element, attribute: kAXRoleAttribute as String) ?? ""
            let subrole = copyString(element, attribute: kAXSubroleAttribute as String) ?? ""
            if subrole == kAXSecureTextFieldSubrole as String
                || role.localizedCaseInsensitiveContains("secure")
                || subrole.localizedCaseInsensitiveContains("secure") {
                return true
            }
            candidate = copyElement(element, attribute: kAXParentAttribute as String)
        }
        return false
    }

    private func focusedDescendant(from coarseElement: AXUIElement) -> AXUIElement? {
        if let nestedFocusedElement = copyElement(
            coarseElement,
            attribute: kAXFocusedUIElementAttribute as String
        ), !CFEqual(nestedFocusedElement, coarseElement) {
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
               candidate.depth > (bestMatch?.depth ?? -1) {
                bestMatch = candidate
            }
            for child in (copyElements(
                candidate.element,
                attribute: kAXChildrenAttribute as String
            ) ?? []).reversed() {
                stack.append((child, candidate.depth + 1))
            }
        }
        return bestMatch?.element
    }

    private func copyElements(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? [AXUIElement]
    }

    private func copyBool(_ element: AXUIElement, attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    private func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func windowID(of element: AXUIElement) -> CGWindowID? {
        var windowID = CGWindowID(0)
        let result = _AXUIElementGetWindow(element, &windowID)
        guard result == .success else { return nil }
        return windowID
    }
}

/// Result of a helper frame mutation. `resultingFrame` is the window's actual
/// frame read back from AX (source of truth, no CGWindowList lag) — nil when the
/// move failed or the helper couldn't read it back.
struct WindowFrameResult {
    let success: Bool
    let resultingFrame: CGRect?

    static let failure = WindowFrameResult(success: false, resultingFrame: nil)

    init(success: Bool, resultingFrame: CGRect?) {
        self.success = success
        self.resultingFrame = resultingFrame
    }

    init(reply: NSDictionary) {
        success = (reply["success"] as? NSNumber)?.boolValue ?? false
        resultingFrame = (reply["frame"] as? NSDictionary)
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
    }
}

final class XPCHelperClient: NSObject, @unchecked Sendable {
    nonisolated static let shared = XPCHelperClient()
    
    private let serviceName = "rohoswagger.gojo.GojoXPCHelper"
    
    private var remoteService: RemoteXPCService<GojoXPCHelperProtocol>?
    private var connection: NSXPCConnection?
    private var lastKnownAuthorization: Bool?
    private var monitoringTask: Task<Void, Never>?
    
    deinit {
        connection?.invalidate()
        stopMonitoringAccessibilityAuthorization()
    }
    
    // MARK: - Connection Management (Main Actor Isolated)
    
    @MainActor
    private func ensureRemoteService() -> RemoteXPCService<GojoXPCHelperProtocol> {
        if let existing = remoteService {
            return existing
        }
        
        let conn = NSXPCConnection(serviceName: serviceName)
        
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
                self?.remoteService = nil
            }
        }
        
        conn.resume()
        
        let service = RemoteXPCService<GojoXPCHelperProtocol>(
            connection: conn,
            remoteInterface: GojoXPCHelperProtocol.self
        )
        
        connection = conn
        remoteService = service
        return service
    }
    
    @MainActor
    private func getRemoteService() -> RemoteXPCService<GojoXPCHelperProtocol>? {
        remoteService
    }
    
    @MainActor
    private func notifyAuthorizationChange(_ granted: Bool) {
        guard lastKnownAuthorization != granted else { return }
        lastKnownAuthorization = granted
        NotificationCenter.default.post(
            name: .accessibilityAuthorizationChanged,
            object: nil,
            userInfo: ["granted": granted]
        )
    }

    // MARK: - Monitoring
    nonisolated func startMonitoringAccessibilityAuthorization(every interval: TimeInterval = 3.0) {
        // Ensure only one monitor exists
        stopMonitoringAccessibilityAuthorization()
        monitoringTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Call the helper method periodically which will notify on change
                _ = await self.isAccessibilityAuthorized()
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch { break }
            }
        }
    }

    nonisolated func stopMonitoringAccessibilityAuthorization() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    // Expose whether the client is actively monitoring (useful for tests/debug)
    var isMonitoring: Bool {
        return monitoringTask != nil
    }
    
    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try? await service.withService { service in
                service.requestAccessibilityAuthorization()
            }
        }
    }
    
    nonisolated func isAccessibilityAuthorized() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.isAccessibilityAuthorized { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }
    
    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: Bool = try await service.withContinuation { service, continuation in
                service.ensureAccessibilityAuthorization(promptIfNeeded) { authorized in
                    continuation.resume(returning: authorized)
                }
            }
            await MainActor.run {
                notifyAuthorizationChange(result)
            }
            return result
        } catch {
            return false
        }
    }

    // MARK: - Search Hotkey Interception

    /// Starts the helper-side ⌘Space event tap (see `SearchHotkeyTapService`
    /// in GojoXPCHelper). Must run in the helper, not the main app: the main
    /// Gojo.app is sandboxed and cannot create a global keyboard event tap.
    /// `token` is echoed back in the toggle notification so the caller can
    /// authenticate it. Returns whether the tap is active after the call.
    nonisolated func startSearchHotkeyInterception(token: String) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            return try await service.withContinuation { service, continuation in
                service.startSearchHotkeyInterception(token) { active in
                    continuation.resume(returning: active)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func stopSearchHotkeyInterception() {
        Task {
            let service = await MainActor.run { ensureRemoteService() }
            try? await service.withService { service in
                service.stopSearchHotkeyInterception()
            }
        }
    }

    nonisolated func captureFocusedTextTarget(promptIfNeeded: Bool = false) async -> NSDictionary {
        do {
            let (service, preferredTargetHint) = await MainActor.run {
                (
                    ensureRemoteService(),
                    preferredDictationApplicationPasteTarget()
                )
            }
            let preferredTarget = preferredTargetHint?.xpcDictionary
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                service.captureFocusedTextTarget(
                    promptIfNeeded,
                    preferredTarget: preferredTarget
                ) { result in
                    continuation.resume(returning: result)
                }
            }
            let authorized = (result["authorized"] as? NSNumber)?.boolValue == true
            await MainActor.run {
                notifyAuthorizationChange(authorized)
            }
            return result
        } catch {
            return [
                "authorized": false,
                "success": false,
                "error": "helperUnavailable",
            ]
        }
    }

    @MainActor
    private func preferredDictationApplicationPasteTarget()
        -> DictationCaptureTargetHint? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        let topWindows = windowList.compactMap(
            WindowTargetWindowSnapshot.init(cgWindowInfo:)
        )
        var applicationsByPID: [pid_t: WindowTargetApplicationSnapshot] = [:]
        for window in topWindows where applicationsByPID[window.pid] == nil {
            guard let application = NSRunningApplication(
                processIdentifier: window.pid
            ) else {
                continue
            }
            applicationsByPID[window.pid] = WindowTargetApplicationSnapshot(
                pid: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                activationPolicy: dictationActivationPolicy(
                    application.activationPolicy
                ),
                isTerminated: application.isTerminated
            )
        }
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        guard let target = WindowTargetResolver.topmostApplicationPasteTarget(
            topWindows: topWindows,
            applicationsByPID: applicationsByPID,
            ownPID: ownPID,
            excludedBundleIDs: [Bundle.main.bundleIdentifier].compactMap {
                $0
            }.reduce(into: Set<String>()) {
                $0.insert($1)
            },
            allowedBundleIDs: nil
        ) else {
            return nil
        }
        let targetWindow = topWindows.first {
            $0.pid == target.pid && $0.windowID == target.windowID
        }
        let displayID = targetWindow.flatMap {
            dictationDisplayID(containing: $0.bounds)
        }
        return DictationCaptureTargetHint(
            pid: target.pid,
            windowID: target.windowID,
            displayID: displayID
        )
    }

    private func dictationActivationPolicy(
        _ policy: NSApplication.ActivationPolicy
    ) -> WindowTargetActivationPolicy {
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

    private func dictationDisplayID(
        containing frame: CGRect
    ) -> CGDirectDisplayID? {
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return nil
        }
        var displays = [CGDirectDisplayID](
            repeating: 0,
            count: Int(displayCount)
        )
        let result = displays.withUnsafeMutableBufferPointer { buffer in
            CGGetOnlineDisplayList(
                displayCount,
                buffer.baseAddress,
                &displayCount
            )
        }
        guard result == .success else {
            return nil
        }
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

    nonisolated func insertText(_ text: String, token: String) async -> NSDictionary {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                service.insertText(text, token: token) { result in
                    continuation.resume(returning: result)
                }
            }
            let authorized = (result["authorized"] as? NSNumber)?.boolValue == true
            await MainActor.run {
                notifyAuthorizationChange(authorized)
            }
            if result["error"] as? String == "applicationPasteRequired",
               let pid = result["pid"] as? NSNumber,
               let windowID = result["windowID"] as? NSNumber {
                let targetPID = pid_t(pid.int32Value)
                let targetWindowID = CGWindowID(truncating: windowID)
                // Do not activate or raise the destination here. Opaque browser
                // windows may not expose an AX window element, and stealing focus
                // would make it possible to paste after the user switched away.
                // The paste service verifies the captured pid and CGWindowID before
                // touching the clipboard and again before posting every key event.
                return await DictationApplicationInsertionService.shared.insert(
                    text,
                    target: DictationApplicationPasteTarget(
                        pid: targetPID,
                        windowID: targetWindowID
                    )
                )
            }
            if result["error"] as? String == "applicationPasteRequired" {
                return [
                    "authorized": true,
                    "success": false,
                    "method": "application-paste",
                    "verified": false,
                    "error": "focusChanged",
                ]
            }
            if result["error"] as? String == "applicationUnicodeRequired",
               let pid = result["pid"] as? NSNumber,
               let windowID = result["windowID"] as? NSNumber {
                return await DictationApplicationInsertionService.shared.insertUnicode(
                    text,
                    target: DictationApplicationPasteTarget(
                        pid: pid_t(pid.int32Value),
                        windowID: CGWindowID(truncating: windowID)
                    )
                )
            }
            if result["error"] as? String == "applicationUnicodeRequired" {
                return [
                    "authorized": true,
                    "success": false,
                    "method": "application-unicode",
                    "verified": false,
                    "error": "focusChanged",
                ]
            }
            return result
        } catch {
            return [
                "authorized": false,
                "success": false,
                "method": "none",
                "error": "helperUnavailable",
            ]
        }
    }

    nonisolated func focusedWindowSnapshot(promptIfNeeded: Bool) async -> NSDictionary? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                service.focusedWindowSnapshot(promptIfNeeded) { snapshot in
                    continuation.resume(returning: snapshot)
                }
            }
            let authorized = (result["authorized"] as? NSNumber)?.boolValue == true
            await MainActor.run {
                notifyAuthorizationChange(authorized)
            }
            guard result["error"] == nil else { return nil }
            return result
        } catch {
            return nil
        }
    }

    nonisolated func setFocusedWindowFrame(_ normalFrame: CGRect, windowID: CGWindowID?) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let frameDictionary = normalFrame.dictionaryRepresentation as NSDictionary
            let windowIDNumber = windowID.map { NSNumber(value: $0) }
            return try await service.withContinuation { service, continuation in
                service.setFocusedWindowFrame(frameDictionary, windowID: windowIDNumber) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func setWindowFrame(_ normalFrame: CGRect, pid: pid_t, windowID: CGWindowID?) async -> WindowFrameResult {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let frameDictionary = normalFrame.dictionaryRepresentation as NSDictionary
            let pidNumber = NSNumber(value: pid)
            let windowIDNumber = windowID.map { NSNumber(value: $0) }
            let reply: NSDictionary = try await service.withContinuation { service, continuation in
                service.setWindowFrame(frameDictionary, pid: pidNumber, windowID: windowIDNumber) { reply in
                    continuation.resume(returning: reply)
                }
            }
            return WindowFrameResult(reply: reply)
        } catch {
            return .failure
        }
    }

    nonisolated func performZoom(pid: pid_t, windowID: CGWindowID?) async -> WindowFrameResult {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let pidNumber = NSNumber(value: pid)
            let windowIDNumber = windowID.map { NSNumber(value: $0) }
            let reply: NSDictionary = try await service.withContinuation { service, continuation in
                service.performZoom(pidNumber, windowID: windowIDNumber) { reply in
                    continuation.resume(returning: reply)
                }
            }
            return WindowFrameResult(reply: reply)
        } catch {
            return .failure
        }
    }

    nonisolated func raiseWindow(
        pid: pid_t,
        windowID: CGWindowID?,
        allowApplicationFallback: Bool
    ) async -> Bool {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let pidNumber = NSNumber(value: pid)
            let windowIDNumber = windowID.map { NSNumber(value: $0) }
            return try await service.withContinuation { service, continuation in
                service.raiseWindow(
                    pidNumber,
                    windowID: windowIDNumber,
                    allowApplicationFallback: allowApplicationFallback
                ) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }

    nonisolated func enumerateWindows(screenUUID: String?) async -> [[String: Any]] {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let result: NSArray = try await service.withContinuation { service, continuation in
                service.enumerateWindows(forScreen: screenUUID as NSString?) { array in
                    continuation.resume(returning: array)
                }
            }
            return (result as? [[String: Any]]) ?? []
        } catch {
            return []
        }
    }
    
    nonisolated func windowTitles(for windows: [(pid: pid_t, windowID: CGWindowID)]) async -> [CGWindowID: String] {
        guard !windows.isEmpty else { return [:] }
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let requests: NSArray = windows.map { pair -> NSDictionary in
                ["pid": NSNumber(value: pair.pid), "windowID": NSNumber(value: pair.windowID)] as NSDictionary
            } as NSArray
            let reply: NSDictionary = try await service.withContinuation { service, continuation in
                service.windowTitles(requests) { dict in
                    continuation.resume(returning: dict)
                }
            }
            var result: [CGWindowID: String] = [:]
            for case let (key as String, value as String) in reply {
                if let wid = UInt32(key) { result[CGWindowID(wid)] = value }
            }
            return result
        } catch {
            return [:]
        }
    }

    // MARK: - Keyboard Brightness
    
    nonisolated func isKeyboardBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isKeyboardBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentKeyboardBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentKeyboardBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setKeyboardBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setKeyboardBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
    
    // MARK: - Screen Brightness
    
    nonisolated func isScreenBrightnessAvailable() async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.isScreenBrightnessAvailable { available in
                    continuation.resume(returning: available)
                }
            }
        } catch {
            return false
        }
    }
    
    nonisolated func currentScreenBrightness() async -> Float? {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let result: NSNumber? = try await service.withContinuation { service, continuation in
                service.currentScreenBrightness { value in
                    continuation.resume(returning: value)
                }
            }
            return result?.floatValue
        } catch {
            return nil
        }
    }
    
    nonisolated func setScreenBrightness(_ value: Float) async -> Bool {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            return try await service.withContinuation { service, continuation in
                service.setScreenBrightness(value) { success in
                    continuation.resume(returning: success)
                }
            }
        } catch {
            return false
        }
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}
