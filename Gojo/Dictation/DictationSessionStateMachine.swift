import Foundation

struct DictationSessionStateMachine: Sendable {
    enum Event: Equatable, Sendable {
        case hotKeyDown
        case hotKeyUp
        case captureStarted
        case permissionDenied
        case audioTooShort
        case transcriptionCompleted(String)
        case insertionCompleted(String)
        case failed(DictationFailure)
        case cancel
    }

    enum Action: Equatable, Sendable {
        case none
        case beginRequest
        case finishCapture
        case insert
        case cancel
    }

    private(set) var state: DictationState = .idle

    @discardableResult
    mutating func handle(_ event: Event) -> Action {
        switch (state, event) {
        case (.idle, .hotKeyDown),
             (.succeeded, .hotKeyDown),
             (.error, .hotKeyDown):
            state = .requestingPermission
            return .beginRequest

        case (.requestingPermission, .captureStarted):
            state = .listening
            return .none

        case (.requestingPermission, .permissionDenied):
            state = .error(.microphonePermissionDenied)
            return .none

        case (.listening, .hotKeyUp):
            state = .transcribing
            return .finishCapture

        case (.transcribing, .audioTooShort):
            state = .idle
            return .none

        case (.transcribing, .transcriptionCompleted):
            state = .inserting
            return .insert

        case (.inserting, .insertionCompleted(let transcript)):
            state = .succeeded(transcript)
            return .none

        case (_, .failed(let failure)):
            state = .error(failure)
            return .none

        case (.idle, .cancel):
            return .none

        case (_, .cancel),
             (.requestingPermission, .hotKeyUp):
            state = .idle
            return .cancel

        default:
            // Repeated down events and unmatched up events are intentionally ignored.
            return .none
        }
    }
}
