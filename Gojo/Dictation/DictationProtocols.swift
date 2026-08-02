import Foundation

protocol DictationTargetCapturing: Sendable {
    associatedtype Target: Sendable

    func captureTarget() async throws -> Target
}

protocol DictationAudioCapturing: Sendable {
    func requestPermission() async -> Bool
    func startCapture() async throws
    func stopCapture() async throws -> DictationAudio
    func cancelCapture() async
}

protocol LocalDictationTranscribing: Sendable {
    func transcribe(_ audio: DictationAudio) async throws -> String
    func cancelTranscription() async
    /// Loads whatever `transcribe` would otherwise load on first use. Called
    /// when a session starts so the cost overlaps with the user speaking.
    func prepare() async
}

extension LocalDictationTranscribing {
    func cancelTranscription() async {}
    func prepare() async {}
}

protocol DictationTextInserting: Sendable {
    associatedtype Target: Sendable

    func insert(_ text: String, into target: Target) async throws
}
