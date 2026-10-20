import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation
import os

private final class DictationModifierEventTapContext: @unchecked Sendable {
    let generation: UInt64
    private let logger: Logger
    private let forwardInput: @Sendable (UInt64, DictationModifierEventTapInput) -> Void
    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var enabled = false
    private var active = true
    private var suppressSpaceUp = false
    #if DEBUG
    private var consumedLockPresses: UInt64 = 0
    var consumedVoiceLockPresses: UInt64 { lock.withLock { consumedLockPresses } }
    #endif

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
        lock.withLock {
            guard active, enabled, let eventTap, CFMachPortIsValid(eventTap) else { return false }
            return CGEvent.tapIsEnabled(tap: eventTap)
        }
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

    func deactivate() { lock.withLock { active = false; enabled = false } }

    func consumeSpace(type: CGEventType, event: CGEvent) -> Bool {
        guard lock.withLock({ active }) else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == 49 else { return false }
        if type == .keyUp {
            let suppressed = suppressSpaceUp
            suppressSpaceUp = false
            return suppressed
        }
        if suppressSpaceUp { return true }
        let modifiers = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift, .maskSecondaryFn])
        guard modifiers == [.maskControl, .maskAlternate] else { return false }
        if !suppressSpaceUp, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            #if DEBUG
            lock.withLock { consumedLockPresses &+= 1 }
            #endif
            forward(.lockToggle)
        }
        suppressSpaceUp = true
        return true
    }

    func forward(_ input: DictationModifierEventTapInput) {
        guard lock.withLock({ active }) else { return }
        forwardInput(generation, input)
    }
}

final class DictationModifierEventTapHost: DictationEventTapHosting, @unchecked Sendable {
    typealias StartResult = DictationEventTapHostStartResult

    private let context: DictationModifierEventTapContext
    private let logger: Logger
    private let stateLock = NSLock()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startContinuation: CheckedContinuation<StartResult, Never>?
    private var shouldStop = false
    private var pendingRunLoopOperations: [UUID: () -> Void] = [:]

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

    #if DEBUG
    var consumedVoiceLockPresses: UInt64 { context.consumedVoiceLockPresses }
    #endif

    var isEnabledSnapshot: Bool {
        context.isEnabledSnapshot
    }

    func start() async -> StartResult {
        await withCheckedContinuation { continuation in
            stateLock.withLock {
                guard !shouldStop else { continuation.resume(returning: .stopped); return }
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

    func enabledStatus() async -> Bool {
        await performOnRunLoop { $0.context.isEnabledSnapshot } ?? false
    }

    func stop() {
        context.deactivate()
        let stopped = stateLock.withLock { () -> (CFRunLoop?, CheckedContinuation<StartResult, Never>?, [() -> Void]) in
            shouldStop = true
            let continuation = startContinuation
            startContinuation = nil
            let pending = Array(pendingRunLoopOperations.values)
            pendingRunLoopOperations.removeAll()
            return (runLoop, continuation, pending)
        }
        stopped.1?.resume(returning: .stopped)
        stopped.2.forEach { $0() }
        guard let runLoop = stopped.0 else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            tearDownOnRunLoop()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    #if DEBUG
    func disableAndRecoverForTesting() async -> Bool {
        await performOnRunLoop { host in
            guard let eventTap = host.eventTap else { return false }
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
        let result: StartResult = stateLock.withLock({ shouldStop }) ? .stopped : createOnRunLoop()
        let continuation = stateLock.withLock { () -> CheckedContinuation<StartResult, Never>? in
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        continuation?.resume(returning: stateLock.withLock({ shouldStop }) ? .stopped : result)

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
                | (1 << CGEventType.keyUp.rawValue)
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
        let result = DictationRunLoopResult<T>()
        let identifier = UUID()
        return await withCheckedContinuation { continuation in
            result.install(continuation)
            let runLoop = stateLock.withLock { () -> CFRunLoop? in
                guard !shouldStop, let runLoop = self.runLoop else { return nil }
                pendingRunLoopOperations[identifier] = { result.finish(nil) }
                return runLoop
            }
            guard let runLoop else { result.finish(nil); return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                guard let self else { result.finish(nil); return }
                let stopped = self.stateLock.withLock { () -> Bool in
                    self.pendingRunLoopOperations.removeValue(forKey: identifier)
                    return self.shouldStop
                }
                result.finish(stopped ? nil : operation(self))
            }
            CFRunLoopWakeUp(runLoop)
        }
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
        let pending = stateLock.withLock { () -> [() -> Void] in
            runLoop = nil
            let pending = Array(pendingRunLoopOperations.values)
            pendingRunLoopOperations.removeAll()
            return pending
        }
        pending.forEach { $0() }
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

    if (type == .keyDown || type == .keyUp), context.consumeSpace(type: type, event: event) {
        return nil
    }

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        context.reenableEventTapImmediately()
        context.forward(.tapDisabled(reenabled: context.isEnabledSnapshot))

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

enum DictationEventTapHostStartResult: Equatable {
    case started, stopped, tapUnavailable, runLoopSourceUnavailable, enableFailed

    var state: DictationTapState {
        switch self {
        case .started: return .enabled
        case .stopped: return .stopped
        case .tapUnavailable: return .creationFailed
        case .runLoopSourceUnavailable: return .runLoopSourceFailed
        case .enableFailed: return .enableFailed
        }
    }
}

protocol DictationEventTapHosting: AnyObject, Sendable {
    var isEnabledSnapshot: Bool { get }
    func enabledStatus() async -> Bool
    func start() async -> DictationEventTapHostStartResult
    func stop()
    #if DEBUG
    var consumedVoiceLockPresses: UInt64 { get }
    func disableAndRecoverForTesting() async -> Bool
    #endif
}

final class DictationHotkeyTapService: @unchecked Sendable {
    static let shared = DictationHotkeyTapService()
    static let helperInstanceID = UUID()
    typealias TimeoutScheduler = @Sendable (@escaping @Sendable () -> Void) -> Void
    typealias HostFactory = @Sendable (UInt64, @escaping @Sendable (UInt64, DictationModifierEventTapInput) -> Void) -> any DictationEventTapHosting

    private struct Lease {
        let owner: UUID
        let request: UUID
        let generation: UInt64
        let host: any DictationEventTapHosting
        let send: @Sendable (DictationTapEvent, @escaping @Sendable (Bool) -> Void) -> Void
        var sequence: UInt64 = 0
        var pending: [DictationTapEvent] = []
        var delivering = false
    }

    private let lock = NSLock()
    private let deliveryQueue = DispatchQueue(label: "gojo.dictation.helper-input")
    private let trust: @Sendable () -> Bool
    private let makeHost: HostFactory
    private let scheduleAcknowledgementTimeout: TimeoutScheduler
    private var owners: Set<UUID> = []
    private var canceledRequests: [UUID: Set<UUID>] = [:]
    private var connectionInvalidationHandlers: [UUID: @Sendable () -> Void] = [:]
    private var generation: UInt64 = 0
    private var lease: Lease?

    init(trust: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }, hostFactory: HostFactory? = nil,
         scheduleAcknowledgementTimeout: @escaping TimeoutScheduler = { timeout in
             DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
         }) {
        self.trust = trust
        self.scheduleAcknowledgementTimeout = scheduleAcknowledgementTimeout
        makeHost = hostFactory ?? { generation, forward in
            DictationModifierEventTapHost(generation: generation,
                logger: Logger(subsystem: "rohoswagger.gojo.dictation", category: "helper-shortcut"),
                forwardInput: forward)
        }
    }

    var permissionStatus: HelperPermissionStatus {
        HelperPermissionStatus(instanceID: Self.helperInstanceID, accessibilityAuthorized: trust())
    }

    func register(owner: UUID, invalidateConnection: @escaping @Sendable () -> Void = {}) {
        lock.withLock {
            owners.insert(owner)
            connectionInvalidationHandlers[owner] = invalidateConnection
        }
    }

    func invalidate(owner: UUID) {
        let oldHost = lock.withLock { () -> (any DictationEventTapHosting)? in
            owners.remove(owner)
            canceledRequests.removeValue(forKey: owner)
            connectionInvalidationHandlers.removeValue(forKey: owner)
            guard lease?.owner == owner else { return nil }
            let host = lease?.host
            lease = nil
            return host
        }
        oldHost?.stop()
    }

    func start(owner: UUID, request: UUID, send: @escaping @Sendable (DictationTapEvent, @escaping @Sendable (Bool) -> Void) -> Void) async -> DictationTapStatus {
        let permission = permissionStatus
        guard permission.accessibilityAuthorized else {
            stop(owner: owner, request: request)
            return DictationTapStatus(requestID: request, helper: permission, state: .accessibilityRequired)
        }
        let replacement = lock.withLock { () -> (host: (any DictationEventTapHosting)?, old: (any DictationEventTapHosting)?, generation: UInt64) in
            guard owners.contains(owner), canceledRequests[owner]?.contains(request) != true else { return (nil, nil, generation) }
            if let lease, lease.owner == owner, lease.request == request {
                return (nil, nil, lease.generation)
            }
            let old = lease?.host
            generation &+= 1
            let newGeneration = generation
            let host = makeHost(newGeneration) { [weak self] generation, input in
                self?.forward(input, generation: generation)
            }
            lease = Lease(owner: owner, request: request, generation: newGeneration, host: host, send: send)
            return (host, old, newGeneration)
        }
        replacement.old?.stop()
        guard let host = replacement.host else { return await status(owner: owner, request: request) }
        let result = await host.start()
        let owns = lock.withLock { lease?.owner == owner && lease?.request == request && lease?.generation == replacement.generation }
        guard owns else {
            host.stop()
            return DictationTapStatus(requestID: request, helper: permissionStatus, state: .stopped)
        }
        if result != .started {
            stop(owner: owner, request: request)
        }
        return DictationTapStatus(requestID: request, helper: permissionStatus, state: result.state)
    }

    func stop(owner: UUID, request: UUID) {
        let stopped = lock.withLock { () -> ((any DictationEventTapHosting)?, (@Sendable () -> Void)?) in
            var exhausted: (@Sendable () -> Void)?
            if owners.contains(owner) {
                canceledRequests[owner, default: []].insert(request)
                if canceledRequests[owner, default: []].count >= 1_024 {
                    // Reconnect before discarding replay guards for this connection.
                    owners.remove(owner)
                    canceledRequests.removeValue(forKey: owner)
                    exhausted = connectionInvalidationHandlers.removeValue(forKey: owner)
                }
            }
            guard lease?.owner == owner, lease?.request == request || exhausted != nil else { return (nil, exhausted) }
            let host = lease?.host
            lease = nil
            return (host, exhausted)
        }
        stopped.0?.stop()
        stopped.1?()
    }

    func status(owner: UUID, request: UUID) async -> DictationTapStatus {
        let current = lock.withLock { () -> Lease? in
            guard let lease, lease.owner == owner, lease.request == request else { return nil }
            return lease
        }
        guard let current else { return DictationTapStatus(requestID: request, helper: permissionStatus, state: .stopped) }
        let enabled = await current.host.enabledStatus()
        let owns = lock.withLock { lease?.generation == current.generation }
        return DictationTapStatus(requestID: request, helper: permissionStatus, state: owns ? (enabled ? .enabled : .enableFailed) : .stopped)
    }

    #if DEBUG
    func diagnostics(owner: UUID, request: UUID, recoverDisabled: Bool) async -> NSDictionary {
        let host = lock.withLock { () -> (any DictationEventTapHosting)? in
            guard let lease, lease.owner == owner, lease.request == request else { return nil }
            return lease.host
        }
        guard let host else { return ["enabled": false, "consumed": NSNumber(value: UInt64(0))] }
        if recoverDisabled { _ = await host.disableAndRecoverForTesting() }
        let current = lock.withLock { lease?.owner == owner && lease?.request == request && lease?.host === host }
        return ["enabled": current && host.isEnabledSnapshot,
                "consumed": NSNumber(value: current ? host.consumedVoiceLockPresses : 0)]
    }
    #endif

    private func forward(_ input: DictationModifierEventTapInput, generation: UInt64) {
        let schedule = lock.withLock { () -> Bool in
            guard var lease, lease.generation == generation else { return false }
            lease.sequence &+= 1
            // A gap forces the app to discard an incomplete gesture and recheck the tap.
            let event = DictationTapEvent(requestID: lease.request, helperInstanceID: Self.helperInstanceID,
                sequence: lease.sequence, input: input)
            if lease.pending.count < 64 { lease.pending.append(event) }
            else { lease.pending[lease.pending.count - 1] = event }
            let schedule = !lease.delivering && !lease.pending.isEmpty
            if schedule { lease.delivering = true }
            self.lease = lease
            return schedule
        }
        if schedule { deliveryQueue.async { [weak self] in self?.deliverNext(generation: generation) } }
    }

    private func deliverNext(generation: UInt64) {
        let delivery = lock.withLock { () -> (DictationTapEvent, @Sendable (DictationTapEvent, @escaping @Sendable (Bool) -> Void) -> Void)? in
            guard var lease, lease.generation == generation else { return nil }
            guard !lease.pending.isEmpty else {
                lease.delivering = false
                self.lease = lease
                return nil
            }
            let event = lease.pending.removeFirst()
            self.lease = lease
            return (event, lease.send)
        }
        guard let delivery else { return }
        let acknowledged = DictationAcknowledgement()
        let finish: @Sendable (Bool) -> Void = { [weak self] delivered in
            guard acknowledged.claim(), let self else { return }
            if delivered {
                self.deliveryQueue.async { [weak self] in self?.deliverNext(generation: generation) }
            } else {
                self.failDelivery(generation: generation)
            }
        }
        scheduleAcknowledgementTimeout { finish(false) }
        delivery.1(delivery.0, finish)
    }

    private func failDelivery(generation: UInt64) {
        let failed = lock.withLock { () -> ((any DictationEventTapHosting)?, (@Sendable () -> Void)?) in
            guard let lease, lease.generation == generation else { return (nil, nil) }
            self.lease = nil
            owners.remove(lease.owner)
            canceledRequests.removeValue(forKey: lease.owner)
            return (lease.host, connectionInvalidationHandlers.removeValue(forKey: lease.owner))
        }
        failed.0?.stop()
        failed.1?()
    }
}

private final class DictationAcknowledgement: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func claim() -> Bool { lock.withLock { if completed { return false }; completed = true; return true } }
}

private final class DictationRunLoopResult<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var completed = false
    func install(_ continuation: CheckedContinuation<Value?, Never>) { lock.withLock { self.continuation = continuation } }
    func finish(_ result: Value?) {
        let pending = lock.withLock { () -> CheckedContinuation<Value?, Never>? in
            guard !completed else { return nil }
            completed = true
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume(returning: result)
    }
}
