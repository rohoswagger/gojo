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

    private var eventTapHost: DictationModifierEventTapHost?
    private var eventTapGeneration: UInt64 = 0
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
        eventTapHost?.isEnabledSnapshot ?? false
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
        guard let eventTapHost else { return false }
        guard eventTapHost.disableAndRecoverForTesting() else { return false }
        recoverFromDisabledEventTap()
        return isMonitoring
    }
    #endif

    func start(promptIfNeeded: Bool = false) async {
        if eventTapHost?.isEnabledSnapshot == true {
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
        if eventTapHost?.isEnabledSnapshot == true {
            recoveryTask?.cancel()
            recoveryTask = nil
            recoveryPolicy.recordSuccess()
            return
        }
        recoveryTask?.cancel()
        recoveryTask = nil
        if eventTapHost != nil {
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

        guard eventTapHost == nil, recoveryPolicy.ownsStartAttempt(generation) else { return }
        let startResult = await createEventTap()
        guard startResult == .started else {
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
        if let eventTapHost {
            if eventTapHost.isEnabledSnapshot {
                recoveryTask?.cancel()
                recoveryTask = nil
                recoveryPolicy.recordSuccess()
                return
            }

            if await eventTapHost.enable() {
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

    private enum EventTapStartResult {
        case started
        case failed
    }

    private func createEventTap() async -> EventTapStartResult {
        eventTapGeneration &+= 1
        let generation = eventTapGeneration
        let host = DictationModifierEventTapHost(
            generation: generation,
            logger: logger
        ) { [weak self] generation, input in
            DispatchQueue.main.async { [weak self] in
                self?.handleEventTapInput(input, generation: generation)
            }
        }
        eventTapHost = host
        switch await host.start() {
        case .started:
            logger.notice("monitor started chord=control+option")
            return .started
        case .tapUnavailable:
            eventTapHost = nil
            logger.error("monitor start failed: event tap unavailable")
            return .failed
        case .runLoopSourceUnavailable:
            eventTapHost = nil
            logger.error("monitor start failed: run loop source unavailable")
            return .failed
        case .enableFailed:
            eventTapHost = nil
            logger.error("monitor start failed: event tap did not enable")
            return .failed
        }
    }

    private func handleEventTapInput(
        _ input: DictationModifierEventTapInput,
        generation: UInt64
    ) {
        guard generation == eventTapGeneration else { return }
        switch input {
        case .tapDisabled:
            recoverFromDisabledEventTap()

        case .flagsChanged(
            let isExactChord,
            let anyTriggerModifierDown,
            let hasDisallowedModifiers
        ):
            apply(machine.handle(.flagsChanged(
                isExactChord: isExactChord,
                anyTriggerModifierDown: anyTriggerModifierDown,
                hasDisallowedModifiers: hasDisallowedModifiers
            )))

        case .keyDown:
            apply(machine.handle(.keyDown))
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
        if let eventTapHost {
            if eventTapHost.isEnabledSnapshot {
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
        eventTapGeneration &+= 1
        eventTapHost?.stop()
        eventTapHost = nil
    }
}

private enum DictationModifierEventTapInput: Sendable {
    case tapDisabled
    case flagsChanged(
        isExactChord: Bool,
        anyTriggerModifierDown: Bool,
        hasDisallowedModifiers: Bool
    )
    case keyDown
}

private final class DictationModifierEventTapContext: @unchecked Sendable {
    let generation: UInt64
    private let logger: Logger
    private let forwardInput: @Sendable (UInt64, DictationModifierEventTapInput) -> Void
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var enabled = false

    init(
        generation: UInt64,
        logger: Logger,
        forwardInput: @escaping @Sendable (UInt64, DictationModifierEventTapInput) -> Void
    ) {
        self.generation = generation
        self.logger = logger
        self.forwardInput = forwardInput
    }

    var isEnabledSnapshot: Bool {
        lock.withLock { enabled }
    }

    func setEventTap(_ eventTap: CFMachPort?) {
        lock.withLock {
            self.eventTap = eventTap
        }
    }

    func setEnabled(_ enabled: Bool) {
        lock.withLock {
            self.enabled = enabled
        }
    }

    func reenableEventTapImmediately() {
        let tap = lock.withLock { eventTap }
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: tap)
        setEnabled(isEnabled)
        if isEnabled {
            logger.notice("monitor event tap re-enabled inside disabled callback")
        } else {
            logger.error("monitor event tap did not re-enable inside disabled callback")
        }
    }

    func forward(_ input: DictationModifierEventTapInput) {
        forwardInput(generation, input)
    }
}

private final class DictationModifierEventTapHost: @unchecked Sendable {
    enum StartResult {
        case started
        case tapUnavailable
        case runLoopSourceUnavailable
        case enableFailed
    }

    private let context: DictationModifierEventTapContext
    private let logger: Logger
    private let stateLock = NSLock()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startContinuation: CheckedContinuation<StartResult, Never>?
    private var shouldStop = false

    init(
        generation: UInt64,
        logger: Logger,
        forwardInput: @escaping @Sendable (UInt64, DictationModifierEventTapInput) -> Void
    ) {
        self.logger = logger
        self.context = DictationModifierEventTapContext(
            generation: generation,
            logger: logger,
            forwardInput: forwardInput
        )
    }

    var isEnabledSnapshot: Bool {
        context.isEnabledSnapshot
    }

    func start() async -> StartResult {
        await withCheckedContinuation { continuation in
            stateLock.withLock {
                startContinuation = continuation
                let thread = Thread { [weak self] in
                    self?.runLoopThreadMain()
                }
                thread.name = "gojo.dictation.modifier-event-tap"
                thread.qualityOfService = .userInteractive
                self.thread = thread
                thread.start()
            }
        }
    }

    func enable() async -> Bool {
        await performOnRunLoop { host in
            guard let eventTap = host.eventTap else {
                host.context.setEnabled(false)
                return false
            }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            let isEnabled = CGEvent.tapIsEnabled(tap: eventTap)
            host.context.setEnabled(isEnabled)
            return isEnabled
        } ?? false
    }

    func stop() {
        let runLoop = stateLock.withLock { () -> CFRunLoop? in
            shouldStop = true
            return self.runLoop
        }
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            tearDownOnRunLoop()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    #if DEBUG
    func disableAndRecoverForTesting() -> Bool {
        performOnRunLoopSync { host in
            guard let eventTap = host.eventTap else {
                host.context.setEnabled(false)
                return false
            }
            CGEvent.tapEnable(tap: eventTap, enable: false)
            guard !CGEvent.tapIsEnabled(tap: eventTap) else { return false }
            host.context.reenableEventTapImmediately()
            return host.context.isEnabledSnapshot
        } ?? false
    }
    #endif

    private func runLoopThreadMain() {
        let currentRunLoop = CFRunLoopGetCurrent()
        stateLock.withLock {
            runLoop = currentRunLoop
        }
        let result = createOnRunLoop()
        let continuation = stateLock.withLock { () -> CheckedContinuation<StartResult, Never>? in
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        continuation?.resume(returning: result)

        guard result == .started else {
            tearDownOnRunLoop()
            return
        }

        if stateLock.withLock({ shouldStop }) {
            tearDownOnRunLoop()
            return
        }

        CFRunLoopRun()
        tearDownOnRunLoop()
    }

    private func createOnRunLoop() -> StartResult {
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
        )
        guard let createdEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dictationModifierEventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(context).toOpaque())
        ) else {
            return .tapUnavailable
        }

        guard let createdRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            createdEventTap,
            0
        ) else {
            CGEvent.tapEnable(tap: createdEventTap, enable: false)
            CFMachPortInvalidate(createdEventTap)
            return .runLoopSourceUnavailable
        }

        context.setEventTap(createdEventTap)
        eventTap = createdEventTap
        runLoopSource = createdRunLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), createdRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: createdEventTap, enable: true)
        let isEnabled = CGEvent.tapIsEnabled(tap: createdEventTap)
        context.setEnabled(isEnabled)
        return isEnabled ? .started : .enableFailed
    }

    private func performOnRunLoop<T: Sendable>(
        _ operation: @escaping @Sendable (DictationModifierEventTapHost) -> T
    ) async -> T? {
        await withCheckedContinuation { continuation in
            guard let runLoop = stateLock.withLock({ self.runLoop }) else {
                continuation.resume(returning: nil)
                return
            }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: operation(self))
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func performOnRunLoopSync<T>(
        _ operation: @escaping (DictationModifierEventTapHost) -> T
    ) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = OptionalLockedBox<T>()
        guard let runLoop = stateLock.withLock({ self.runLoop }) else { return nil }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            if let self {
                box.set(operation(self))
            }
            semaphore.signal()
        }
        CFRunLoopWakeUp(runLoop)
        semaphore.wait()
        return box.value
    }

    private func tearDownOnRunLoop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            context.setEnabled(false)
            context.setEventTap(nil)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        stateLock.withLock {
            runLoop = nil
        }
    }
}

private final class OptionalLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value?

    init(_ value: Value? = nil) {
        storedValue = value
    }

    var value: Value? {
        lock.withLock { storedValue }
    }

    func set(_ value: Value) {
        lock.withLock {
            storedValue = value
        }
    }
}

private func dictationModifierEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let context = Unmanaged<DictationModifierEventTapContext>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        context.reenableEventTapImmediately()
        context.forward(.tapDisabled)

    case .flagsChanged:
        let flags = event.flags
        let controlDown = flags.contains(.maskControl)
        let optionDown = flags.contains(.maskAlternate)
        let disallowedFlags: CGEventFlags = [.maskCommand, .maskShift, .maskSecondaryFn]
        let hasDisallowedModifiers = !flags.intersection(disallowedFlags).isEmpty
        context.forward(.flagsChanged(
            isExactChord: controlDown && optionDown && !hasDisallowedModifiers,
            anyTriggerModifierDown: controlDown || optionDown,
            hasDisallowedModifiers: hasDisallowedModifiers
        ))

    case .keyDown:
        context.forward(.keyDown)

    default:
        break
    }

    return Unmanaged.passUnretained(event)
}
