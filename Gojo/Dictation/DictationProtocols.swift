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
    /// Routes live mono audio (at the hardware sample rate) to a streaming
    /// transcriber for the duration of the next capture. Pass nil to clear.
    func setStreamConsumer(_ consumer: (@Sendable ([Float], Double) -> Void)?) async
}

extension DictationAudioCapturing {
    func setStreamConsumer(_ consumer: (@Sendable ([Float], Double) -> Void)?) async {}
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

/// A transcriber that can consume live audio during capture so only the tail
/// remains to process when the user releases the shortcut.
protocol DictationStreamingTranscribing: LocalDictationTranscribing {
    /// Starts a streaming session and returns a consumer for live mono audio
    /// at the given hardware sample rate, or nil when streaming is unavailable
    /// (model not loaded yet, wrong provider/model). Never blocks on model
    /// loading.
    func beginStreamingSession() async -> (@Sendable ([Float], Double) -> Void)?
    /// Ends the session and returns the final transcript.
    func finishStreamingSession() async throws -> String
    func cancelStreamingSession() async
}

/// Optionally refines an already-transcribed utterance before it is inserted.
/// Implementations must support prompt cancellation so a replacement dictation
/// session never races an earlier polish request.
protocol DictationTextPolishing: Sendable {
    func polish(_ transcript: String) async throws -> String
    func cancelPolishing() async
}

protocol DictationTextInserting: Sendable {
    associatedtype Target: Sendable

    func insert(_ text: String, into target: Target) async throws
}
