import AudioToolbox
import CoreAudio
import Foundation

extension DictationInputDeviceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The selected microphone is unavailable. Reconnect it or choose another microphone, then try again."
        case .queryFailed:
            return "Microphone devices could not be read. Try again."
        case .selectionFailed:
            return "The selected microphone could not be opened. Choose another microphone, then try again."
        }
    }
}

enum DictationInputDeviceError: Error, Equatable {
    case unavailable
    case queryFailed(OSStatus)
    case selectionFailed(OSStatus)
}

enum DictationInputDevices {
    struct ResolvedInput {
        let deviceID: AudioDeviceID
        let device: DictationInputDevice
    }

    static func inputDevices() throws -> [DictationInputDevice] {
        var address = property(kAudioHardwarePropertyDevices)
        var byteCount: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        try requireSuccess(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &byteCount))
        guard byteCount > 0 else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &byteCount, $0.baseAddress!)
        }
        try requireSuccess(status)
        return devices.compactMap { try? description(for: $0) }.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    static func resolve(_ selection: DictationInputSelection) throws -> ResolvedInput {
        let deviceID: AudioDeviceID
        switch selection {
        case .systemDefault:
            deviceID = try scalar(
                AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultInputDevice,
                initial: AudioDeviceID(kAudioObjectUnknown)
            )
        case .deviceUID(let selectedUID):
            var address = property(kAudioHardwarePropertyTranslateUIDToDevice)
            var uid = selectedUID as CFString
            var resolved = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            let status = withUnsafePointer(to: &uid) { qualifier in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout<CFString>.size), qualifier, &size, &resolved
                )
            }
            guard status == noErr else { throw DictationInputDeviceError.unavailable }
            deviceID = resolved
        }
        guard deviceID != kAudioObjectUnknown,
              let device = try? description(for: deviceID) else {
            throw DictationInputDeviceError.unavailable
        }
        if case .deviceUID(let uid) = selection, device.id != uid {
            throw DictationInputDeviceError.unavailable
        }
        return ResolvedInput(deviceID: deviceID, device: device)
    }

    private static func description(for deviceID: AudioDeviceID) throws -> DictationInputDevice {
        let alive = try scalar(deviceID, selector: kAudioDevicePropertyDeviceIsAlive, initial: UInt32(0))
        guard alive != 0 else { throw DictationInputDeviceError.unavailable }
        var address = property(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        try requireSuccess(AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { throw DictationInputDeviceError.unavailable }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        try requireSuccess(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer))
        let buffers = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        guard buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) > 0 else {
            throw DictationInputDeviceError.unavailable
        }
        let uid = try string(deviceID, selector: kAudioDevicePropertyDeviceUID)
        guard !uid.isEmpty else { throw DictationInputDeviceError.unavailable }
        return DictationInputDevice(id: uid, name: try string(deviceID, selector: kAudioObjectPropertyName))
    }

    private static func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func scalar(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        initial: UInt32
    ) throws -> UInt32 {
        var address = property(selector)
        var value = initial
        var size = UInt32(MemoryLayout<UInt32>.size)
        try requireSuccess(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        return value
    }

    private static func string(_ object: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString>.size)
        try requireSuccess(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
        guard let value else { throw DictationInputDeviceError.unavailable }
        return value.takeRetainedValue() as String
    }

    private static func requireSuccess(_ status: OSStatus) throws {
        guard status == noErr else { throw DictationInputDeviceError.queryFailed(status) }
    }
}

final class DictationInputDeviceObserver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rohoswagger.gojo.dictation.input-devices")
    private let listener: AudioObjectPropertyListenerBlock
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(onChange: @escaping @Sendable () -> Void) {
        listener = { _, _ in onChange() }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
    }

    deinit {
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
    }
}
