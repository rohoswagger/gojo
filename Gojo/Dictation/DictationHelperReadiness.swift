import Foundation

let dictationHelperProtocolVersion = 1

enum HelperConnectionFailure: Error, Equatable, Sendable {
    case unavailable(domain: String, code: Int)
    case interrupted
    case invalidated
    case timedOut
    case incompatibleProtocol(expected: Int, actual: Int)
    case malformedReply
}

struct HelperPermissionStatus: Equatable, Sendable {
    let protocolVersion: Int
    let instanceID: UUID
    let accessibilityAuthorized: Bool

    init(protocolVersion: Int = dictationHelperProtocolVersion, instanceID: UUID, accessibilityAuthorized: Bool) {
        self.protocolVersion = protocolVersion
        self.instanceID = instanceID
        self.accessibilityAuthorized = accessibilityAuthorized
    }

    init(reply: NSDictionary) throws {
        guard let version = reply["protocolVersion"] as? Int else { throw HelperConnectionFailure.malformedReply }
        guard version == dictationHelperProtocolVersion else {
            throw HelperConnectionFailure.incompatibleProtocol(expected: dictationHelperProtocolVersion, actual: version)
        }
        guard let identifier = reply["helperInstanceID"] as? String,
              let instanceID = UUID(uuidString: identifier),
              let trusted = reply["accessibilityAuthorized"] as? Bool else {
            throw HelperConnectionFailure.malformedReply
        }
        self.init(protocolVersion: version, instanceID: instanceID, accessibilityAuthorized: trusted)
    }

    var dictionary: NSDictionary {
        ["protocolVersion": protocolVersion, "helperInstanceID": instanceID.uuidString,
         "accessibilityAuthorized": accessibilityAuthorized]
    }
}

enum DictationTapState: Int, Equatable, Sendable {
    case stopped, enabled, accessibilityRequired, creationFailed, runLoopSourceFailed, enableFailed
}

struct DictationTapStatus: Equatable, Sendable {
    let requestID: UUID
    let helper: HelperPermissionStatus
    let state: DictationTapState

    init(requestID: UUID, helper: HelperPermissionStatus, state: DictationTapState) {
        self.requestID = requestID
        self.helper = helper
        self.state = state
    }

    init(reply: NSDictionary) throws {
        helper = try HelperPermissionStatus(reply: reply)
        guard let identifier = reply["requestID"] as? String,
              let requestID = UUID(uuidString: identifier),
              let rawState = reply["tapState"] as? Int,
              let state = DictationTapState(rawValue: rawState) else {
            throw HelperConnectionFailure.malformedReply
        }
        self.requestID = requestID
        self.state = state
    }

    var dictionary: NSDictionary {
        let result = NSMutableDictionary(dictionary: helper.dictionary)
        result["requestID"] = requestID.uuidString
        result["tapState"] = state.rawValue
        return result
    }
}

enum DictationModifierEventTapInput: Equatable, Sendable {
    case tapDisabled(reenabled: Bool)
    case flagsChanged(isExactChord: Bool, anyTriggerModifierDown: Bool, hasDisallowedModifiers: Bool)
    case keyDown
    case lockToggle
}

struct DictationTapEvent: Equatable, Sendable {
    let requestID: UUID
    let helperInstanceID: UUID
    let sequence: UInt64
    let input: DictationModifierEventTapInput
}

enum DictationHelperState: Equatable {
    case checking
    case available(HelperPermissionStatus)
    case unavailable(HelperConnectionFailure)
}

enum DictationAccessibilityState: Equatable {
    case unknown, notTrusted, requesting, trusted
}

enum DictationShortcutFailure: Equatable {
    case helper(HelperConnectionFailure)
    case tap(DictationTapState)
}

enum DictationShortcutReadiness: Equatable {
    case stopped, checking, awaitingAccessibility, ready
    case unavailable(DictationShortcutFailure)
}

@MainActor
protocol DictationHotkeyTransport: AnyObject {
    var dictationInputHandler: (@MainActor (DictationTapEvent) -> Void)? { get set }
    func helperPermissionStatus() async throws -> HelperPermissionStatus
    func requestHelperAccessibility() async throws -> HelperPermissionStatus
    func startDictationTap(requestID: UUID) async throws -> DictationTapStatus
    func stopDictationTap(requestID: UUID) async throws
    func dictationTapStatus(requestID: UUID) async throws -> DictationTapStatus
    #if DEBUG
    func dictationTapDiagnostics(requestID: UUID, recoverDisabled: Bool) async throws -> (enabled: Bool, consumed: UInt64)
    #endif
}

struct DictationTapEventGate {
    private(set) var requestID: UUID?
    private(set) var helperInstanceID: UUID?
    private(set) var sequence: UInt64 = 0

    mutating func begin(requestID: UUID, helperInstanceID: UUID) {
        self.requestID = requestID
        self.helperInstanceID = helperInstanceID
        sequence = 0
    }

    mutating func invalidate() {
        requestID = nil
        helperInstanceID = nil
        sequence = 0
    }

    mutating func accept(_ event: DictationTapEvent) -> Bool? {
        guard event.requestID == requestID, event.helperInstanceID == helperInstanceID,
              event.sequence > sequence else { return nil }
        let contiguous = event.sequence == sequence + 1
        sequence = event.sequence
        return contiguous
    }
}

struct HelperConnectionGeneration {
    private(set) var value: UInt64 = 0
    mutating func next() -> UInt64 { value &+= 1; return value }
    func owns(_ generation: UInt64) -> Bool { value == generation }
}

extension Notification.Name {
    static let helperConnectionStateChanged = Notification.Name("helperConnectionStateChanged")
}

extension HelperConnectionFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable(let domain, let code): return "Gojo's helper is unavailable (\(domain) \(code)). Retry or rebuild Gojo with a valid signing identity."
        case .interrupted: return "Gojo's helper connection was interrupted. Reconnecting."
        case .invalidated: return "Gojo's helper connection ended. Retry the connection."
        case .timedOut: return "Gojo's helper did not reply. Retry the connection."
        case .incompatibleProtocol: return "Gojo and its helper have different versions. Rebuild or reinstall Gojo."
        case .malformedReply: return "Gojo's helper returned an invalid reply. Rebuild or reinstall Gojo."
        }
    }

    static func wrapping(_ error: Error) -> HelperConnectionFailure {
        if let failure = error as? HelperConnectionFailure { return failure }
        let error = error as NSError
        return .unavailable(domain: error.domain, code: error.code)
    }
}

extension DictationShortcutFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .helper(let failure): return failure.localizedDescription
        case .tap(.accessibilityRequired): return "Allow Accessibility access for Gojo, then retry the shortcut."
        case .tap: return "Gojo could not enable the dictation shortcut. Retry the shortcut."
        }
    }
}

struct HelperWireReply: @unchecked Sendable {
    let dictionary: NSDictionary
    let generation: UInt64
    init(dictionary: NSDictionary, generation: UInt64 = 0) {
        self.dictionary = dictionary
        self.generation = generation
    }
}

final class HelperReplyWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<HelperWireReply, Error>?
    private var result: Result<HelperWireReply, Error>?

    func install(_ continuation: CheckedContinuation<HelperWireReply, Error>) {
        let completed = lock.withLock { () -> Result<HelperWireReply, Error>? in
            if let result { return result }
            self.continuation = continuation
            return nil
        }
        if let completed { continuation.resume(with: completed) }
    }

    func finish(_ value: Result<HelperWireReply, Error>) {
        let pending = lock.withLock { () -> CheckedContinuation<HelperWireReply, Error>? in
            guard result == nil else { return nil }
            result = value
            let pending = continuation
            continuation = nil
            return pending
        }
        pending?.resume(with: value)
    }
}

