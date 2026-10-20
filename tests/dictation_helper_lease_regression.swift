import Foundation

final class FakeTapHost: DictationEventTapHosting, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var stopped = false
    private var continuation: CheckedContinuation<DictationEventTapHostStartResult, Never>?
    let delayed: Bool
    let result: DictationEventTapHostStartResult
    let forward: @Sendable (UInt64, DictationModifierEventTapInput) -> Void
    let generation: UInt64

    init(delayed: Bool, result: DictationEventTapHostStartResult = .started, generation: UInt64,
         forward: @escaping @Sendable (UInt64, DictationModifierEventTapInput) -> Void) {
        self.delayed = delayed; self.result = result; self.generation = generation; self.forward = forward
    }
    var isEnabledSnapshot: Bool { lock.withLock { enabled && !stopped } }
    func enabledStatus() async -> Bool { isEnabledSnapshot }
    var waiting: Bool { lock.withLock { continuation != nil } }
    var wasStopped: Bool { lock.withLock { stopped } }
    func start() async -> DictationEventTapHostStartResult {
        if delayed {
            return await withCheckedContinuation { value in lock.withLock { continuation = value } }
        }
        lock.withLock { enabled = result == .started }
        return result
    }
    func complete() {
        let value = lock.withLock { () -> CheckedContinuation<DictationEventTapHostStartResult, Never>? in
            enabled = true
            let value = continuation; continuation = nil; return value
        }
        value?.resume(returning: .started)
    }
    func stop() { lock.withLock { stopped = true; enabled = false } }
    #if DEBUG
    var consumedVoiceLockPresses: UInt64 { 0 }
    func disableAndRecoverForTesting() async -> Bool { isEnabledSnapshot }
    #endif
}

final class HostStore: @unchecked Sendable {
    private let lock = NSLock()
    private var hosts: [FakeTapHost] = []
    private var received: [DictationTapEvent] = []
    func make(_ generation: UInt64, _ forward: @escaping @Sendable (UInt64, DictationModifierEventTapInput) -> Void) -> any DictationEventTapHosting {
        lock.withLock {
            let host = FakeTapHost(delayed: hosts.isEmpty, generation: generation, forward: forward)
            hosts.append(host); return host
        }
    }
    func append(_ host: FakeTapHost) { lock.withLock { hosts.append(host) } }
    var all: [FakeTapHost] { lock.withLock { hosts } }
    var events: [DictationTapEvent] { lock.withLock { received } }
    func receive(_ event: DictationTapEvent) { lock.withLock { received.append(event) } }
}

final class AcknowledgementStore: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [DictationTapEvent] = []
    private var acknowledgements: [@Sendable (Bool) -> Void] = []
    var events: [DictationTapEvent] { lock.withLock { received } }
    func receive(_ event: DictationTapEvent, acknowledge: @escaping @Sendable (Bool) -> Void) {
        lock.withLock { received.append(event); acknowledgements.append(acknowledge) }
    }
    func acknowledgeNext(delivered: Bool = true) {
        let next = lock.withLock { () -> (@Sendable (Bool) -> Void)? in
            guard !acknowledgements.isEmpty else { return nil }
            return acknowledgements.removeFirst()
        }
        next?(delivered)
    }
}

final class DeliveryDeadlineStore: @unchecked Sendable {
    private let lock = NSLock()
    private var deadlines: [@Sendable () -> Void] = []
    private var failures = 0
    var invalidations: Int { lock.withLock { failures } }
    func schedule(_ deadline: @escaping @Sendable () -> Void) { lock.withLock { deadlines.append(deadline) } }
    func invalidate() { lock.withLock { failures += 1 } }
    func fireAll() {
        let pending = lock.withLock { () -> [@Sendable () -> Void] in
            let pending = deadlines; deadlines.removeAll(); return pending
        }
        pending.forEach { $0() }
    }
}

@main
struct DictationHelperLeaseRegression {
    static func main() async throws {
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
        }
        let store = HostStore()
        let service = DictationHotkeyTapService(trust: { true }, hostFactory: { store.make($0, $1) })
        let owner = UUID(), request = UUID(), newer = UUID()
        service.register(owner: owner)
        let first = Task { await service.start(owner: owner, request: request, send: { event, acknowledge in store.receive(event); acknowledge(true) }) }
        while store.all.first?.waiting != true { await Task.yield() }
        service.stop(owner: owner, request: request)
        let second = await service.start(owner: owner, request: newer, send: { event, acknowledge in store.receive(event); acknowledge(true) })
        expect(second.state == .enabled, "New lease enables")
        store.all[0].complete()
        let late = await first.value
        expect(late.state == .stopped && store.all[0].wasStopped, "Late old start is stopped")
        service.stop(owner: owner, request: request)
        expect(await service.status(owner: owner, request: newer).state == .enabled, "Old stop cannot stop a new lease")
        _ = await service.start(owner: owner, request: request, send: { event, acknowledge in store.receive(event); acknowledge(true) })
        expect(store.all.count == 2, "Stopped request cannot be resurrected by a late start invocation")
        expect(await service.status(owner: owner, request: newer).state == .enabled, "Rejected stale start preserves new lease")
        let otherOwner = UUID(), otherRequest = UUID()
        service.register(owner: otherOwner)
        _ = await service.start(owner: otherOwner, request: otherRequest, send: { event, acknowledge in store.receive(event); acknowledge(true) })
        service.invalidate(owner: owner)
        expect(await service.status(owner: otherOwner, request: otherRequest).state == .enabled, "Old connection invalidation preserves current owner")
        service.invalidate(owner: otherOwner)
        expect(store.all.last!.wasStopped, "Connection death stops its tap")
        expect(await service.status(owner: otherOwner, request: otherRequest).state == .stopped, "Connection death releases its lease")
        let dead = await service.start(owner: otherOwner, request: UUID(), send: { event, acknowledge in store.receive(event); acknowledge(true) })
        expect(dead.state == .stopped, "A dead connection cannot recreate a tap")
        let denied = DictationHotkeyTapService(trust: { false }, hostFactory: { _, _ in fatalError("AX false must not create a tap") })
        denied.register(owner: owner)
        let denial = await denied.start(owner: owner, request: UUID(), send: { event, acknowledge in store.receive(event); acknowledge(true) })
        expect(denial.state == .accessibilityRequired && !denial.helper.accessibilityAuthorized, "Actual AX false is preserved")

        let backpressure = AcknowledgementStore()
        let immediate = FakeTapHost(delayed: false, generation: 1, forward: { _, _ in })
        let boundedOwner = UUID(), boundedRequest = UUID()
        let callbackStore = HostStore()
        let callbackService = DictationHotkeyTapService(trust: { true }, hostFactory: { generation, forward in
            let host = FakeTapHost(delayed: false, generation: generation, forward: forward)
            callbackStore.append(host)
            return host
        })
        callbackService.register(owner: boundedOwner)
        _ = await callbackService.start(owner: boundedOwner, request: boundedRequest) { event, acknowledge in
            backpressure.receive(event, acknowledge: acknowledge)
        }
        let sendingHost = callbackStore.all[0]
        sendingHost.forward(sendingHost.generation, .keyDown)
        while backpressure.events.count < 1 { await Task.yield() }
        for _ in 0..<100 { sendingHost.forward(sendingHost.generation, .keyDown) }
        expect(backpressure.events.count == 1, "Only one callback is in flight until app acknowledgement")
        for expected in 2...65 {
            backpressure.acknowledgeNext()
            while backpressure.events.count < expected { await Task.yield() }
        }
        expect(backpressure.events.count == 65, "Callback backlog is bounded to 64 pending inputs")
        expect(backpressure.events.last!.sequence == 101, "Overflow retains the final sequence so a lost release cannot remain hidden")
        callbackService.invalidate(owner: boundedOwner)
        backpressure.acknowledgeNext()

        let failedDelivery = AcknowledgementStore()
        let failedDeadlines = DeliveryDeadlineStore()
        let failedHosts = HostStore()
        let failedService = DictationHotkeyTapService(trust: { true }, hostFactory: { generation, forward in
            let host = FakeTapHost(delayed: false, generation: generation, forward: forward)
            failedHosts.append(host); return host
        }, scheduleAcknowledgementTimeout: { failedDeadlines.schedule($0) })
        failedService.register(owner: boundedOwner, invalidateConnection: { failedDeadlines.invalidate() })
        _ = await failedService.start(owner: boundedOwner, request: boundedRequest) { event, acknowledge in
            failedDelivery.receive(event, acknowledge: acknowledge)
        }
        let failedHost = failedHosts.all[0]
        failedHost.forward(failedHost.generation, .keyDown)
        while failedDelivery.events.count < 1 { await Task.yield() }
        failedDelivery.acknowledgeNext(delivered: false)
        expect(failedHost.wasStopped && failedDeadlines.invalidations == 1,
            "Reverse-send failure stops its host and invalidates its exact connection")
        expect(await failedService.status(owner: boundedOwner, request: boundedRequest).state == .stopped,
            "Send failure cannot leave a Ready lease that delivers nothing")
        failedDeadlines.fireAll()
        expect(failedDeadlines.invalidations == 1, "Send error and timeout settle delivery only once")

        let missingAck = AcknowledgementStore()
        let missingDeadlines = DeliveryDeadlineStore()
        let missingHosts = HostStore()
        let missingService = DictationHotkeyTapService(trust: { true }, hostFactory: { generation, forward in
            let host = FakeTapHost(delayed: false, generation: generation, forward: forward)
            missingHosts.append(host); return host
        }, scheduleAcknowledgementTimeout: { missingDeadlines.schedule($0) })
        missingService.register(owner: boundedOwner, invalidateConnection: { missingDeadlines.invalidate() })
        _ = await missingService.start(owner: boundedOwner, request: boundedRequest) { event, acknowledge in
            missingAck.receive(event, acknowledge: acknowledge)
        }
        missingHosts.all[0].forward(missingHosts.all[0].generation, .keyDown)
        while missingAck.events.count < 1 { await Task.yield() }
        let replacementRequest = UUID()
        _ = await missingService.start(owner: boundedOwner, request: replacementRequest) { event, acknowledge in
            missingAck.receive(event, acknowledge: acknowledge)
        }
        missingDeadlines.fireAll()
        expect(await missingService.status(owner: boundedOwner, request: replacementRequest).state == .enabled,
            "Old callback timeout must not close a newer lease")
        expect(missingDeadlines.invalidations == 0, "Old callback timeout must not invalidate a healthy replacement connection")
        let replacementHost = missingHosts.all[1]
        replacementHost.forward(replacementHost.generation, .keyDown)
        while missingAck.events.count < 2 { await Task.yield() }
        missingDeadlines.fireAll()
        expect(replacementHost.wasStopped && missingDeadlines.invalidations == 1,
            "Missing acknowledgement has bounded fail-closed recovery")
        expect(await missingService.status(owner: boundedOwner, request: replacementRequest).state == .stopped,
            "A never-acknowledged callback cannot retain a dead Ready lease")
        missingAck.acknowledgeNext()
        missingAck.acknowledgeNext()
        expect(missingDeadlines.invalidations == 1, "Late acknowledgements cannot reactivate or double-fail a lease")

        let quota = DictationHotkeyTapService(trust: { true }, hostFactory: { _, _ in immediate })
        quota.register(owner: boundedOwner)
        for _ in 0..<1_024 { quota.stop(owner: boundedOwner, request: UUID()) }
        let exhausted = await quota.start(owner: boundedOwner, request: UUID()) { _, acknowledge in acknowledge(true) }
        expect(exhausted.state == .stopped, "Replay guard quota closes the old owner before dropping tombstones")

        var generation = HelperConnectionGeneration()
        let old = generation.next(), current = generation.next()
        expect(!generation.owns(old) && generation.owns(current), "Old invalidation cannot own the new connection")
        let helper = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        expect(try HelperPermissionStatus(reply: helper.dictionary) == helper, "Handshake round trips exact actual trust")
        do {
            _ = try HelperPermissionStatus(reply: ["protocolVersion": 999])
            fatalError("Version mismatch must throw")
        } catch HelperConnectionFailure.incompatibleProtocol { }
        do {
            _ = try HelperPermissionStatus(reply: ["protocolVersion": dictationHelperProtocolVersion])
            fatalError("Missing trust must throw instead of becoming AX false")
        } catch HelperConnectionFailure.malformedReply { }
        var gate = DictationTapEventGate()
        gate.begin(requestID: newer, helperInstanceID: helper.instanceID)
        expect(gate.accept(DictationTapEvent(requestID: request, helperInstanceID: helper.instanceID, sequence: 1, input: .keyDown)) == nil, "Old request callback rejected")
        expect(gate.accept(DictationTapEvent(requestID: newer, helperInstanceID: UUID(), sequence: 1, input: .keyDown)) == nil, "Old helper callback rejected")
        expect(gate.accept(DictationTapEvent(requestID: newer, helperInstanceID: helper.instanceID, sequence: 1, input: .keyDown)) == true, "Current callback accepted")
        expect(gate.accept(DictationTapEvent(requestID: newer, helperInstanceID: helper.instanceID, sequence: 1, input: .keyDown)) == nil, "Duplicate callback rejected")
        expect(gate.accept(DictationTapEvent(requestID: newer, helperInstanceID: helper.instanceID, sequence: 3, input: .keyDown)) == false, "Sequence gap is identified")
        gate.invalidate()
        expect(gate.accept(DictationTapEvent(requestID: newer, helperInstanceID: helper.instanceID, sequence: 4, input: .keyDown)) == nil, "Stopped callback rejected")
        let waiter = HelperReplyWaiter()
        waiter.finish(.failure(HelperConnectionFailure.timedOut))
        waiter.finish(.success(HelperWireReply(dictionary: helper.dictionary)))
        do {
            let _: HelperWireReply = try await withCheckedThrowingContinuation { waiter.install($0) }
            fatalError("Late reply must not overwrite timeout")
        } catch HelperConnectionFailure.timedOut { }
        print("Dictation helper lease, handshake and callback regressions passed")
    }
}
