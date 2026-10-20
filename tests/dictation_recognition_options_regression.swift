import Foundation
import WhisperKit

private func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

@main
struct DictationRecognitionOptionsRegression {
    static func main() async throws {
        let small = try DictationLocalRecognition(model: .whisperSmallEnglish)
        let smallOptions = try WhisperKitDictationTranscriber.decodingOptions(for: small)
        require(smallOptions.task == .transcribe, "Small English uses transcription")
        require(smallOptions.language == "en", "Small English fixes the decoder language")
        require(!smallOptions.detectLanguage, "Small English cannot auto-detect")

        let large = try DictationLocalRecognition(model: .whisperLargeV3)
        let largeOptions = try WhisperKitDictationTranscriber.decodingOptions(for: large)
        require(largeOptions.language == "en", "Large retains the previous English default")
        require(!largeOptions.detectLanguage, "default English avoids implicit language detection")

        let automatic = try DictationLocalRecognition(model: .whisperLargeV3, language: .automatic)
        let automaticOptions = try WhisperKitDictationTranscriber.decodingOptions(for: automatic)
        require(automaticOptions.language == nil, "automatic language clears the fixed language")
        require(automaticOptions.detectLanguage, "automatic language reaches the real SDK option")
        require(automaticOptions.task == .transcribe, "detection does not implicitly translate")

        let spanish = try DictationLocalRecognition(model: .whisperLargeV3, language: .fixed("es"))
        let spanishOptions = try WhisperKitDictationTranscriber.decodingOptions(for: spanish, promptTokens: [12, 34])
        require(spanishOptions.language == "es", "fixed language reaches the real SDK option")
        require(!spanishOptions.detectLanguage, "fixed Spanish disables automatic detection")
        require(spanishOptions.promptTokens == [12, 34], "frozen recognition terms retain their token prompt")
        require(spanishOptions.temperature == 0 && spanishOptions.temperatureFallbackCount == 0,
                "language options preserve deterministic decode settings")
        require(spanishOptions.chunkingStrategy == .vad && spanishOptions.withoutTimestamps,
                "language options preserve the existing audio decode path")

        let translated = try DictationLocalRecognition(
            model: .whisperLargeV3, language: .fixed("es"), translateToEnglish: true
        )
        let translatedOptions = try WhisperKitDictationTranscriber.decodingOptions(for: translated)
        require(translatedOptions.task == .translate, "explicit translation reaches the real SDK task")
        require(translatedOptions.language == "es", "translation preserves the source language")

        try rejectUnsupportedRequests()
        try await pinnedModelRefusesChanges()
        print("Dictation recognition options regression passed with real WhisperKit DecodingOptions")
    }

    private static func rejectUnsupportedRequests() throws {
        for operation in [
            { try DictationLocalRecognition(model: .whisperSmallEnglish, language: .automatic) },
            { try DictationLocalRecognition(model: .whisperSmallEnglish, translateToEnglish: true) },
            { try DictationLocalRecognition(model: .whisperLargeV3, language: .fixed("made-up")) },
            { try DictationLocalRecognition(model: .parakeetUnifiedEnglish, translateToEnglish: true) },
            { try DictationLocalRecognition(model: .parakeetV3Multilingual, language: .fixed("es")) },
        ] {
            do {
                _ = try operation()
                fatalError("unsupported request reached preparation")
            } catch is DictationRecognitionValidationError {}
        }
        let parakeet = try DictationLocalRecognition(model: .parakeetUnifiedEnglish)
        do {
            _ = try WhisperKitDictationTranscriber.decodingOptions(for: parakeet)
            fatalError("Whisper adapter accepted a Parakeet model")
        } catch WhisperKitDictationError.incompatibleRecognitionRequest {}
    }

    private static func pinnedModelRefusesChanges() async throws {
        let transcriber = WhisperKitDictationTranscriber()
        let plan = DictationSessionPlan()
        try await transcriber.beginSession(plan)
        await transcriber.unload()
        do {
            try await transcriber.selectModel(.largeV3)
            fatalError("selected model changed while a session was pinned")
        } catch WhisperKitDictationError.transcriptionAlreadyRunning {}
        await transcriber.endSession(UUID())
        do {
            try await transcriber.prepare(request: .openRouter(modelID: "frozen-model"))
            fatalError("local backend accepted a cloud request")
        } catch WhisperKitDictationError.incompatibleRecognitionRequest {}
        do {
            try await transcriber.beginSession(DictationSessionPlan())
            fatalError("a second session replaced the pinned session")
        } catch WhisperKitDictationError.sessionAlreadyActive {}
        await transcriber.endSession(plan.id)
        let next = DictationSessionPlan()
        try await transcriber.beginSession(next)
        await transcriber.endSession(next.id)
    }
}
