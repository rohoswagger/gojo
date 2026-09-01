import Foundation

enum DictationActivationMode: String, CaseIterable, Identifiable {
    case holdToTalk
    case tapToTalk

    static let defaultsKey = "dictationActivationMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .holdToTalk:
            return "Hold to talk"
        case .tapToTalk:
            return "Tap to talk"
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = Self(rawValue: rawValue) else {
            return .holdToTalk
        }
        return mode
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// Keeps event-tap retries deterministic and independently testable. A failed
/// tap is usually transient (login, wake, permission propagation, or macOS
/// temporarily disabling taps), so back off without giving up permanently.
struct DictationEventTapRecoveryPolicy {
    private static let retryDelaysMilliseconds = [250, 500, 1_000, 2_000, 5_000]

    private(set) var consecutiveFailures = 0
    private(set) var startGeneration: UInt = 0

    mutating func beginStartAttempt() -> UInt {
        startGeneration &+= 1
        return startGeneration
    }

    mutating func invalidateStartAttempts() {
        startGeneration &+= 1
    }

    func ownsStartAttempt(_ generation: UInt) -> Bool {
        startGeneration == generation
    }

    mutating func nextRetryDelayMilliseconds() -> Int {
        let index = min(consecutiveFailures, Self.retryDelaysMilliseconds.count - 1)
        if consecutiveFailures < Self.retryDelaysMilliseconds.count {
            consecutiveFailures += 1
        }
        return Self.retryDelaysMilliseconds[index]
    }

    mutating func recordSuccess() {
        consecutiveFailures = 0
    }
}

/// Coalesces reentrant event-tap start requests while an authorization check is
/// suspended. Prompting intent is sticky so a lifecycle recovery cannot turn a
/// user-visible permission request into a silent background attempt.
struct DictationEventTapStartRequestPolicy {
    private(set) var isRunning = false
    private var hasPendingRequest = false
    private var pendingPromptIfNeeded = false

    mutating func enqueue(promptIfNeeded: Bool) -> Bool {
        hasPendingRequest = true
        pendingPromptIfNeeded = pendingPromptIfNeeded || promptIfNeeded
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    mutating func nextRequest() -> Bool? {
        guard hasPendingRequest else {
            isRunning = false
            return nil
        }
        hasPendingRequest = false
        let promptIfNeeded = pendingPromptIfNeeded
        pendingPromptIfNeeded = false
        return promptIfNeeded
    }

    mutating func cancelPendingRequests() {
        hasPendingRequest = false
        pendingPromptIfNeeded = false
    }
}

/// Prevents a release from stopping a session unless this shortcut pipeline
/// successfully admitted its matching press.
struct DictationShortcutSessionGate {
    private(set) var hasAcceptedKeyDown = false

    mutating func acceptKeyDown() {
        hasAcceptedKeyDown = true
    }

    mutating func consumeKeyUp() -> Bool {
        guard hasAcceptedKeyDown else { return false }
        hasAcceptedKeyDown = false
        return true
    }

    mutating func reset() {
        hasAcceptedKeyDown = false
    }
}

struct DictationModifierShortcutStateMachine {
    enum State: Equatable {
        case idle
        case arming
        case active
        case stopping
        case blocked
    }

    enum Event {
        case flagsChanged(
            isExactChord: Bool,
            anyTriggerModifierDown: Bool,
            hasDisallowedModifiers: Bool
        )
        case keyDown
        case activationDelayElapsed
        case cancel
    }

    enum Action: Equatable {
        case none
        case scheduleActivation
        case cancelScheduledActivation
        case beginDictation
        case finishDictation
        case cancelDictation
    }

    private(set) var state: State = .idle
    private(set) var mode: DictationActivationMode

    init(mode: DictationActivationMode = .holdToTalk) {
        self.mode = mode
    }

    mutating func handle(_ event: Event) -> Action {
        if case .cancel = event {
            return reset()
        }

        switch mode {
        case .holdToTalk:
            return handleHoldToTalk(event)
        case .tapToTalk:
            return handleTapToTalk(event)
        }
    }

    mutating func setMode(_ newMode: DictationActivationMode) -> Action {
        guard mode != newMode else { return .none }
        let action = reset()
        mode = newMode
        return action
    }

    mutating func reset() -> Action {
        let previousState = state
        state = .idle
        switch previousState {
        case .arming where mode == .holdToTalk:
            return .cancelScheduledActivation
        case .active, .stopping:
            return .cancelDictation
        case .idle, .arming, .blocked:
            return .none
        }
    }

    /// Returns the gesture recognizer to idle when the downstream dictation
    /// service rejects a begin request before a session exists. This deliberately
    /// emits no cancellation action because there is nothing to cancel.
    mutating func rejectDictationStart() {
        state = .idle
    }

    private mutating func handleHoldToTalk(_ event: Event) -> Action {
        switch (state, event) {
        case let (.idle, .flagsChanged(isExactChord, _, hasDisallowedModifiers)):
            if hasDisallowedModifiers {
                state = .blocked
                return .none
            }
            guard isExactChord else { return .none }
            state = .arming
            return .scheduleActivation

        case (.idle, _):
            return .none

        case (.arming, .activationDelayElapsed):
            state = .active
            return .beginDictation

        case (.arming, .flagsChanged(_, _, hasDisallowedModifiers: true)):
            state = .blocked
            return .cancelScheduledActivation

        case (.arming, .flagsChanged(isExactChord: true, _, hasDisallowedModifiers: false)):
            return .none

        case let (.arming, .flagsChanged(
            isExactChord: false,
            anyTriggerModifierDown: anyTriggerDown,
            hasDisallowedModifiers: hasDisallowedModifiers
        )):
            state = anyTriggerDown || hasDisallowedModifiers ? .blocked : .idle
            return .cancelScheduledActivation

        case (.arming, .keyDown):
            state = .blocked
            return .cancelScheduledActivation

        case (.active, .flagsChanged(isExactChord: true, _, hasDisallowedModifiers: false)):
            return .none

        case let (.active, .flagsChanged(_, anyTriggerDown, hasDisallowedModifiers)):
            state = anyTriggerDown || hasDisallowedModifiers ? .blocked : .idle
            return hasDisallowedModifiers ? .cancelDictation : .finishDictation

        case (.active, .keyDown):
            state = .blocked
            return .cancelDictation

        case (.active, .activationDelayElapsed):
            return .none

        case (.stopping, _):
            state = .idle
            return .cancelDictation

        case let (.blocked, .flagsChanged(
            isExactChord: _,
            anyTriggerModifierDown: anyTriggerDown,
            hasDisallowedModifiers: hasDisallowedModifiers
        )):
            if !anyTriggerDown && !hasDisallowedModifiers {
                state = .idle
            }
            return .none

        case (.blocked, _):
            return .none

        case (_, .cancel):
            return .none
        }
    }

    private mutating func handleTapToTalk(_ event: Event) -> Action {
        switch (state, event) {
        case let (.idle, .flagsChanged(isExactChord, _, hasDisallowedModifiers)):
            if hasDisallowedModifiers {
                state = .blocked
            } else if isExactChord {
                state = .arming
            }
            return .none

        case (.idle, _):
            return .none

        case (.arming, .flagsChanged(_, _, hasDisallowedModifiers: true)):
            state = .blocked
            return .none

        case (.arming, .flagsChanged(isExactChord: true, _, hasDisallowedModifiers: false)):
            return .none

        case let (.arming, .flagsChanged(
            isExactChord: false,
            anyTriggerModifierDown: anyTriggerDown,
            hasDisallowedModifiers: false
        )):
            guard !anyTriggerDown else { return .none }
            state = .active
            return .beginDictation

        case (.arming, .keyDown):
            state = .blocked
            return .none

        case (.arming, .activationDelayElapsed):
            return .none

        case (.active, .flagsChanged(_, _, hasDisallowedModifiers: true)):
            state = .blocked
            return .cancelDictation

        case (.active, .flagsChanged(isExactChord: true, _, hasDisallowedModifiers: false)):
            state = .stopping
            return .none

        case (.active, .flagsChanged(isExactChord: false, _, hasDisallowedModifiers: false)):
            return .none

        case (.active, .keyDown):
            state = .blocked
            return .cancelDictation

        case (.active, .activationDelayElapsed):
            return .none

        case (.stopping, .flagsChanged(_, _, hasDisallowedModifiers: true)):
            state = .blocked
            return .cancelDictation

        case (.stopping, .flagsChanged(isExactChord: true, _, hasDisallowedModifiers: false)):
            return .none

        case let (.stopping, .flagsChanged(
            isExactChord: false,
            anyTriggerModifierDown: anyTriggerDown,
            hasDisallowedModifiers: false
        )):
            guard !anyTriggerDown else { return .none }
            state = .idle
            return .finishDictation

        case (.stopping, .keyDown):
            state = .blocked
            return .cancelDictation

        case (.stopping, .activationDelayElapsed):
            return .none

        case let (.blocked, .flagsChanged(
            isExactChord: _,
            anyTriggerModifierDown: anyTriggerDown,
            hasDisallowedModifiers: hasDisallowedModifiers
        )):
            if !anyTriggerDown && !hasDisallowedModifiers {
                state = .idle
            }
            return .none

        case (.blocked, _):
            return .none

        case (_, .cancel):
            return .none
        }
    }
}
