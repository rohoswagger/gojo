import Foundation

protocol DictationTargetCapturing: Sendable {
    associatedtype Target: Sendable

    func captureTarget(purpose: DictationSessionPurpose) async throws -> DictationTargetResolution<Target>
    func captureAdditionalTarget(purpose: DictationSessionPurpose) async throws -> DictationTargetResolution<Target>
    func destinationIdentifier(for target: Target) -> String?
}

extension DictationTargetCapturing {
    func destinationIdentifier(for target: Target) -> String? { nil }

    func captureAdditionalTarget(purpose: DictationSessionPurpose) async throws -> DictationTargetResolution<Target> {
        try await captureTarget(purpose: purpose)
    }
}

protocol DictationAudioCapturing: Sendable {
    func configure(_ configuration: DictationCaptureConfiguration) async throws
    func captureSnapshot() async -> DictationCaptureSnapshot?
    func requestPermission() async throws -> Bool
    func startCapture() async throws
    func stopCapture() async throws -> DictationAudio
    func cancelCapture() async
    func takeInterruptedAudio() async -> DictationAudio?
    func captureIsQuiescent() async -> Bool
    func startContinuousCapture(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error>
    func stopContinuousCapture() async throws
    func promoteCaptureToContinuous(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error>
}

extension DictationAudioCapturing {
    func configure(_ configuration: DictationCaptureConfiguration) async throws {}
    func captureSnapshot() async -> DictationCaptureSnapshot? { nil }
    func takeInterruptedAudio() async -> DictationAudio? { nil }
    func captureIsQuiescent() async -> Bool { true }

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
    func transcribe(_ audio: DictationAudio, request: DictationRecognitionRequest) async throws -> String
    func prepare(request: DictationRecognitionRequest) async throws
    func cancelTranscription() async
    func beginSession(_ plan: DictationSessionPlan) async throws
    func endSession(_ id: UUID) async
}

extension LocalDictationTranscribing {
    func cancelTranscription() async {}
    func prepare(request: DictationRecognitionRequest) async throws {}
    func beginSession(_ plan: DictationSessionPlan) async throws {}
    func endSession(_ id: UUID) async {}
}

protocol DictationTextPolishing: Sendable {
    func polish(_ transcript: String, options: DictationTextOptions) async throws -> String
    func cancelPolishing() async
}

protocol DictationTextInserting: Sendable {
    associatedtype Target: Sendable

    func insert(_ text: String, into target: Target, plan: DictationSessionPlan) async throws -> DictationInsertionOutcome
    func insertRetainingTarget(_ text: String, into target: Target, plan: DictationSessionPlan) async throws -> DictationInsertionOutcome
    func releaseTarget(_ target: Target) async
}

extension DictationTextInserting {
    func insertRetainingTarget(_ text: String, into target: Target, plan: DictationSessionPlan) async throws -> DictationInsertionOutcome {
        try await insert(text, into: target, plan: plan)
    }

    func releaseTarget(_ target: Target) async {}
}
