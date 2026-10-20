import Combine
import Foundation
import os

@MainActor
final class DictationModifierHotKeyMonitor: ObservableObject {
    static let shared = DictationModifierHotKeyMonitor(transport: XPCHelperClient.shared)

    @Published private(set) var helperState: DictationHelperState = .checking
    @Published private(set) var accessibilityState: DictationAccessibilityState = .unknown
    @Published private(set) var shortcutReadiness: DictationShortcutReadiness = .stopped

    private let logger = Logger(subsystem: "rohoswagger.gojo.dictation", category: "shortcut")
    private let activationDelay: Duration = .milliseconds(75)
    private let transport: any DictationHotkeyTransport
    private let sleepForRecovery: @Sendable (Duration) async throws -> Void
    private var observers: [NSObjectProtocol] = []
    private var desiredEnabled = false
    private var active = false
    private var eventGate = DictationTapEventGate()
    private var reconciliationTask: Task<Void, Never>?
    private var reconciliationGeneration: UInt64 = 0
    private var activationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryPolicy = DictationEventTapRecoveryPolicy()
    private var startRequests = DictationEventTapStartRequestPolicy()
    private var machine = DictationModifierShortcutStateMachine(mode: .holdToTalk)

    init(transport: any DictationHotkeyTransport, observeConnectionChanges: Bool = true,
         sleepForRecovery: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.sleepForRecovery = sleepForRecovery
        transport.dictationInputHandler = { [weak self] event in self?.handleEventTapInput(event) }
        if observeConnectionChanges {
            observers.append(NotificationCenter.default.addObserver(forName: .helperConnectionStateChanged,
                object: nil, queue: .main) { [weak self] notification in
                let failure = notification.userInfo?["failure"] as? HelperConnectionFailure
                Task { @MainActor in
                    guard let self else { return }
                    if let failure { self.helperConnectionLost(failure) }
                    else { await self.refreshReadiness() }
                }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .accessibilityAuthorizationChanged,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refreshReadiness() }
            })
        }
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    var activationMode: DictationActivationMode { machine.isVoiceLocked ? .voiceMode : machine.mode }
    var isMonitoring: Bool { active }

    func cancelCurrentSession() {
        activationTask?.cancel()
        activationTask = nil
        _ = machine.reset()
        apply(.cancelDictation)
    }

    func adoptVoiceModeSession() {
        activationTask?.cancel()
        activationTask = nil
        machine.adoptVoiceModeSession()
    }

    func rejectCurrentDictationStart() {
        activationTask?.cancel()
        activationTask = nil
        machine.rejectDictationStart()
        _ = machine.setMode(.holdToTalk)
    }

    func accessibilityAuthorizationWasRevoked() {
        guard accessibilityState != .requesting else { return }
        recoveryPolicy.invalidateStartAttempts()
        recoveryTask?.cancel()
        recoveryTask = nil
        invalidateLease()
        cancelCurrentSession()
        accessibilityState = .notTrusted
        shortcutReadiness = .awaitingAccessibility
        if desiredEnabled { scheduleRecovery(reason: "accessibility required") }
    }

    #if DEBUG
    func consumedVoiceLockPressesForTesting() async -> UInt64 {
        guard let request = eventGate.requestID else { return 0 }
        let result = try? await transport.dictationTapDiagnostics(requestID: request, recoverDisabled: false)
        guard request == eventGate.requestID else { return 0 }
        return result?.consumed ?? 0
    }

    func recoverDisabledEventTapForTesting() async -> Bool {
        guard let request = eventGate.requestID else { return false }
        let result = try? await transport.dictationTapDiagnostics(requestID: request, recoverDisabled: true)
        guard request == eventGate.requestID else { return false }
        if result?.enabled == true { resetShortcutState(preservingVoiceMode: true) }
        await refreshReadiness()
        return isMonitoring
    }
    #endif

    func start(promptIfNeeded: Bool = false) async {
        guard !Task.isCancelled else { return }
        desiredEnabled = true
        if startRequests.enqueue(promptIfNeeded: promptIfNeeded) {
            reconciliationGeneration &+= 1
            let generation = reconciliationGeneration
            reconciliationTask = Task { [weak self] in
                guard let self else { return }
                while self.reconciliationGeneration == generation,
                      let prompt = self.startRequests.nextRequest() {
                    await self.performStart(promptIfNeeded: prompt)
                }
                if self.reconciliationGeneration == generation { self.reconciliationTask = nil }
            }
        }
        await reconciliationTask?.value
    }

    func refreshReadiness() async {
        guard !Task.isCancelled else { return }
        if desiredEnabled { await start(promptIfNeeded: false); return }
        let generation = recoveryPolicy.startGeneration
        do {
            let status = try await transport.helperPermissionStatus()
            guard !Task.isCancelled, recoveryPolicy.ownsStartAttempt(generation) else { return }
            record(status)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, recoveryPolicy.ownsStartAttempt(generation) else { return }
            helperState = .unavailable(.wrapping(error))
        }
    }

    func finishAccessibilityRequest() async {
        if accessibilityState == .requesting { accessibilityState = .notTrusted }
        await recoverIfNeeded()
    }

    private func performStart(promptIfNeeded: Bool) async {
        guard desiredEnabled else { return }
        recoveryTask?.cancel()
        recoveryTask = nil
        let generation = recoveryPolicy.beginStartAttempt()
        if !active { shortcutReadiness = .checking }
        do {
            var permission = try await transport.helperPermissionStatus()
            guard owns(generation) else { return }
            if let previous = eventGate.helperInstanceID, previous != permission.instanceID {
                invalidateLease()
                cancelCurrentSession()
            }
            record(permission)
            if !permission.accessibilityAuthorized, promptIfNeeded, accessibilityState != .requesting {
                accessibilityState = .requesting
                permission = try await transport.requestHelperAccessibility()
                guard owns(generation) else { return }
                record(permission)
            }
            guard permission.accessibilityAuthorized else {
                invalidateLease()
                shortcutReadiness = .awaitingAccessibility
                scheduleRecovery(reason: "awaiting accessibility")
                return
            }
            if let request = eventGate.requestID {
                let status = try await transport.dictationTapStatus(requestID: request)
                guard owns(generation), request == eventGate.requestID else { return }
                if status.helper.instanceID == permission.instanceID, status.state == .enabled {
                    active = true
                    shortcutReadiness = .ready
                    recoveryPolicy.recordSuccess()
                    return
                }
                invalidateLease()
                if status.state == .stopped || status.helper.instanceID != permission.instanceID {
                    cancelCurrentSession()
                } else {
                    resetShortcutState(preservingVoiceMode: true)
                }
            }
            let request = UUID()
            eventGate.begin(requestID: request, helperInstanceID: permission.instanceID)
            let result = try await transport.startDictationTap(requestID: request)
            guard owns(generation), eventGate.requestID == request else {
                try? await transport.stopDictationTap(requestID: request)
                return
            }
            record(result.helper)
            guard result.helper.instanceID == permission.instanceID else { throw HelperConnectionFailure.invalidated }
            guard result.state == .enabled else {
                invalidateLease()
                shortcutReadiness = result.state == .accessibilityRequired ? .awaitingAccessibility : .unavailable(.tap(result.state))
                scheduleRecovery(reason: "helper tap unavailable")
                return
            }
            active = true
            shortcutReadiness = .ready
            logger.notice("monitor started chord=control+option owner=helper")
            recoveryPolicy.recordSuccess()
        } catch is CancellationError {
            guard owns(generation) else { return }
            scheduleRecovery(reason: "shortcut check cancelled")
        } catch {
            guard owns(generation) else { return }
            let failure = HelperConnectionFailure.wrapping(error)
            if failure == .timedOut {
                if !active {
                    invalidateLease()
                    helperState = .unavailable(failure)
                    shortcutReadiness = .unavailable(.helper(failure))
                }
                scheduleRecovery(reason: "helper status timed out")
            } else {
                helperConnectionLost(failure)
            }
        }
    }

    func recoverIfNeeded() async {
        resetShortcutState(preservingVoiceMode: true)
        await refreshReadiness()
    }

    func stop() {
        desiredEnabled = false
        recoveryPolicy.invalidateStartAttempts()
        reconciliationGeneration &+= 1
        reconciliationTask?.cancel()
        reconciliationTask = nil
        startRequests = DictationEventTapStartRequestPolicy()
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryPolicy.recordSuccess()
        cancelCurrentSession()
        invalidateLease()
        shortcutReadiness = .stopped
    }

    private func owns(_ generation: UInt) -> Bool {
        desiredEnabled && recoveryPolicy.ownsStartAttempt(generation)
    }

    private func record(_ permission: HelperPermissionStatus) {
        helperState = .available(permission)
        if permission.accessibilityAuthorized { accessibilityState = .trusted }
        else if accessibilityState != .requesting { accessibilityState = .notTrusted }
    }

    private func helperConnectionLost(_ failure: HelperConnectionFailure) {
        recoveryPolicy.invalidateStartAttempts()
        recoveryTask?.cancel()
        recoveryTask = nil
        invalidateLease()
        cancelCurrentSession()
        helperState = .unavailable(failure)
        shortcutReadiness = .unavailable(.helper(failure))
        if desiredEnabled { scheduleRecovery(reason: "helper connection unavailable") }
    }

    private func invalidateLease() {
        let request = eventGate.requestID
        eventGate.invalidate()
        active = false
        if let request { Task { [transport] in try? await transport.stopDictationTap(requestID: request) } }
    }

    private func handleEventTapInput(_ event: DictationTapEvent) {
        guard desiredEnabled, let contiguous = eventGate.accept(event) else { return }
        guard contiguous else {
            resetShortcutState(preservingVoiceMode: true)
            Task { [weak self] in await self?.refreshReadiness() }
            return
        }
        switch event.input {
        case .tapDisabled(let reenabled):
            resetShortcutState(preservingVoiceMode: true)
            if !reenabled {
                invalidateLease()
                shortcutReadiness = .unavailable(.tap(.enableFailed))
                scheduleRecovery(reason: "helper tap remained disabled")
            }
        case .flagsChanged(let exact, let down, let disallowed):
            apply(machine.handle(.flagsChanged(isExactChord: exact, anyTriggerModifierDown: down, hasDisallowedModifiers: disallowed)))
        case .lockToggle: apply(machine.toggleVoiceLock())
        case .keyDown: apply(machine.handle(.keyDown))
        }
    }

    private func apply(_ action: DictationModifierShortcutStateMachine.Action) {
        switch action {
        case .none:
            break

        case .scheduleActivation:
            logger.debug("event=arming chord=control+option")
            activationTask?.cancel()
            let delay = activationDelay
            activationTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self else { return }
                self.activationTask = nil
                self.apply(self.machine.handle(.activationDelayElapsed))
            }

        case .cancelScheduledActivation:
            logger.debug("event=disarmed chord=control+option")
            activationTask?.cancel()
            activationTask = nil

        case .beginVoiceMode, .lockVoiceMode:
            activationTask?.cancel()
            activationTask = nil
            if action == .beginVoiceMode {
                GojoDictationService.shared.startVoiceMode()
            } else {
                GojoDictationService.sendShortcutEvent(.lockVoiceMode)
            }

        case .beginDictation:
            logger.notice("event=keyDown chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.shared.beginShortcut()

        case .finishDictation:
            logger.notice("event=keyUp chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.sendShortcutEvent(.keyUp)

        case .cancelDictation:
            logger.notice("event=cancel chord=control+option")
            GojoDictationService.sendShortcutEvent(.cancel)
        }
    }

    private func resetShortcutState(preservingVoiceMode: Bool = false) {
        let action = preservingVoiceMode ? machine.recoverGesture() : machine.reset()
        activationTask?.cancel()
        activationTask = nil
        apply(action)
    }

    private func scheduleRecovery(reason: String) {
        guard desiredEnabled, recoveryTask == nil else { return }
        let delay = recoveryPolicy.nextRetryDelayMilliseconds()
        let generation = recoveryPolicy.startGeneration
        logger.debug("shortcut retry reason=\(reason, privacy: .public) delayMs=\(delay, privacy: .public)")
        let sleepForRecovery = sleepForRecovery
        recoveryTask = Task { [weak self] in
            do { try await sleepForRecovery(.milliseconds(Int64(delay))) } catch { return }
            guard let self, self.desiredEnabled, self.recoveryPolicy.ownsStartAttempt(generation) else { return }
            self.recoveryTask = nil
            await self.start(promptIfNeeded: false)
        }
    }
}
