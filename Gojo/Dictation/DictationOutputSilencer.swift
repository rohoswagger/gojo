import AppKit
import CoreAudio
import Foundation
import os

struct DictationOutputUID: Hashable, Sendable {
    let rawValue: String
}

enum DictationOutputControl: Hashable, Sendable {
    case mute(element: UInt32)
    case scalar(element: UInt32)
}

enum DictationOutputValue: Equatable, Sendable {
    case mute(UInt32)
    case scalar(Float32)
}

struct DictationOutputIssue: CustomStringConvertible {
    let uid: DictationOutputUID?
    let operation: String
    let reason: String

    var description: String {
        "output=\(uid?.rawValue ?? "unknown") operation=\(operation) reason=\(reason)"
    }
}

final class DictationOutputObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        let action = cancellation
        cancellation = nil
        action?()
    }

    deinit { cancel() }
}

@MainActor
protocol DictationOutputAudio {
    func defaultOutputUIDs() throws -> Set<DictationOutputUID>
    func outputChannels(_ uid: DictationOutputUID) throws -> [UInt32]
    func read(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> DictationOutputValue
    func isSettable(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> Bool
    func write(_ value: DictationOutputValue, to control: DictationOutputControl, on uid: DictationOutputUID) throws
    func observeOutputChanges(_ changed: @escaping @Sendable () -> Void) throws -> DictationOutputObservation
}

@MainActor
final class DictationOutputSilencer {
    typealias Cleanup = @Sendable () async -> Void

    static let shared = DictationOutputSilencer(audio: CoreAudioDictationOutput(), report: {
        Logger(subsystem: "rohoswagger.gojo.dictation", category: "output").error("operation=\($0.operation, privacy: .public) output=\($0.uid?.rawValue ?? "unknown", privacy: .private) reason=\($0.reason, privacy: .private)")
    })

    private struct Change {
        let control: DictationOutputControl
        let original: DictationOutputValue
        let written: DictationOutputValue
    }

    private let audio: any DictationOutputAudio
    private let report: (DictationOutputIssue) -> Void
    private var leases: Set<UUID> = []
    private var changes: [DictationOutputUID: [Change]] = [:]
    private var generation: UUID?
    private var observation: DictationOutputObservation?
    private var terminationObserver: NSObjectProtocol?

    init(audio: any DictationOutputAudio, report: @escaping (DictationOutputIssue) -> Void) {
        self.audio = audio
        self.report = report
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAllNow() }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    func quietForDictation() -> Cleanup {
        let lease = UUID()
        leases.insert(lease)
        if generation == nil {
            let interval = UUID()
            generation = interval
            do {
                observation = try audio.observeOutputChanges { [weak self] in
                    Task { @MainActor in
                        guard let self, self.generation == interval, !self.leases.isEmpty else { return }
                        self.reconcileOutputs()
                    }
                }
            } catch {
                issue(nil, "observe", error)
            }
            reconcileOutputs()
        }
        return { [self] in await release(lease) }
    }

    private func release(_ lease: UUID) {
        guard leases.remove(lease) != nil, leases.isEmpty else { return }
        restoreAllNow()
    }

    private func restoreAllNow() {
        generation = nil
        leases.removeAll()
        observation?.cancel()
        observation = nil
        for uid in Array(changes.keys) {
            restore(uid)
        }
        changes.removeAll()
    }

    private func reconcileOutputs() {
        do {
            for uid in try audio.defaultOutputUIDs() where changes[uid] == nil {
                changes[uid] = []
                quiet(uid)
            }
        } catch {
            issue(nil, "defaults", error)
        }
    }

    private func quiet(_ uid: DictationOutputUID) {
        let mute = DictationOutputControl.mute(element: kAudioObjectPropertyElementMain)
        if let original = try? audio.read(mute, on: uid), case .mute(let value) = original {
            if value != 0 { return }
            if (try? audio.isSettable(mute, on: uid)) == true {
                if apply([Change(control: mute, original: original, written: .mute(1))], on: uid) { return }
            }
        }

        do {
            let master = DictationOutputControl.scalar(element: kAudioObjectPropertyElementMain)
            let controls: [DictationOutputControl]
            if (try? audio.isSettable(master, on: uid)) == true,
               let value = try? audio.read(master, on: uid), case .scalar = value {
                controls = [master]
            } else {
                let channels = try audio.outputChannels(uid)
                guard !channels.isEmpty else { throw OutputError.unsupported("No output channels") }
                controls = channels.map { .scalar(element: $0) }
            }
            let planned = try controls.map { control -> Change in
                guard try audio.isSettable(control, on: uid) else {
                    throw OutputError.unsupported("Output volume is not writable for \(control)")
                }
                let original = try audio.read(control, on: uid)
                guard case .scalar(let value) = original, value.isFinite, (0...1).contains(value) else {
                    throw OutputError.unsupported("Invalid output volume for \(control)")
                }
                return Change(control: control, original: original, written: .scalar(0))
            }
            _ = apply(planned, on: uid)
        } catch {
            issue(uid, "quiet", error)
        }
    }

    private func apply(_ planned: [Change], on uid: DictationOutputUID) -> Bool {
        let start = changes[uid, default: []].count
        do {
            for change in planned where change.original != change.written {
                changes[uid, default: []].append(change)
                try audio.write(change.written, to: change.control, on: uid)
                guard try audio.read(change.control, on: uid) == change.written else {
                    throw OutputError.unsupported("Output did not confirm \(change.control)")
                }
            }
            return true
        } catch {
            issue(uid, "quiet", error)
            restore(uid, startingAt: start)
            return false
        }
    }

    private func restore(_ uid: DictationOutputUID, startingAt start: Int = 0) {
        guard let journal = changes[uid] else { return }
        var unresolved: [Change] = []
        for change in journal.dropFirst(start).reversed() {
            do {
                let current = try audio.read(change.control, on: uid)
                guard current == change.written else { continue }
                try audio.write(change.original, to: change.control, on: uid)
                guard try audio.read(change.control, on: uid) == change.original else {
                    throw OutputError.unsupported("Output did not confirm restoration of \(change.control)")
                }
            } catch {
                issue(uid, "restore", error)
                unresolved.append(change)
            }
        }
        changes[uid] = Array(journal.prefix(start)) + unresolved.reversed()
    }

    private func issue(_ uid: DictationOutputUID?, _ operation: String, _ error: Error) {
        report(DictationOutputIssue(uid: uid, operation: operation, reason: String(describing: error)))
    }
}

private enum OutputError: Error {
    case status(OSStatus)
    case unsupported(String)
    case unavailable(String)
}

@MainActor
final class CoreAudioDictationOutput: DictationOutputAudio {
    func defaultOutputUIDs() throws -> Set<DictationOutputUID> {
        var outputs: Set<DictationOutputUID> = []
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            let device: UInt32 = try scalar(AudioObjectID(kAudioObjectSystemObject), address: address(selector), initial: kAudioObjectUnknown)
            if device != kAudioObjectUnknown {
                outputs.insert(DictationOutputUID(rawValue: try uid(device)))
            }
        }
        return outputs
    }

    func outputChannels(_ uid: DictationOutputUID) throws -> [UInt32] {
        let device = try resolve(uid)
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { return [] }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, storage))
        let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
        let count = buffers.reduce(UInt32(0)) { $0 + $1.mNumberChannels }
        return count == 0 ? [] : Array(1...count)
    }

    func read(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> DictationOutputValue {
        let device = try resolve(uid)
        switch control {
        case .mute:
            return .mute(try scalar(device, address: address(control), initial: UInt32(0)))
        case .scalar:
            return .scalar(try scalar(device, address: address(control), initial: Float32(0)))
        }
    }

    func isSettable(_ control: DictationOutputControl, on uid: DictationOutputUID) throws -> Bool {
        let device = try resolve(uid)
        var property = address(control)
        guard AudioObjectHasProperty(device, &property) else { return false }
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(device, &property, &settable))
        return settable.boolValue
    }

    func write(_ value: DictationOutputValue, to control: DictationOutputControl, on uid: DictationOutputUID) throws {
        let device = try resolve(uid)
        var property = address(control)
        switch (control, value) {
        case (.mute, .mute(var value)):
            try check(AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value))
        case (.scalar, .scalar(var value)):
            try check(AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value))
        default:
            throw OutputError.unsupported("Mismatched output control and value")
        }
    }

    func observeOutputChanges(_ changed: @escaping @Sendable () -> Void) throws -> DictationOutputObservation {
        let queue = DispatchQueue.main
        let listener: AudioObjectPropertyListenerBlock = { _, _ in changed() }
        var registered: [AudioObjectPropertyAddress] = []
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDevices] {
            var property = address(selector)
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, queue, listener)
            guard status == noErr else {
                for var previous in registered {
                    AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &previous, queue, listener)
                }
                throw OutputError.status(status)
            }
            registered.append(property)
        }
        return DictationOutputObservation {
            for var property in registered {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, queue, listener)
            }
        }
    }

    private func resolve(_ expected: DictationOutputUID) throws -> AudioObjectID {
        var property = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var uid = expected.rawValue as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &uid) { qualifier in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device)
        }
        try check(status)
        guard device != kAudioObjectUnknown, try self.uid(device) == expected.rawValue else {
            throw OutputError.unavailable(expected.rawValue)
        }
        let alive: UInt32 = try scalar(device, address: address(kAudioDevicePropertyDeviceIsAlive), initial: 0)
        guard alive != 0 else { throw OutputError.unavailable(expected.rawValue) }
        return device
    }

    private func uid(_ device: AudioObjectID) throws -> String {
        var property = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        try check(AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value))
        guard let value else { throw OutputError.unavailable("Missing output UID") }
        return value.takeRetainedValue() as String
    }

    private func scalar<T>(_ device: AudioObjectID, address: AudioObjectPropertyAddress, initial: T) throws -> T {
        var property = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, bytes.baseAddress!)
        }
        try check(status)
        guard size == MemoryLayout<T>.size else { throw OutputError.unsupported("Unexpected output property size") }
        return value
    }

    private func address(_ control: DictationOutputControl) -> AudioObjectPropertyAddress {
        switch control {
        case .mute(let element):
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        case .scalar(let element):
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        }
    }

    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw OutputError.status(status) }
    }
}
