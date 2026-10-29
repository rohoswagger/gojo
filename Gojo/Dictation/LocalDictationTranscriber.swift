import Foundation

actor LocalDictationTranscriber: LocalDictationTranscribing {
    private var selectedModel: DictationModelID
    private let whisper: WhisperKitDictationTranscriber
    private let parakeet = ParakeetUnifiedDictationTranscriber()
    private let barkClean = BarkDictationTranscriber(variant: .clean)
    private let bark = BarkDictationTranscriber()
    private let parakeetV3 = ParakeetV3DictationTranscriber()
    private var session: (id: UUID, request: DictationLocalRecognition)?
    private var operations: [UUID: DictationModelID] = [:]
    private var maintenanceInProgress = false

    init(selectedModel: DictationModelID) {
        self.selectedModel = selectedModel
        whisper = WhisperKitDictationTranscriber(
            selectedModel: selectedModel.whisperModel ?? .smallEnglish
        )
    }

    func beginSession(_ plan: DictationSessionPlan) async throws {
        let request = try localRequest(plan.recognition)
        guard session == nil else { throw WhisperKitDictationError.sessionAlreadyActive }
        session = (plan.id, request)
        do {
            try await backend(for: request.model).beginSession(plan)
        } catch {
            if session?.id == plan.id { session = nil }
            throw error
        }
    }

    func endSession(_ id: UUID) async {
        guard let pinned = session, pinned.id == id else { return }
        await backend(for: pinned.request.model).endSession(id)
        if session?.id == id { session = nil }
    }

    func install(
        _ model: DictationModelID,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return }
            try await whisper.install(whisperModel, onProgress: onProgress)
        case .parakeetUnifiedEnglish:
            try await parakeet.install(onProgress: onProgress)
        case .underdogBark3CleanEnglish:
            try await barkClean.install(onProgress: onProgress)
        case .underdogBark3English:
            try await bark.install(onProgress: onProgress)
        case .parakeetV3Multilingual:
            try await parakeetV3.install(onProgress: onProgress)
        }
    }

    func isModelInstalled(_ model: DictationModelID) async -> Bool {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return false }
            return await whisper.isModelInstalled(whisperModel)
        case .parakeetUnifiedEnglish:
            return await parakeet.isModelInstalled()
        case .underdogBark3CleanEnglish:
            return await barkClean.isModelInstalled()
        case .underdogBark3English:
            return await bark.isModelInstalled()
        case .parakeetV3Multilingual:
            return await parakeetV3.isModelInstalled()
        }
    }

    func removeModel(_ model: DictationModelID) async throws {
        guard session == nil, operations.isEmpty, !maintenanceInProgress else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
        }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3:
            guard let whisperModel = model.whisperModel else { return }
            try await whisper.remove(whisperModel)
        case .parakeetUnifiedEnglish:
            try await parakeet.remove()
        case .underdogBark3CleanEnglish:
            try await barkClean.remove()
        case .underdogBark3English:
            try await bark.remove()
        case .parakeetV3Multilingual:
            try await parakeetV3.remove()
        }
    }

    func selectModel(_ model: DictationModelID) async throws {
        guard model != selectedModel else { return }
        guard session == nil, operations.isEmpty, !maintenanceInProgress else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
        }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
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

    func transcribe(_ audio: DictationAudio, request: DictationRecognitionRequest) async throws -> String {
        let local = try localRequest(request)
        let operation = UUID()
        operations[operation] = local.model
        defer { operations.removeValue(forKey: operation) }
        return try await backend(for: local.model).transcribe(audio, request: request)
    }

    func prepare(request: DictationRecognitionRequest) async throws {
        let local = try localRequest(request)
        let operation = UUID()
        operations[operation] = local.model
        defer { operations.removeValue(forKey: operation) }
        try await backend(for: local.model).prepare(request: request)
    }

    func cancelTranscription() async {
        var models = Set(operations.values)
        if let session { models.insert(session.request.model) }
        for model in models {
            await backend(for: model).cancelTranscription()
        }
    }

    func releaseModels() async {
        guard session == nil, operations.isEmpty, !maintenanceInProgress else { return }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        await whisper.unload()
        await parakeet.unload()
        await parakeetV3.unload()
        await bark.unload()
        await barkClean.unload()
    }

    private func localRequest(_ request: DictationRecognitionRequest) throws -> DictationLocalRecognition {
        guard !maintenanceInProgress else { throw WhisperKitDictationError.transcriptionAlreadyRunning }
        guard case .local(let local) = request,
              session == nil || session?.request == local else {
            throw WhisperKitDictationError.incompatibleRecognitionRequest
        }
        guard operations.values.allSatisfy({ $0 == local.model }) else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
        }
        return local
    }

    private func backend(for model: DictationModelID) -> any LocalDictationTranscribing {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3: return whisper
        case .parakeetUnifiedEnglish: return parakeet
        case .underdogBark3CleanEnglish: return barkClean
        case .underdogBark3English: return bark
        case .parakeetV3Multilingual: return parakeetV3
        }
    }

    private func unload(model: DictationModelID) async {
        switch model {
        case .whisperSmallEnglish, .whisperLargeV3: await whisper.unload()
        case .parakeetUnifiedEnglish: await parakeet.unload()
        case .underdogBark3CleanEnglish: await barkClean.unload()
        case .underdogBark3English: await bark.unload()
        case .parakeetV3Multilingual: await parakeetV3.unload()
        }
    }
}
