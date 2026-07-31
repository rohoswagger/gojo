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
}

extension LocalDictationTranscribing {
    func cancelTranscription() async {}
}

protocol DictationTextInserting: Sendable {
    associatedtype Target: Sendable

    func insert(_ text: String, into target: Target) async throws
}
