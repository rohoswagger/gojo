import Foundation

actor LocalDictationTranscriber: LocalDictationTranscribing {
    private var selectedModel: DictationModelID
    private let whisper: WhisperKitDictationTranscriber
    private let parakeet = ParakeetUnifiedDictationTranscriber()
    private let parakeetV3 = ParakeetV3DictationTranscriber()

    init(selectedModel: DictationModelID) {
        self.selectedModel = selectedModel
        whisper = WhisperKitDictationTranscriber(
            selectedModel: selectedModel.whisperModel ?? .smallEnglish
        )
    }

    func install(_ model: DictationModelID) async throws {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return }
            try await whisper.install(whisperModel)
        case .parakeetUnifiedEnglish:
            try await parakeet.install()
        case .parakeetV3Multilingual:
            try await parakeetV3.install()
        }
    }

    func isModelInstalled(_ model: DictationModelID) async -> Bool {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return false }
            return await whisper.isModelInstalled(whisperModel)
        case .parakeetUnifiedEnglish:
            return await parakeet.isModelInstalled()
        case .parakeetV3Multilingual:
            return await parakeetV3.isModelInstalled()
        }
    }

    func removeModel(_ model: DictationModelID) async throws {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return }
            try await whisper.remove(whisperModel)
        case .parakeetUnifiedEnglish:
            try await parakeet.remove()
        case .parakeetV3Multilingual:
            try await parakeetV3.remove()
        }
    }

    func selectModel(_ model: DictationModelID) async throws {
        guard model != selectedModel else { return }
        guard await isModelInstalled(model) else {
            throw WhisperKitDictationError.modelNotInstalled
        }

        if selectedModel.engine == .whisperKit, model.engine == .whisperKit {
            guard let whisperModel = model.whisperModel else { return }
            try await whisper.selectModel(whisperModel)
        } else {
            await unload(model: selectedModel)
            if let whisperModel = model.whisperModel {
                try await whisper.selectModel(whisperModel)
            }
        }
        selectedModel = model
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        switch selectedModel {
        case .whisperSmallEnglish, .whisperLargeV3:
            return try await whisper.transcribe(audio)
        case .parakeetUnifiedEnglish:
            return try await parakeet.transcribe(audio)
        case .parakeetV3Multilingual:
            return try await parakeetV3.transcribe(audio)
        }
    }

    func prepare() async {
        switch selectedModel {
        case .whisperSmallEnglish, .whisperLargeV3:
            await whisper.prepare()
        case .parakeetUnifiedEnglish:
            await parakeet.prepare()
        case .parakeetV3Multilingual:
            await parakeetV3.prepare()
        }
    }

    func cancelTranscription() async {
        switch selectedModel {
        case .whisperSmallEnglish, .whisperLargeV3:
            await whisper.cancelTranscription()
        case .parakeetUnifiedEnglish:
            await parakeet.cancelTranscription()
        case .parakeetV3Multilingual:
            await parakeetV3.cancelTranscription()
        }
    }

    private func unload(model: DictationModelID) async {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            await whisper.unload()
        case .parakeetUnifiedEnglish:
            await parakeet.unload()
        case .parakeetV3Multilingual:
            await parakeetV3.unload()
        }
    }
}
