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

    func isSelectedModelInstalled() async -> Bool {
        await isModelInstalled(selectedModel)
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
        switch selectedModel.engine {
        case .whisperKit:
            return try await whisper.transcribe(audio)
        case .fluidAudio:
            switch selectedModel {
            case .parakeetUnifiedEnglish:
                return try await parakeet.transcribe(audio)
            case .parakeetV3Multilingual:
                return try await parakeetV3.transcribe(audio)
            case .whisperSmallEnglish, .whisperLargeV3:
                preconditionFailure("A Whisper model cannot use the FluidAudio route")
            }
        }
    }

    func cancelTranscription() async {
        switch selectedModel.engine {
        case .whisperKit:
            await whisper.cancelTranscription()
        case .fluidAudio:
            switch selectedModel {
            case .parakeetUnifiedEnglish:
                await parakeet.cancelTranscription()
            case .parakeetV3Multilingual:
                await parakeetV3.cancelTranscription()
            case .whisperSmallEnglish, .whisperLargeV3:
                break
            }
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

private extension DictationModelID {
    var engine: DictationEngineID {
        switch self {
        case .whisperSmallEnglish, .whisperLargeV3:
            return .whisperKit
        case .parakeetUnifiedEnglish, .parakeetV3Multilingual:
            return .fluidAudio
        }
    }
}
