import AppKit
import Foundation

@MainActor
private final class FakeOutputAudio: DictationOutputAudio {
    struct Device {
        var values: [DictationOutputControl: DictationOutputValue]
        var settable: Set<DictationOutputControl>
        var channels: [UInt32] = [1, 2]
    }

    struct Write: Equatable {
        let uid: DictationOutputUID
        let control: DictationOutputControl
        let value: DictationOutputValue
    }

    enum Failure: Error { case injected, disconnected, unsupported }

    var devices: [DictationOutputUID: Device] = [:]
    var defaults: Set<DictationOutputUID> = []
    var writes: [Write] = []
    var callbacks: [@Sendable () -> Void] = []
    var cancellations = 0
    var failWrite: Write?
    var applyFailingWrite = false
    var failReadAfterWrite: Write?
    var failedRead = false
    var observerFailure = false

    func defaultOutputUIDs() throws -> Set<DictationOutputUID> { defaults }
    func outputChannels(_ uid: DictationOutputUID) throws -> [UInt32] {
        guard let device = devices[uid] else { throw Failure.disconnected }
        return device.channels
    }
    func read(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> DictationOutputValue {
        if !failedRead, let failure = failReadAfterWrite, writes.last == failure, failure.uid == uid, failure.control == control {
            failedRead = true
            throw Failure.injected
        }
        guard let device = devices[uid] else { throw Failure.disconnected }
        guard let value = device.values[control] else { throw Failure.unsupported }
        return value
    }
    func isSettable(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> Bool {
        guard let device = devices[uid] else { throw Failure.disconnected }
        return device.settable.contains(control)
    }
    func write(_ value: DictationOutputValue, to control: DictationOutputControl, on uid: DictationOutputUID) throws {
        guard devices[uid] != nil else { throw Failure.disconnected }
        let write = Write(uid: uid, control: control, value: value)
        writes.append(write)
        if write != failWrite || applyFailingWrite { devices[uid]?.values[control] = value }
        if write == failWrite { throw Failure.injected }
    }
    func observeOutputChanges(_ changed: @escaping @Sendable () -> Void) throws -> DictationOutputObservation {
        if observerFailure { throw Failure.injected }
        callbacks.append(changed)
        return DictationOutputObservation { [weak self] in self?.cancellations += 1 }
    }

    func add(_ uid: DictationOutputUID, mute: UInt32 = 0) {
        devices[uid] = Device(values: [.mute(element: 0): .mute(mute)], settable: [.mute(element: 0)])
    }
    func addScalars(_ uid: DictationOutputUID, _ values: [UInt32: Float32]) {
        devices[uid] = Device(values: Dictionary(uniqueKeysWithValues: values.map { (.scalar(element: $0.key), .scalar($0.value)) }), settable: Set(values.keys.map { .scalar(element: $0) }))
    }
    func value(_ uid: DictationOutputUID, _ control: DictationOutputControl = .mute(element: 0)) -> DictationOutputValue? {
        devices[uid]?.values[control]
    }
    func userSet(_ uid: DictationOutputUID, _ control: DictationOutputControl, _ value: DictationOutputValue) {
        devices[uid]?.values[control] = value
    }
}

@main
private struct OutputSilencerRegression {
    static let a = DictationOutputUID(rawValue: "output-a")
    static let b = DictationOutputUID(rawValue: "output-b")
    static let c = DictationOutputUID(rawValue: "output-c")
    static let mute = DictationOutputControl.mute(element: 0)
    static let master = DictationOutputControl.scalar(element: 0)
    static let left = DictationOutputControl.scalar(element: 1)
    static let right = DictationOutputControl.scalar(element: 2)

    @MainActor
    static func main() async {
        await masterMuteAndLeases()
        await alreadyMuted()
        await scalarCoverage()
        await failedAndAmbiguousWrites()
        await userOverrides()
        await routesByUID()
        await unsupportedAndDisconnect()
        await lateCallbacksAndTermination()
        print("Dictation output silencer regressions passed")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    @MainActor
    static func masterMuteAndLeases() async {
        let audio = FakeOutputAudio()
        audio.add(a)
        audio.defaults = [a]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let first = silencer.quietForDictation()
        let second = silencer.quietForDictation()
        expect(audio.value(a) == .mute(1), "Capture must mute the output")
        expect(audio.writes.count == 1, "Overlapping captures must reuse the first snapshot")
        await first()
        await first()
        expect(audio.value(a) == .mute(1), "Old or duplicate cleanup must keep a live capture muted")
        await second()
        expect(audio.value(a) == .mute(0), "Last capture must restore the original mute")
        expect(audio.writes.count == 2 && audio.cancellations == 1, "Last cleanup must restore and cancel observation once")
        let next = silencer.quietForDictation()
        await first()
        expect(audio.value(a) == .mute(1), "An old cleanup must not end a new interval")
        await next()
    }

    @MainActor
    static func alreadyMuted() async {
        let audio = FakeOutputAudio()
        audio.add(a, mute: 1)
        audio.devices[a]?.settable = []
        audio.defaults = [a]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let cleanup = silencer.quietForDictation()
        await cleanup()
        expect(audio.value(a) == .mute(1) && audio.writes.isEmpty, "A pre-muted output must remain untouched even if mute is read-only")
    }

    @MainActor
    static func scalarCoverage() async {
        let audio = FakeOutputAudio()
        audio.addScalars(a, [1: 0.21, 2: 0.79])
        audio.addScalars(b, [0: 0.625])
        audio.defaults = [a, b]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let cleanup = silencer.quietForDictation()
        expect(audio.value(a, left) == .scalar(0) && audio.value(a, right) == .scalar(0), "Fallback must quiet every channel")
        expect(audio.value(b, master) == .scalar(0), "Master scalar must cover its output")
        await cleanup()
        expect(audio.value(a, left) == .scalar(0.21) && audio.value(a, right) == .scalar(0.79), "Fallback must restore exact unequal channels")
        expect(audio.value(b, master) == .scalar(0.625), "Master fallback must restore its exact original")

        audio.writes.removeAll()
        audio.devices[a]?.settable.remove(right)
        audio.defaults = [a]
        var issues: [DictationOutputIssue] = []
        let unsupported = DictationOutputSilencer(audio: audio, report: { issues.append($0) })
        let release = unsupported.quietForDictation()
        expect(audio.writes.isEmpty && !issues.isEmpty, "Incomplete channel coverage must fail before any write")
        await release()
    }

    @MainActor
    static func failedAndAmbiguousWrites() async {
        for ambiguous in [false, true] {
            let audio = FakeOutputAudio()
            audio.addScalars(a, [1: 0.17, 2: 0.83])
            audio.defaults = [a]
            audio.failWrite = .init(uid: a, control: right, value: .scalar(0))
            audio.applyFailingWrite = ambiguous
            var issues: [DictationOutputIssue] = []
            let silencer = DictationOutputSilencer(audio: audio, report: { issues.append($0) })
            let cleanup = silencer.quietForDictation()
            expect(audio.value(a, left) == .scalar(0.17) && audio.value(a, right) == .scalar(0.83), "Partial and ambiguous writes must roll back exact channel values")
            expect(issues.contains { $0.operation == "quiet" }, "Failed quieting must be reported")
            await cleanup()
        }

        let audio = FakeOutputAudio()
        audio.add(a)
        audio.defaults = [a]
        audio.failReadAfterWrite = .init(uid: a, control: mute, value: .mute(1))
        var issues: [DictationOutputIssue] = []
        let silencer = DictationOutputSilencer(audio: audio, report: { issues.append($0) })
        let cleanup = silencer.quietForDictation()
        expect(audio.value(a) == .mute(0), "Readback failure after an applied write must still restore from the attempted-write journal")
        expect(issues.contains { $0.operation == "quiet" }, "Readback failure must be reported")
        await cleanup()

        let failedMute = FakeOutputAudio()
        failedMute.add(a)
        failedMute.defaults = [a]
        failedMute.failWrite = .init(uid: a, control: mute, value: .mute(1))
        failedMute.applyFailingWrite = true
        let uncertain = DictationOutputSilencer(audio: failedMute, report: { _ in })
        let release = uncertain.quietForDictation()
        expect(failedMute.value(a) == .mute(0), "A mute setter that applies then fails must not leave the device muted")
        await release()
    }

    @MainActor
    static func userOverrides() async {
        let audio = FakeOutputAudio()
        audio.add(a)
        audio.addScalars(b, [1: 0.23, 2: 0.81])
        audio.defaults = [a, b]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let cleanup = silencer.quietForDictation()
        audio.userSet(a, mute, .mute(0))
        audio.userSet(b, left, .scalar(0.45))
        await cleanup()
        expect(audio.value(a) == .mute(0), "A user mute change must win")
        expect(audio.value(b, left) == .scalar(0.45), "A user volume change must win")
        expect(audio.value(b, right) == .scalar(0.81), "Unchanged owned channels must still restore")
    }

    @MainActor
    static func routesByUID() async {
        let audio = FakeOutputAudio()
        audio.add(a)
        audio.add(b)
        audio.defaults = [a, b]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let cleanup = silencer.quietForDictation()
        expect(audio.value(a) == .mute(1) && audio.value(b) == .mute(1), "Distinct media and system outputs must both be muted")
        audio.add(c)
        audio.defaults = [c]
        audio.callbacks[0]()
        await settle()
        expect(audio.value(c) == .mute(1), "A newly routed UID must be muted")
        audio.userSet(a, mute, .mute(0))
        audio.defaults = [a]
        audio.callbacks[0]()
        await settle()
        expect(audio.value(a) == .mute(0), "A returning UID must reuse its first snapshot and respect user overrides")
        await cleanup()
        expect(audio.value(a) == .mute(0) && audio.value(b) == .mute(0) && audio.value(c) == .mute(0), "Cleanup must restore by UID including previous routes")
    }

    @MainActor
    static func unsupportedAndDisconnect() async {
        let audio = FakeOutputAudio()
        audio.devices[a] = .init(values: [:], settable: [])
        audio.add(b)
        audio.defaults = [a, b]
        var issues: [DictationOutputIssue] = []
        let silencer = DictationOutputSilencer(audio: audio, report: { issues.append($0) })
        let cleanup = silencer.quietForDictation()
        expect(issues.contains { $0.uid == a && $0.operation == "quiet" }, "Unsupported outputs must be reported")
        expect(audio.value(b) == .mute(1), "An unsupported output must not prevent quieting another output")
        let disconnected = audio.devices.removeValue(forKey: b)!
        await cleanup()
        expect(issues.contains { $0.uid == b && $0.operation == "restore" }, "Disconnected cleanup must report an unresolved restoration")
        audio.devices[b] = disconnected
        audio.callbacks[0]()
        await settle()
        expect(audio.value(b) == .mute(1), "Reconnect after capture ends must not trigger a delayed unmute")
        expect(audio.cancellations == 1, "Unresolved disconnected restores must not retain observation")
    }

    @MainActor
    static func lateCallbacksAndTermination() async {
        let audio = FakeOutputAudio()
        audio.add(a)
        audio.add(b)
        audio.defaults = [a]
        let silencer = DictationOutputSilencer(audio: audio, report: { fatalError($0.description) })
        let cleanup = silencer.quietForDictation()
        audio.defaults = [b]
        audio.callbacks[0]()
        await cleanup()
        await settle()
        expect(audio.value(b) == .mute(0), "A callback queued before cleanup must not mute after cleanup")
        let next = silencer.quietForDictation()
        audio.defaults = [a]
        audio.callbacks[0]()
        await settle()
        expect(audio.value(a) == .mute(0), "A callback from a previous generation must not alter a new interval")
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        expect(audio.value(b) == .mute(0), "Normal quit must restore synchronously before notification returns")
        await next()
        expect(audio.cancellations == 2, "Cleanup after termination must be idempotent")

        audio.observerFailure = true
        audio.defaults = [a]
        var issues: [DictationOutputIssue] = []
        let unobserved = DictationOutputSilencer(audio: audio, report: { issues.append($0) })
        let release = unobserved.quietForDictation()
        expect(audio.value(a) == .mute(1) && issues.contains { $0.operation == "observe" }, "Observation failure must be reported while initial quieting still runs")
        await release()
        expect(audio.value(a) == .mute(0), "Observation failure must not lose cleanup")
    }

    private static func settle() async {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}
