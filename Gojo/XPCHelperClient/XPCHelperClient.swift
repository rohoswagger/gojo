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

@MainActor
private final class DictationApplicationInsertionService {
    static let shared = DictationApplicationInsertionService()

    private static let protectedContentAttribute = "AXContainsProtectedContent"
    private static let isFocusedAttribute = "AXFocused"

    private init() {}

    func insertUnicode(
        _ text: String,
        target: DictationApplicationPasteTarget,
        cancellation: DictationDeliveryCancellation
    ) async -> NSDictionary {
        guard !cancellation.isCancelled else {
            return unicodeFailure("insertionCancelled")
        }
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
            guard !cancellation.isCancelled else {
                let failure = DictationUnicodeTextInjector.failure(
                    afterPostedChunks: postedChunkCount,
                    fallbackCode: "insertionCancelled"
                )
                return unicodeFailure(
                    failure.code,
                    partialInsertion: failure.isPartialInsertion
                )
            }
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
            guard cancellation.withCommitPermission({ DictationUnicodeTextInjector.post(chunk) }) == true else {
                let failure = DictationUnicodeTextInjector.failure(
                    afterPostedChunks: postedChunkCount,
                    fallbackCode: cancellation.isCancelled ? "insertionCancelled" : "unicodeEventUnavailable"
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
    @MainActor private var connectionGeneration = HelperConnectionGeneration()
    @MainActor private var lastPermissionStatus: HelperPermissionStatus?
    @MainActor private var pendingHelperReplies: [UUID: (HelperConnectionFailure) -> Void] = [:]
    @MainActor var dictationInputHandler: (@MainActor (DictationTapEvent) -> Void)?
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
        
        let generation = connectionGeneration.next()
        let receiver = DictationHelperInputReceiver { [weak self] event in
            guard let self, self.connectionGeneration.owns(generation), self.connection != nil else { return }
            self.dictationInputHandler?(event)
        }
        conn.exportedInterface = NSXPCInterface(with: GojoXPCHelperInputProtocol.self)
        conn.exportedObject = receiver
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connectionDidEnd(generation: generation, failure: .interrupted) }
        }
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connectionDidEnd(generation: generation, failure: .invalidated) }
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
    private func connectionDidEnd(generation: UInt64, failure: HelperConnectionFailure) {
        guard connectionGeneration.owns(generation), connection != nil else { return }
        let oldConnection = connection
        connection = nil
        remoteService = nil
        lastPermissionStatus = nil
        _ = connectionGeneration.next()
        let pending = pendingHelperReplies.values
        pendingHelperReplies.removeAll()
        pending.forEach { $0(failure) }
        NotificationCenter.default.post(name: .helperConnectionStateChanged, object: self,
            userInfo: ["failure": failure])
        oldConnection?.invalidate()
    }

    @MainActor
    private func helperRequest(_ send: (GojoXPCHelperProtocol, @escaping (NSDictionary) -> Void) -> Void) async throws -> HelperWireReply {
        try Task.checkCancellation()
        _ = ensureRemoteService()
        guard let connection else { throw HelperConnectionFailure.invalidated }
        let generation = connectionGeneration.value
        let identifier = UUID()
        let waiter = HelperReplyWaiter()
        defer { pendingHelperReplies.removeValue(forKey: identifier) }
        let value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                pendingHelperReplies[identifier] = { failure in waiter.finish(.failure(failure)) }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                    waiter.finish(.failure(HelperConnectionFailure.wrapping(error)))
                }) as? GojoXPCHelperProtocol else {
                    waiter.finish(.failure(HelperConnectionFailure.invalidated)); return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                    waiter.finish(.failure(HelperConnectionFailure.timedOut))
                }
                send(proxy) { dictionary in waiter.finish(.success(HelperWireReply(dictionary: dictionary, generation: generation))) }
            }
        } onCancel: { waiter.finish(.failure(CancellationError())) }
        guard connectionGeneration.owns(generation), self.connection != nil else { throw HelperConnectionFailure.invalidated }
        try Task.checkCancellation()
        return value
    }

    nonisolated func helperPermissionStatus() async throws -> HelperPermissionStatus {
        let reply = try await helperRequest { $0.helperPermissionStatus(with: $1) }
        let status = try HelperPermissionStatus(reply: reply.dictionary)
        try await recordPermissionStatus(status, generation: reply.generation)
        return status
    }

    nonisolated func requestHelperAccessibility() async throws -> HelperPermissionStatus {
        let reply = try await helperRequest { $0.requestHelperAccessibility(with: $1) }
        let status = try HelperPermissionStatus(reply: reply.dictionary)
        try await recordPermissionStatus(status, generation: reply.generation)
        return status
    }

    @MainActor
    private func recordPermissionStatus(_ status: HelperPermissionStatus, generation: UInt64) throws {
        guard connectionGeneration.owns(generation), connection != nil else { throw HelperConnectionFailure.invalidated }
        let instanceChanged = lastPermissionStatus?.instanceID != status.instanceID
        lastPermissionStatus = status
        notifyAuthorizationChange(status.accessibilityAuthorized)
        if instanceChanged { NotificationCenter.default.post(name: .helperConnectionStateChanged, object: self) }
    }

    nonisolated func startDictationTap(requestID: UUID) async throws -> DictationTapStatus {
        let reply = try await helperRequest { $0.startDictationHotkey(requestID.uuidString, with: $1) }
        let status = try DictationTapStatus(reply: reply.dictionary)
        guard status.requestID == requestID else { throw HelperConnectionFailure.malformedReply }
        return status
    }

    nonisolated func stopDictationTap(requestID: UUID) async throws {
        _ = try await helperRequest { service, reply in service.stopDictationHotkey(requestID.uuidString) { reply([:]) } }
    }

    nonisolated func dictationTapStatus(requestID: UUID) async throws -> DictationTapStatus {
        let reply = try await helperRequest { $0.dictationHotkeyStatus(requestID.uuidString, with: $1) }
        let status = try DictationTapStatus(reply: reply.dictionary)
        guard status.requestID == requestID else { throw HelperConnectionFailure.malformedReply }
        return status
    }

    #if DEBUG
    nonisolated func dictationTapDiagnostics(requestID: UUID, recoverDisabled: Bool) async throws -> (enabled: Bool, consumed: UInt64) {
        let reply = try await helperRequest { $0.dictationHotkeyDiagnostics(requestID.uuidString, recoverDisabled: recoverDisabled, with: $1) }
        guard let enabled = reply.dictionary["enabled"] as? Bool, let consumed = reply.dictionary["consumed"] as? NSNumber else { throw HelperConnectionFailure.malformedReply }
        return (enabled, consumed.uint64Value)
    }
    #endif

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

    // MARK: - Accessibility
    
    nonisolated func requestAccessibilityAuthorization() {
        Task { _ = try? await requestHelperAccessibility() }
    }

    nonisolated func isAccessibilityAuthorized() async -> Bool {
        (try? await helperPermissionStatus().accessibilityAuthorized) ?? false
    }

    nonisolated func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        if promptIfNeeded { return (try? await requestHelperAccessibility().accessibilityAuthorized) ?? false }
        return await isAccessibilityAuthorized()
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
        await captureTextTarget(promptIfNeeded: promptIfNeeded, replacingExistingTargets: true)
    }

    nonisolated func captureAdditionalFocusedTextTarget(promptIfNeeded: Bool = false) async -> NSDictionary {
        await captureTextTarget(promptIfNeeded: promptIfNeeded, replacingExistingTargets: false)
    }

    private nonisolated func captureTextTarget(
        promptIfNeeded: Bool,
        replacingExistingTargets: Bool
    ) async -> NSDictionary {
        do {
            let (service, preferredTargetHint) = await MainActor.run {
                (
                    ensureRemoteService(),
                    preferredDictationApplicationPasteTarget()
                )
            }
            let preferredTarget = preferredTargetHint?.xpcDictionary
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                let reply: (NSDictionary) -> Void = { result in
                    continuation.resume(returning: result)
                }
                if replacingExistingTargets {
                    service.captureFocusedTextTarget(
                        promptIfNeeded,
                        preferredTarget: preferredTarget,
                        with: reply
                    )
                } else {
                    service.captureAdditionalFocusedTextTarget(
                        promptIfNeeded,
                        preferredTarget: preferredTarget,
                        with: reply
                    )
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

    nonisolated func insertText(_ text: String, token: String, transactionID: UUID = UUID()) async -> NSDictionary {
        await performTextInsertion(text, token: token, transactionID: transactionID, retainingTarget: false)
    }

    nonisolated func insertTextRetainingTarget(_ text: String, token: String, transactionID: UUID = UUID()) async -> NSDictionary {
        await performTextInsertion(text, token: token, transactionID: transactionID, retainingTarget: true)
    }

    nonisolated func releaseTextTarget(_ token: String) async {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let _: Void = try await service.withContinuation { service, continuation in
                service.releaseTextTarget(token) {
                    continuation.resume(returning: ())
                }
            }
        } catch {}
    }

    nonisolated func observeDictationCorrection(
        _ text: String,
        targetIdentity: String
    ) async -> NSDictionary {
        do {
            try Task.checkCancellation()
            let service = await MainActor.run {
                ensureRemoteService()
            }
            try Task.checkCancellation()
            return try await service.withContinuation { service, continuation in
                service.observeDictationCorrection(text, targetIdentity: targetIdentity) { result in
                    continuation.resume(returning: result)
                }
            }
        } catch {
            return [:]
        }
    }

    nonisolated func cancelDictationCorrectionObservation() async {
        do {
            let service = await MainActor.run {
                ensureRemoteService()
            }
            let _: Void = try await service.withContinuation { service, continuation in
                service.cancelDictationCorrectionObservation {
                    continuation.resume(returning: ())
                }
            }
        } catch {}
    }

    private nonisolated func performTextInsertion(
        _ text: String,
        token: String,
        transactionID: UUID,
        retainingTarget: Bool
    ) async -> NSDictionary {
        let cancellation = DictationDeliveryCancellation()
        if Task.isCancelled { cancellation.cancel() }
        return await withTaskCancellationHandler {
            await DictationDeliveryWriter.shared.perform(transactionID: transactionID) {
                await self.executeTextInsertion(text, token: token, transactionID: transactionID,
                                                retainingTarget: retainingTarget, cancellation: cancellation)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private nonisolated func executeTextInsertion(
        _ text: String,
        token: String,
        transactionID: UUID,
        retainingTarget: Bool,
        cancellation: DictationDeliveryCancellation
    ) async -> NSDictionary {
        let hostWriterID = await DictationDeliveryWriter.shared.identity
        func failure(_ code: String, requested: Bool) -> NSDictionary {
            ["authorized": true, "success": false, "method": "none", "error": code,
             "transactionID": transactionID.uuidString,
             "writerID": requested ? "helper:unacknowledged" : hostWriterID,
             "disposition": requested ? "partialUnknown" : "notSent",
             "writerQuiescent": !requested]
        }
        guard !cancellation.isCancelled else { return failure("insertionCancelled", requested: false) }
        var requested = false
        do {
            let service = await MainActor.run { ensureRemoteService() }
            guard !cancellation.isCancelled else { return failure("insertionCancelled", requested: false) }
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                let reply: (NSDictionary) -> Void = { result in continuation.resume(returning: result) }
                requested = true
                if retainingTarget {
                    service.insertTextRetainingTarget(text, token: token, transactionID: transactionID.uuidString, with: reply)
                } else {
                    service.insertText(text, token: token, transactionID: transactionID.uuidString, with: reply)
                }
            }
            let authorized = (result["authorized"] as? NSNumber)?.boolValue == true
            await MainActor.run { notifyAuthorizationChange(authorized) }
            let insertionResult = await resolveTextInsertionResult(result, text: text,
                transactionID: transactionID, hostWriterID: hostWriterID, cancellation: cancellation)
            if retainingTarget, (insertionResult["success"] as? NSNumber)?.boolValue != true {
                await releaseTextTarget(token)
            }
            return insertionResult
        } catch {
            return failure(error is CancellationError ? "insertionCancelled" : "helperUnavailable", requested: requested)
        }
    }

    private nonisolated func resolveTextInsertionResult(
        _ result: NSDictionary,
        text: String,
        transactionID: UUID,
        hostWriterID: String,
        cancellation: DictationDeliveryCancellation
    ) async -> NSDictionary {
        let error = result["error"] as? String
        guard error == "applicationPasteRequired" || error == "applicationUnicodeRequired" else { return result }
        var hostResult: NSDictionary
        if cancellation.isCancelled {
            hostResult = ["authorized": true, "success": false, "method": "none", "error": "insertionCancelled"]
        } else if error == "applicationPasteRequired" {
            hostResult = ["authorized": true, "success": false, "method": "none", "error": "automaticPasteDisabled"]
        } else if let pid = result["pid"] as? NSNumber, let windowID = result["windowID"] as? NSNumber {
            hostResult = await DictationApplicationInsertionService.shared.insertUnicode(
                text,
                target: DictationApplicationPasteTarget(pid: pid_t(pid.int32Value), windowID: CGWindowID(truncating: windowID)),
                cancellation: cancellation
            )
        } else {
            hostResult = ["authorized": true, "success": false, "method": "application-unicode", "error": "focusChanged"]
        }
        var receipt: [String: Any] = [:]
        for (key, value) in hostResult {
            if let key = key as? String { receipt[key] = value }
        }
        receipt["transactionID"] = transactionID.uuidString
        receipt["writerID"] = hostWriterID
        receipt["writerQuiescent"] = true
        receipt["disposition"] = (hostResult["success"] as? NSNumber)?.boolValue == true ? "allDispatched"
            : ((hostResult["partialInsertion"] as? NSNumber)?.boolValue == true ? "partialUnknown" : "notSent")
        return NSDictionary(dictionary: receipt)
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

    nonisolated func focusedWindow(forPID pid: pid_t) async -> WindowTargetWindowSnapshot? {
        do {
            let service = await MainActor.run { ensureRemoteService() }
            let result: NSDictionary = try await service.withContinuation { service, continuation in
                service.focusedWindowSnapshot(forPID: NSNumber(value: pid)) { snapshot in
                    continuation.resume(returning: snapshot)
                }
            }
            guard WindowTargetResolver.pidValue(result["pid"]) == pid,
                  let windowID = WindowTargetResolver.cgWindowIDValue(result["windowID"]),
                  windowID != 0,
                  let frame = WindowTargetResolver.rectValue(result["axFrame"]),
                  !frame.isNull, frame.width > 0, frame.height > 0 else {
                return nil
            }
            return WindowTargetWindowSnapshot(windowID: windowID, pid: pid, ownerName: nil, layer: 0, bounds: frame)
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

private final class DictationHelperInputReceiver: NSObject, GojoXPCHelperInputProtocol {
    private let receive: @MainActor (DictationTapEvent) -> Void
    private let queue = DispatchQueue(label: "gojo.dictation.client-input")

    init(receive: @escaping @MainActor (DictationTapEvent) -> Void) { self.receive = receive }

    func dictationHotkeyInput(_ requestID: String, helperInstanceID: String, sequence: UInt64,
        kind: Int, exactChord: Bool, triggerDown: Bool, disallowed: Bool, reenabled: Bool, with reply: @escaping () -> Void) {
        guard let request = UUID(uuidString: requestID), let instance = UUID(uuidString: helperInstanceID), sequence > 0 else { reply(); return }
        let input: DictationModifierEventTapInput
        switch kind {
        case 0: input = .flagsChanged(isExactChord: exactChord, anyTriggerModifierDown: triggerDown, hasDisallowedModifiers: disallowed)
        case 1: input = .keyDown
        case 2: input = .lockToggle
        case 3: input = .tapDisabled(reenabled: reenabled)
        default: reply(); return
        }
        let event = DictationTapEvent(requestID: request, helperInstanceID: instance, sequence: sequence, input: input)
        queue.async { [receive] in DispatchQueue.main.async { receive(event); reply() } }
    }
}

extension XPCHelperClient: DictationHotkeyTransport {}
