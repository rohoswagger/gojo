import Foundation

@MainActor
final class GojoDictationService {
    static let shared = GojoDictationService()

    private(set) var commands: [String] = []
    private(set) var hasPendingWork = false

    static func sendShortcutEvent(_ event: DictationShortcutEvent) {
        shared.commands.append(String(describing: event))
        switch event {
        case .keyDown, .startVoiceMode:
            shared.hasPendingWork = true
        case .cancel:
            shared.hasPendingWork = false
        default:
            break
        }
    }

    func beginShortcut() {
        Self.sendShortcutEvent(.keyDown)
    }

    func startVoiceMode() {
        Self.sendShortcutEvent(.startVoiceMode)
    }

    func clearCommands() {
        commands.removeAll()
    }
}

extension Notification.Name {
    static let accessibilityAuthorizationChanged = Notification.Name("accessibilityAuthorizationChanged")
}

@MainActor
final class XPCHelperClient: DictationHotkeyTransport {
    static let shared = XPCHelperClient()
    var dictationInputHandler: (@MainActor (DictationTapEvent) -> Void)?
    var permission = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: false)
    var failure: HelperConnectionFailure?
    var statusFailure: HelperConnectionFailure?
    var suspendHealth = false
    var healthContinuation: CheckedContinuation<HelperPermissionStatus, Error>?
    var tapState: DictationTapState = .enabled
    var permissionContinuation: CheckedContinuation<HelperPermissionStatus, Never>?
    var startContinuation: CheckedContinuation<DictationTapStatus, Never>?
    var suspendPermission = false
    var suspendStart = false
    private(set) var authorizationChecks = 0
    private(set) var prompts = 0
    private(set) var starts: [UUID] = []
    private(set) var stops: [UUID] = []

    func helperPermissionStatus() async throws -> HelperPermissionStatus {
        authorizationChecks += 1
        if let failure { throw failure }
        if suspendHealth { return try await withCheckedThrowingContinuation { healthContinuation = $0 } }
        return permission
    }

    func requestHelperAccessibility() async throws -> HelperPermissionStatus {
        prompts += 1
        if suspendPermission { return await withCheckedContinuation { permissionContinuation = $0 } }
        return permission
    }

    func startDictationTap(requestID: UUID) async throws -> DictationTapStatus {
        starts.append(requestID)
        if suspendStart { return await withCheckedContinuation { startContinuation = $0 } }
        return DictationTapStatus(requestID: requestID, helper: permission, state: tapState)
    }

    func stopDictationTap(requestID: UUID) async throws { stops.append(requestID) }
    func dictationTapStatus(requestID: UUID) async throws -> DictationTapStatus {
        if let statusFailure { throw statusFailure }
        return DictationTapStatus(requestID: requestID, helper: permission, state: tapState)
    }
    #if DEBUG
    func dictationTapDiagnostics(requestID: UUID, recoverDisabled: Bool) async throws -> (enabled: Bool, consumed: UInt64) { (true, 0) }
    #endif
}

actor ControlledRecoverySleep {
    private var sleepers: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var scheduledCount = 0
    private(set) var cancelledOnWake: Set<Int> = []
    var pendingCount: Int { sleepers.count }
    func sleep() async {
        scheduledCount += 1
        let identifier = scheduledCount
        await withCheckedContinuation { sleepers.append((identifier, $0)) }
        if Task.isCancelled { cancelledOnWake.insert(identifier) }
    }
    func releaseFirst() { if !sleepers.isEmpty { sleepers.removeFirst().1.resume() } }
    func releaseAll() {
        let pending = sleepers
        sleepers.removeAll()
        pending.forEach { $0.1.resume() }
    }
}

@main
struct DictationShortcutCancellationRegression {
    @MainActor
    static func main() async {
        let monitor = DictationModifierHotKeyMonitor.shared
        let service = GojoDictationService.shared
        var failures: [String] = []

        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        func expectCommands(_ commands: [String], _ message: String) {
            expect(service.commands == commands, "\(message). Expected \(commands), received \(service.commands)")
        }

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        expect(service.hasPendingWork, "Finish leaves downstream work pending in the stub")
        monitor.cancelCurrentSession()
        expectCommands(["cancel"], "Idle recognizer cancels downstream work after Finish")
        expect(!service.hasPendingWork, "Explicit cancellation reaches downstream work")

        service.clearCommands()
        monitor.cancelCurrentSession()
        monitor.cancelCurrentSession()
        expectCommands(["cancel", "cancel"], "Repeated idle cancellation sends one command per invocation")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        expect(monitor.activationMode == .voiceMode, "Adopted voice session locks the recognizer")
        monitor.cancelCurrentSession()
        expectCommands(["cancel"], "Locked cancellation sends exactly one command")
        expect(monitor.activationMode == .holdToTalk, "Cancellation clears the voice lock")

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        monitor.stop()
        expectCommands(["cancel"], "Stopping an idle recognizer cancels downstream work")
        expect(!service.hasPendingWork, "Stop reaches downstream work")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        monitor.stop()
        expectCommands(["cancel"], "Stopping a locked recognizer sends exactly one command")
        expect(monitor.activationMode == .holdToTalk, "Stop clears the voice lock")

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        monitor.accessibilityAuthorizationWasRevoked()
        expectCommands(["cancel"], "Authorization revocation cancels downstream work")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        await monitor.recoverIfNeeded()
        expectCommands([], "Event-tap recovery preserves a locked voice session")
        expect(monitor.activationMode == .voiceMode, "Recovery retains the voice lock")
        expect(service.hasPendingWork, "Recovery retains downstream voice work")
        expect(XPCHelperClient.shared.authorizationChecks == 1, "Recovery uses the nonprompting authorization stub")
        expect(!monitor.isMonitoring, "The regression never starts an event tap")
        monitor.cancelCurrentSession()

        monitor.stop()

        let transport = XPCHelperClient()
        let injected = DictationModifierHotKeyMonitor(transport: transport, observeConnectionChanges: false)
        await injected.start()
        expect(injected.accessibilityState == .notTrusted, "Actual AX false is permission required")
        expect(injected.shortcutReadiness == .awaitingAccessibility, "AX false keeps shortcut awaiting access")
        transport.failure = .interrupted
        await injected.refreshReadiness()
        expect(injected.accessibilityState == .notTrusted, "Transport failure preserves last actual AX state")
        expect(injected.helperState == .unavailable(.interrupted), "Transport failure has a separate helper state")
        transport.failure = nil
        transport.permission = HelperPermissionStatus(instanceID: transport.permission.instanceID, accessibilityAuthorized: true)
        await injected.refreshReadiness()
        expect(injected.isMonitoring, "Observed grant starts desired monitoring")
        expect(transport.prompts == 0, "Passive recovery never prompts")
        let firstRequest = transport.starts.last!
        transport.failure = .invalidated
        await injected.refreshReadiness()
        expect(!injected.isMonitoring, "Connection loss invalidates readiness")
        expect(injected.accessibilityState == .trusted, "Connection loss does not manufacture a revoked grant")
        transport.failure = nil
        await injected.refreshReadiness()
        expect(injected.isMonitoring, "Reconnect with unchanged grant restarts desired monitoring")
        expect(transport.starts.last != firstRequest, "Reconnect uses a fresh lease")
        service.clearCommands()
        transport.dictationInputHandler?(DictationTapEvent(requestID: firstRequest,
            helperInstanceID: transport.permission.instanceID, sequence: 1, input: .lockToggle))
        expectCommands([], "Old lease callback cannot reactivate dictation")
        injected.stop()

        let cancellation = XPCHelperClient()
        cancellation.permission = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        let cancellationMonitor = DictationModifierHotKeyMonitor(transport: cancellation, observeConnectionChanges: false)
        await cancellationMonitor.start()
        cancellationMonitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        cancellation.suspendHealth = true
        let cancelledRefresh = Task { await cancellationMonitor.refreshReadiness() }
        while cancellation.healthContinuation == nil { await Task.yield() }
        cancelledRefresh.cancel()
        cancellation.suspendHealth = false
        cancellation.healthContinuation?.resume(returning: cancellation.permission)
        await cancelledRefresh.value
        expect(cancellationMonitor.isMonitoring, "Cancelling a Settings refresh must preserve desired monitoring and current lease")
        expect(cancellation.stops.isEmpty, "Cancelling a Settings refresh must not stop the helper lease")
        expectCommands([], "Cancelling a Settings refresh must leave active capture alone")
        expect(service.hasPendingWork && cancellationMonitor.activationMode == .voiceMode,
            "Caller cancellation must preserve the active voice session")
        await cancellationMonitor.recoverIfNeeded()
        expect(cancellationMonitor.isMonitoring, "Lifecycle recovery must remain enabled after cancelled Settings refresh")
        expect(cancellation.starts.count == 1, "Cancelled caller must not replace an active lease")
        cancellation.suspendHealth = true
        cancellation.healthContinuation = nil
        service.clearCommands()
        let cancelledReply = Task { await cancellationMonitor.refreshReadiness() }
        while cancellation.healthContinuation == nil { await Task.yield() }
        cancellation.suspendHealth = false
        cancellation.healthContinuation?.resume(throwing: CancellationError())
        await cancelledReply.value
        expect(cancellationMonitor.isMonitoring && cancellation.stops.isEmpty,
            "A cancelled RPC result abandons only its reconciliation attempt")
        expectCommands([], "A cancelled RPC result must not cancel active capture")
        await cancellationMonitor.refreshReadiness()
        cancellation.statusFailure = .timedOut
        service.clearCommands()
        await cancellationMonitor.refreshReadiness()
        expect(cancellationMonitor.isMonitoring && cancellation.stops.isEmpty,
            "A status timeout must preserve a valid active lease")
        expect(cancellationMonitor.shortcutReadiness == .ready && cancellationMonitor.helperState == .available(cancellation.permission),
            "An active timeout retains the last confirmed operational state while retrying")
        expectCommands([], "A status timeout must not cancel active capture")
        cancellation.statusFailure = nil
        await cancellationMonitor.refreshReadiness()
        expect(cancellationMonitor.shortcutReadiness == .ready && cancellation.starts.count == 1,
            "A recovered status probe reuses its current lease")
        cancellationMonitor.stop()

        let stoppedRefresh = XPCHelperClient()
        let stoppedMonitor = DictationModifierHotKeyMonitor(transport: stoppedRefresh, observeConnectionChanges: false)
        stoppedRefresh.suspendHealth = true
        let cancelledPassiveRefresh = Task { await stoppedMonitor.refreshReadiness() }
        while stoppedRefresh.healthContinuation == nil { await Task.yield() }
        cancelledPassiveRefresh.cancel()
        stoppedRefresh.healthContinuation?.resume(throwing: CancellationError())
        await cancelledPassiveRefresh.value
        expect(stoppedMonitor.helperState == .checking && stoppedMonitor.shortcutReadiness == .stopped,
            "Cancellation of a stopped passive refresh must not manufacture a helper failure")

        let retryTransport = XPCHelperClient()
        retryTransport.permission = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        retryTransport.failure = .timedOut
        let retrySleep = ControlledRecoverySleep()
        let retryMonitor = DictationModifierHotKeyMonitor(transport: retryTransport,
            sleepForRecovery: { _ in await retrySleep.sleep() })
        await retryMonitor.start()
        for _ in 0..<1_000 {
            if await retrySleep.pendingCount == 1 { break }
            await Task.yield()
        }
        expect(await retrySleep.pendingCount == 1, "Timeout schedules the monitor's own backoff")
        NotificationCenter.default.post(name: .helperConnectionStateChanged, object: nil,
            userInfo: ["failure": HelperConnectionFailure.interrupted])
        for _ in 0..<1_000 {
            if retryMonitor.helperState == .unavailable(.interrupted) { break }
            await Task.yield()
        }
        expect(retryMonitor.helperState == .unavailable(.interrupted), "The real connection observer processes interruption")
        retryTransport.failure = nil
        for _ in 0..<1_000 {
            if await retrySleep.pendingCount == 2 { break }
            await Task.yield()
        }
        await retrySleep.releaseFirst()
        for _ in 0..<100 { await Task.yield() }
        expect(retryTransport.authorizationChecks == 1 && !retryMonitor.isMonitoring,
            "A stale timeout wake cannot consume the replacement retry")
        await retrySleep.releaseAll()
        for _ in 0..<1_000 {
            if retryMonitor.shortcutReadiness == .ready { break }
            await Task.yield()
        }
        expect(retryMonitor.shortcutReadiness == .ready && retryMonitor.isMonitoring,
            "Timeout followed by interruption must autonomously recover without an external refresh")
        expect(retryTransport.authorizationChecks == 2 && retryTransport.starts.count == 1,
            "Only the monitor's replacement retry probes and starts the recovered transport")
        retryTransport.statusFailure = .timedOut
        await retryMonitor.refreshReadiness()
        expect(retryMonitor.isMonitoring && retryMonitor.shortcutReadiness == .ready,
            "A slow active helper keeps its confirmed shortcut readiness")
        for _ in 0..<1_000 {
            if await retrySleep.pendingCount == 1 { break }
            await Task.yield()
        }
        NotificationCenter.default.post(name: .helperConnectionStateChanged, object: nil,
            userInfo: ["failure": HelperConnectionFailure.interrupted])
        for _ in 0..<1_000 {
            if await retrySleep.pendingCount == 2 { break }
            await Task.yield()
        }
        expect(!retryMonitor.isMonitoring && retryMonitor.shortcutReadiness == .unavailable(.helper(.interrupted)),
            "A true interruption invalidates an active lease even after a slow status probe")
        await retrySleep.releaseFirst()
        for _ in 0..<100 { await Task.yield() }
        let currentRetryID = await retrySleep.scheduledCount
        retryMonitor.stop()
        await retrySleep.releaseAll()
        for _ in 0..<1_000 {
            if await retrySleep.cancelledOnWake.contains(currentRetryID) { break }
            await Task.yield()
        }
        expect(await retrySleep.cancelledOnWake.contains(currentRetryID),
            "The stale task must not clear the newer recovery task: Stop still cancels that exact retry")

        let pending = XPCHelperClient()
        let pendingMonitor = DictationModifierHotKeyMonitor(transport: pending, observeConnectionChanges: false)
        await pendingMonitor.start(promptIfNeeded: true)
        try? await Task.sleep(for: .milliseconds(550))
        await pendingMonitor.refreshReadiness()
        expect(pendingMonitor.accessibilityState == .requesting, "AX prompt remains pending after half a second")
        expect(pending.prompts == 1, "Passive observations cannot repeat the prompt")
        await pendingMonitor.finishAccessibilityRequest()
        expect(pendingMonitor.accessibilityState == .notTrusted,
            "Returning from a dismissed prompt ends pending observation without declaring denial")
        expect(pending.prompts == 1, "Ending prompt observation never prompts automatically")
        await pendingMonitor.start(promptIfNeeded: true)
        expect(pending.prompts == 2 && pendingMonitor.accessibilityState == .requesting,
            "A fresh explicit user action can rearm a dismissed Accessibility prompt")
        pending.permission = HelperPermissionStatus(instanceID: pending.permission.instanceID, accessibilityAuthorized: true)
        await pendingMonitor.refreshReadiness()
        expect(pendingMonitor.isMonitoring, "Late observed AX grant recovers the desired shortcut")
        pendingMonitor.stop()

        let delayed = XPCHelperClient()
        delayed.permission = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        delayed.suspendStart = true
        let delayedMonitor = DictationModifierHotKeyMonitor(transport: delayed, observeConnectionChanges: false)
        let start = Task { await delayedMonitor.start() }
        while delayed.startContinuation == nil { await Task.yield() }
        let oldRequest = delayed.starts.last!
        delayedMonitor.stop()
        delayed.startContinuation?.resume(returning: DictationTapStatus(requestID: oldRequest, helper: delayed.permission, state: .enabled))
        await start.value
        expect(!delayedMonitor.isMonitoring, "A delayed successful start cannot reactivate a stopped monitor")
        expect(delayed.stops.contains(oldRequest), "A delayed successful start releases its old helper lease")

        delayed.suspendStart = true
        delayed.startContinuation = nil
        let superseded = Task { await delayedMonitor.start() }
        while delayed.startContinuation == nil { await Task.yield() }
        let supersededRequest = delayed.starts.last!
        delayedMonitor.stop()
        delayed.suspendStart = false
        await delayedMonitor.start()
        let replacementRequest = delayed.starts.last!
        delayed.startContinuation?.resume(returning: DictationTapStatus(requestID: supersededRequest, helper: delayed.permission, state: .enabled))
        await superseded.value
        expect(replacementRequest != supersededRequest && delayedMonitor.isMonitoring,
            "A stopped reconciliation completing late cannot clear its replacement task or current lease")
        expect(delayedMonitor.shortcutReadiness == .ready,
            "A stale start completion cannot overwrite replacement readiness")
        delayedMonitor.stop()

        let latePermission = XPCHelperClient()
        latePermission.suspendPermission = true
        let latePermissionMonitor = DictationModifierHotKeyMonitor(transport: latePermission, observeConnectionChanges: false)
        let requesting = Task { await latePermissionMonitor.start(promptIfNeeded: true) }
        while latePermission.permissionContinuation == nil { await Task.yield() }
        latePermissionMonitor.stop()
        latePermission.permissionContinuation?.resume(returning: HelperPermissionStatus(instanceID: latePermission.permission.instanceID,
            accessibilityAuthorized: true))
        await requesting.value
        expect(latePermission.starts.isEmpty, "Late permission reply cannot start a stopped shortcut")
        expect(latePermissionMonitor.shortcutReadiness == .stopped, "Late permission reply cannot overwrite stopped readiness")

        var tapToTalk = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = tapToTalk.handle(.flagsChanged(isExactChord: true, anyTriggerModifierDown: true, hasDisallowedModifiers: false))
        expect(tapToTalk.handle(.flagsChanged(isExactChord: false, anyTriggerModifierDown: false, hasDisallowedModifiers: false)) == .beginDictation,
            "Tap-to-talk admits dictation after releasing both trigger modifiers")
        expect(tapToTalk.handle(.keyDown) == .cancelDictation,
            "Unmodified typing must still cancel active tap-to-talk; dropping those callbacks changes behavior")
        var stoppingVoice = DictationModifierShortcutStateMachine(mode: .voiceMode)
        _ = stoppingVoice.handle(.flagsChanged(isExactChord: true, anyTriggerModifierDown: true, hasDisallowedModifiers: false))
        _ = stoppingVoice.handle(.flagsChanged(isExactChord: false, anyTriggerModifierDown: false, hasDisallowedModifiers: false))
        _ = stoppingVoice.handle(.flagsChanged(isExactChord: true, anyTriggerModifierDown: true, hasDisallowedModifiers: false))
        expect(stoppingVoice.state == .stopping, "Second voice chord arms its stop gesture")
        expect(stoppingVoice.handle(.keyDown) == .none && stoppingVoice.state == .activeBlocked,
            "Typing while voice is stopping disqualifies Stop without ending voice mode")
        expect(stoppingVoice.handle(.flagsChanged(isExactChord: false, anyTriggerModifierDown: false, hasDisallowedModifiers: false)) == .none,
            "Blocked typing recovers without inventing a voice stop")

        let broken = XPCHelperClient()
        broken.permission = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        broken.tapState = .creationFailed
        let brokenMonitor = DictationModifierHotKeyMonitor(transport: broken, observeConnectionChanges: false)
        await brokenMonitor.start()
        expect(!brokenMonitor.isMonitoring, "AX grant alone cannot publish shortcut readiness")
        expect(brokenMonitor.shortcutReadiness == .unavailable(.tap(.creationFailed)), "Tap creation failure is explicit")
        brokenMonitor.stop()

        guard failures.isEmpty else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("Dictation shortcut cancellation regressions passed")
    }
}
