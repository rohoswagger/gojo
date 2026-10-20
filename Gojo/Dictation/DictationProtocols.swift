import Foundation

protocol DictationTargetCapturing: Sendable {
    associatedtype Target: Sendable

    func captureTarget() async throws -> DictationTargetResolution<Target>
    func captureAdditionalTarget() async throws -> DictationTargetResolution<Target>
    func destinationIdentifier(for target: Target) -> String?
}

extension DictationTargetCapturing {
    func destinationIdentifier(for target: Target) -> String? { nil }

    func captureAdditionalTarget() async throws -> DictationTargetResolution<Target> {
        try await captureTarget()
    }
}

protocol DictationAudioCapturing: Sendable {
    func requestPermission() async throws -> Bool
    func startCapture() async throws
    func stopCapture() async throws -> DictationAudio
    func cancelCapture() async
    func startContinuousCapture(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error>
    func stopContinuousCapture() async throws
    func promoteCaptureToContinuous(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error>
}

extension DictationAudioCapturing {
    func promoteCaptureToContinuous(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        throw DictationContinuousCaptureError.unsupported
    }

    func startContinuousCapture(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        throw DictationContinuousCaptureError.unsupported
    }

    func stopContinuousCapture() async throws {
        throw DictationContinuousCaptureError.unsupported
    }
}

protocol LocalDictationTranscribing: Sendable {
    func transcribe(_ audio: DictationAudio) async throws -> String
    func cancelTranscription() async
    /// Loads whatever `transcribe` would otherwise load on first use. Called
    /// when a session starts so the cost overlaps with the user speaking.
    func prepare() async throws
}

extension LocalDictationTranscribing {
    func cancelTranscription() async {}
    func prepare() async throws {}
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

    func insert(_ text: String, into target: Target) async throws -> DictationInsertionOutcome
    func insertRetainingTarget(_ text: String, into target: Target) async throws -> DictationInsertionOutcome
    func releaseTarget(_ target: Target) async
}

extension DictationTextInserting {
    func insertRetainingTarget(_ text: String, into target: Target) async throws -> DictationInsertionOutcome {
        try await insert(text, into: target)
    }

    func releaseTarget(_ target: Target) async {}
}
