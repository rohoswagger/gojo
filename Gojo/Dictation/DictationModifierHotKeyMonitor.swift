import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation
import os

@MainActor
final class DictationModifierHotKeyMonitor {
    static let shared = DictationModifierHotKeyMonitor()

    private let logger = Logger(
        subsystem: "rohoswagger.gojo.dictation",
        category: "shortcut"
    )
    private let activationDelay: Duration = .milliseconds(75)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryPolicy = DictationEventTapRecoveryPolicy()
    private var startRequests = DictationEventTapStartRequestPolicy()
    private var machine = DictationModifierShortcutStateMachine(
        mode: DictationActivationMode.saved()
    )

    private init() {}

    var activationMode: DictationActivationMode {
        machine.mode
    }

    var isMonitoring: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func setActivationMode(_ mode: DictationActivationMode) {
        mode.save()
        let action = machine.setMode(mode)
        if action != .none {
            activationTask?.cancel()
            activationTask = nil
        }
        apply(action)
    }

    func cancelCurrentSession() {
        resetShortcutState()
    }

    /// Re-arms tap-to-talk after the service declines a begin request during
    /// preflight. Unlike cancellation, rejection must not emit another service
    /// event because no dictation session was admitted.
    func rejectCurrentDictationStart() {
        activationTask?.cancel()
        activationTask = nil
        machine.rejectDictationStart()
    }

    /// A negative authorization notification can be emitted by the very check
    /// that is about to show the first-use prompt. Do not let that notification
    /// cancel the in-flight prompting request; a completed start attempt will
    /// leave no tap behind if authorization remains unavailable.
    func accessibilityAuthorizationWasRevoked() {
        guard !startRequests.isRunning else { return }
        stop()
    }

    #if DEBUG
    /// Allows the live shortcut regression to verify recovery from the same
    /// disabled-tap state macOS can leave behind after sleep or a timeout.
    func recoverDisabledEventTapForTesting() -> Bool {
        guard let eventTap else { return false }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        guard !CGEvent.tapIsEnabled(tap: eventTap) else { return false }
        recoverFromDisabledEventTap()
        return isMonitoring
    }
    #endif

    func start(promptIfNeeded: Bool = false) async {
        if let eventTap, CGEvent.tapIsEnabled(tap: eventTap) {
            recoveryTask?.cancel()
            recoveryTask = nil
            recoveryPolicy.recordSuccess()
            return
        }

        guard startRequests.enqueue(promptIfNeeded: promptIfNeeded) else { return }
        while let pendingPromptIfNeeded = startRequests.nextRequest() {
            await performStart(promptIfNeeded: pendingPromptIfNeeded)
        }
    }

    private func performStart(promptIfNeeded: Bool) async {
        if let eventTap, CGEvent.tapIsEnabled(tap: eventTap) {
            recoveryTask?.cancel()
            recoveryTask = nil
            recoveryPolicy.recordSuccess()
            return
        }
        recoveryTask?.cancel()
        recoveryTask = nil
        if eventTap != nil {
            logger.error("monitor found a disabled event tap; recreating")
            resetShortcutState()
            tearDownEventTap()
        }

        let generation = recoveryPolicy.beginStartAttempt()

        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        guard recoveryPolicy.ownsStartAttempt(generation) else { return }
        if !authorized {
            guard promptIfNeeded else {
                logger.error("monitor start failed: accessibility permission missing")
                return
            }
            let granted = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true)
            guard recoveryPolicy.ownsStartAttempt(generation) else { return }
            guard granted else {
                logger.error("monitor start failed: accessibility permission denied")
                return
            }
        }

        guard eventTap == nil, recoveryPolicy.ownsStartAttempt(generation) else { return }
        guard createEventTap() else {
            scheduleRecovery(reason: "event tap unavailable")
            return
        }
        recoveryPolicy.recordSuccess()
    }

    /// Revalidates the tap after lifecycle transitions where macOS can silently
    /// invalidate CGEvent taps (app activation, screen unlock, and system wake).
    func recoverIfNeeded() async {
        // A tap can remain enabled even if its final modifier-release event was
        // lost during a lifecycle transition. Always clear the gesture state.
        resetShortcutState()
        if let eventTap {
            if CGEvent.tapIsEnabled(tap: eventTap) {
                recoveryTask?.cancel()
                recoveryTask = nil
                recoveryPolicy.recordSuccess()
                return
            }

            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                recoveryTask?.cancel()
                recoveryTask = nil
                recoveryPolicy.recordSuccess()
                logger.notice("monitor recovered by re-enabling event tap")
                return
            }

            logger.error("monitor recovery could not re-enable event tap; recreating")
            tearDownEventTap()
        }

        await start(promptIfNeeded: false)
    }

    func stop() {
        recoveryPolicy.invalidateStartAttempts()
        startRequests.cancelPendingRequests()
        recoveryTask?.cancel()
        recoveryTask = nil
        recoveryPolicy.recordSuccess()
        resetShortcutState()
        tearDownEventTap()
    }

    @discardableResult
    private func createEventTap() -> Bool {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
        )
        guard let createdEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DictationModifierHotKeyMonitor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            logger.error("monitor start failed: event tap unavailable")
            return false
        }

        guard let createdRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            createdEventTap,
            0
        ) else {
            CGEvent.tapEnable(tap: createdEventTap, enable: false)
            CFMachPortInvalidate(createdEventTap)
            logger.error("monitor start failed: run loop source unavailable")
            return false
        }

        eventTap = createdEventTap
        runLoopSource = createdRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), createdRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdEventTap, enable: true)
        guard CGEvent.tapIsEnabled(tap: createdEventTap) else {
            tearDownEventTap()
            logger.error("monitor start failed: event tap did not enable")
            return false
        }
        logger.notice("monitor started chord=control+option")
        return true
    }

    nonisolated private func handle(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        MainActor.assumeIsolated {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                recoverFromDisabledEventTap()
                return Unmanaged.passUnretained(event)
            }

            switch type {
            case .flagsChanged:
                let flags = event.flags
                let controlDown = flags.contains(.maskControl)
                let optionDown = flags.contains(.maskAlternate)
                let disallowedFlags: CGEventFlags = [.maskCommand, .maskShift, .maskSecondaryFn]
                let hasDisallowedModifiers = !flags.intersection(disallowedFlags).isEmpty
                let exactChord = controlDown
                    && optionDown
                    && !hasDisallowedModifiers
                apply(machine.handle(.flagsChanged(
                    isExactChord: exactChord,
                    anyTriggerModifierDown: controlDown || optionDown,
                    hasDisallowedModifiers: hasDisallowedModifiers
                )))

            case .keyDown:
                apply(machine.handle(.keyDown))

            default:
                break
            }

            return Unmanaged.passUnretained(event)
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

        case .beginDictation:
            logger.notice("event=keyDown chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.sendShortcutEvent(.keyDown)

        case .finishDictation:
            logger.notice("event=keyUp chord=control+option mode=\(self.machine.mode.rawValue, privacy: .public)")
            GojoDictationService.sendShortcutEvent(.keyUp)

        case .cancelDictation:
            logger.notice("event=cancel chord=control+option")
            GojoDictationService.sendShortcutEvent(.cancel)
        }
    }

    private func resetShortcutState() {
        let action = machine.reset()
        activationTask?.cancel()
        activationTask = nil
        apply(action)
    }

    private func recoverFromDisabledEventTap() {
        resetShortcutState()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            if CGEvent.tapIsEnabled(tap: eventTap) {
                recoveryPolicy.recordSuccess()
                logger.notice("monitor recovered from disabled event tap")
            } else {
                logger.error("monitor could not re-enable disabled event tap")
                // Do not invalidate the Mach port while Core Graphics may still
                // be executing its callback. Recreate it on the next actor turn.
                Task { [weak self] in
                    guard let self else { return }
                    self.tearDownEventTap()
                    self.scheduleRecovery(reason: "event tap remained disabled")
                }
            }
        } else {
            scheduleRecovery(reason: "event tap callback lost its tap")
        }
    }

    private func scheduleRecovery(reason: String) {
        guard recoveryTask == nil else { return }
        let delayMilliseconds = recoveryPolicy.nextRetryDelayMilliseconds()
        let generation = recoveryPolicy.startGeneration
        logger.error(
            "monitor retry scheduled reason=\(reason, privacy: .public) delayMs=\(delayMilliseconds, privacy: .public)"
        )
        recoveryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(Int64(delayMilliseconds)))
            } catch {
                return
            }
            guard let self, self.recoveryPolicy.ownsStartAttempt(generation) else { return }
            self.recoveryTask = nil
            await self.start(promptIfNeeded: false)
        }
    }

    private func tearDownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }
}
