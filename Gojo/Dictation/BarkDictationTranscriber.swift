@preconcurrency import ArgmaxCore
import CryptoKit
import Foundation

actor BarkDictationTranscriber: LocalDictationTranscribing {
    private let variant: BarkModelVariant

    init(variant: BarkModelVariant = .verbatim) {
        self.variant = variant
    }

    private var session: (id: UUID, request: DictationRecognitionRequest)?
    private var maintenanceInProgress = false
    private var manager: BarkSpeechEngine?
    private var modelValidation = DictationModelValidationCache()
    private var loadTask: (generation: UInt, task: Task<BarkSpeechEngine, Error>)?
    private var loadGeneration: UInt = 0
    private var transcriptionTask: (generation: UInt, task: Task<String, Error>)?
    private var activeTranscriptionGeneration: UInt?
    private var transcriptionGeneration: UInt = 0

    func beginSession(_ plan: DictationSessionPlan) async throws {
        try validateRequest(plan.recognition)
        guard session == nil else { throw WhisperKitDictationError.sessionAlreadyActive }
        session = (plan.id, plan.recognition)
    }

    func endSession(_ id: UUID) async {
        guard session?.id == id else { return }
        await cancelTranscription()
        if session?.id == id { session = nil }
    }

    private func validateRequest(_ request: DictationRecognitionRequest) throws {
        guard !maintenanceInProgress else { throw BarkDictationError.transcriptionAlreadyRunning }
        guard case .local(let local) = request, local.model == variant.modelID,
              session == nil || session?.request == request else {
            throw WhisperKitDictationError.incompatibleRecognitionRequest
        }
    }

    func install() async throws {
        guard #available(macOS 15.0, *) else { throw BarkRuntimeError.unsupportedSystem }
        #if !arch(arm64)
        throw BarkRuntimeError.unsupportedSystem
        #endif
        guard session == nil, activeTranscriptionGeneration == nil,
              loadTask == nil, !maintenanceInProgress else {
            throw BarkDictationError.transcriptionAlreadyRunning
        }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        await unloadResources()
        _ = try await resolvePinnedModelFolder(
            allowDownload: DictationModelRequest.settingsDownload.allowsDownload
        )
    }

    func remove() async throws {
        guard session == nil, !maintenanceInProgress else {
            throw BarkDictationError.transcriptionAlreadyRunning
        }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        await unloadResources()
        modelValidation.invalidate()
        try removeCachedModel()
    }

    func isModelInstalled() -> Bool {
        installedModelFolder() != nil
    }

    private func installedModelFolder() -> URL? {
        guard let folder = cachedModelFolder(),
              let validatedFolder = try? modelValidation.validatedFolder(
                  at: folder,
                  requiredFiles: Array(variant.modelSHA256.keys),
                  validate: validateModel
              ) else {
            clearCachedModelFolder()
            modelValidation.invalidate()
            return nil
        }
        return validatedFolder
    }

    func transcribe(_ audio: DictationAudio, request: DictationRecognitionRequest) async throws -> String {
        try validateRequest(request)
        guard audio.sampleRate == DictationAudio.transcriptionSampleRate else {
            throw BarkDictationError.invalidSampleRate(audio.sampleRate)
        }
        guard activeTranscriptionGeneration == nil else {
            throw BarkDictationError.transcriptionAlreadyRunning
        }
        guard isModelInstalled() else {
            throw WhisperKitDictationError.modelNotInstalled
        }

        transcriptionGeneration &+= 1
        let generation = transcriptionGeneration
        activeTranscriptionGeneration = generation
        defer {
            if activeTranscriptionGeneration == generation {
                activeTranscriptionGeneration = nil
            }
            if transcriptionTask?.generation == generation {
                transcriptionTask = nil
            }
        }

        let manager = try await loadManager()
        try Task.checkCancellation()
        guard activeTranscriptionGeneration == generation,
              transcriptionGeneration == generation else { throw CancellationError() }
        let task = Task.detached { () async throws -> String in
            try Task.checkCancellation()
            let transcript = try await manager.transcribe(audio.samples)
            try Task.checkCancellation()
            return transcript
        }
        transcriptionTask = (generation, task)
        let transcript = try await task.value
        try Task.checkCancellation()
        guard activeTranscriptionGeneration == generation,
              transcriptionGeneration == generation else { throw CancellationError() }
        return transcript
    }

    func prepare(request: DictationRecognitionRequest) async throws {
        try validateRequest(request)
        _ = try await loadManager()
    }

    func cancelTranscription() async {
        transcriptionGeneration &+= 1
        let cancelledGeneration = activeTranscriptionGeneration
        let cancelledTranscription = transcriptionTask
        let cancelledLoad = loadTask
        loadGeneration &+= 1
        cancelledTranscription?.task.cancel()
        cancelledLoad?.task.cancel()
        if let task = cancelledTranscription?.task {
            _ = await task.result
        }
        if let task = cancelledLoad?.task {
            _ = await task.result
        }
        if activeTranscriptionGeneration == cancelledGeneration {
            activeTranscriptionGeneration = nil
        }
        if transcriptionTask?.generation == cancelledTranscription?.generation {
            transcriptionTask = nil
        }
        if loadTask?.generation == cancelledLoad?.generation {
            loadTask = nil
        }
    }

    func unload() async {
        guard session == nil, !maintenanceInProgress else { return }
        maintenanceInProgress = true
        defer { maintenanceInProgress = false }
        await unloadResources()
    }

    private func unloadResources() async {
        await cancelTranscription()
        let pendingLoad = loadTask
        loadGeneration &+= 1
        pendingLoad?.task.cancel()
        if let task = pendingLoad?.task {
            _ = await task.result
        }
        loadTask = nil
        await manager?.cleanup()
        manager = nil
    }

    private func loadManager() async throws -> BarkSpeechEngine {
        if let manager { return manager }
        if let loadTask {
            do {
                let loaded = try await loadTask.task.value
                guard loadGeneration == loadTask.generation else { throw CancellationError() }
                return loaded
            }
            catch is CancellationError { throw CancellationError() }
            catch { throw DictationModelPreparationError.classify(error) }
        }

        try DictationModelPreparationError.checkStorage()
        guard let modelFolder = installedModelFolder() else {
            throw WhisperKitDictationError.modelNotInstalled
        }
        loadGeneration &+= 1
        let generation = loadGeneration
        let variant = variant
        let task = Task.detached { () async throws -> BarkSpeechEngine in
            try await BarkSpeechEngine.load(variant: variant, from: modelFolder)
        }
        loadTask = (generation, task)
        do {
            let loadedManager = try await task.value
            guard loadTask?.generation == generation,
                  loadGeneration == generation else {
                await loadedManager.cleanup()
                throw CancellationError()
            }
            manager = loadedManager
            loadTask = nil
            return loadedManager
        } catch {
            if loadTask?.generation == generation {
                loadTask = nil
            }
            if error is CancellationError { throw error }
            throw DictationModelPreparationError.classify(error)
        }
    }

    private func cachedModelFolder() -> URL? {
        guard let expectedURL = DictationModelStorage.hubRepositoryRoot(variant.repository),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: variant.cachedModelFolderKey),
                  matches: expectedURL
              ) else {
            clearCachedModelFolder()
            return nil
        }
        let hasEveryRequiredFile = variant.modelSHA256.keys.allSatisfy { relativePath in
            FileManager.default.fileExists(
                atPath: expectedURL.appendingPathComponent(relativePath).path
            )
        }
        guard hasEveryRequiredFile else {
            UserDefaults.standard.removeObject(forKey: variant.cachedModelFolderKey)
            return nil
        }
        return expectedURL
    }

    private func clearCachedModelFolder() {
        UserDefaults.standard.removeObject(forKey: variant.cachedModelFolderKey)
    }

    private func removeCachedModel() throws {
        guard let folder = DictationModelStorage.hubRepositoryRoot(variant.repository),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: variant.cachedModelFolderKey),
                  matches: folder
              ) else {
            clearCachedModelFolder()
            throw WhisperKitDictationError.modelRemovalFailed
        }
        let topLevelItems = variant.removalItems
        do {
            try DictationModelStorage.removeAllowlistedItems(
                from: folder,
                topLevelItems: topLevelItems
            )
            clearCachedModelFolder()
        } catch {
            throw WhisperKitDictationError.modelRemovalFailed
        }
    }

    private func resolvePinnedModelFolder(allowDownload: Bool) async throws -> URL {
        if let cachedURL = installedModelFolder() { return cachedURL }

        guard allowDownload else {
            throw WhisperKitDictationError.modelNotInstalled
        }

        guard let expectedURL = DictationModelStorage.hubRepositoryRoot(variant.repository) else {
            throw WhisperKitDictationError.modelUnavailable(variant.repository)
        }
        for (path, expectedHash) in variant.modelSHA256 {
            let file = expectedURL.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try Task.checkCancellation()
            let actualHash = try Self.sha256(of: file)
            if actualHash != expectedHash {
                try Task.checkCancellation()
                try DictationModelStorage.removeAllowlistedItems(
                    from: expectedURL,
                    topLevelItems: variant.removalItems
                )
                modelValidation.invalidate()
                clearCachedModelFolder()
                break
            }
        }
        let hub = HubApiWrapper(useBackgroundSession: true)
        let snapshot = try await hub.snapshot(
            from: HubApiWrapper.Repo(id: variant.repository),
            revision: variant.revision,
            matching: variant.downloadPatterns
        )
        guard snapshot.standardizedFileURL.path == expectedURL.standardizedFileURL.path else {
            throw WhisperKitDictationError.modelUnavailable(variant.repository)
        }
        let validatedFolder = try modelValidation.validatedFolder(
            at: snapshot,
            requiredFiles: Array(variant.modelSHA256.keys),
            validate: validateModel
        )
        UserDefaults.standard.set(validatedFolder.path, forKey: variant.cachedModelFolderKey)
        return validatedFolder
    }

    private func validateModel(at folder: URL) throws {
        var totalBytes: UInt64 = 0
        for (relativePath, expectedHash) in variant.modelSHA256 {
            let fileURL = folder.appendingPathComponent(relativePath)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw BarkDictationError.integrityFailed(relativePath)
            }
            totalBytes += UInt64(fileSize)
            guard totalBytes <= variant.maximumModelBytes,
                  try Self.sha256(of: fileURL) == expectedHash else {
                throw BarkDictationError.integrityFailed(relativePath)
            }
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum BarkDictationError: LocalizedError {
    case integrityFailed(String)
    case invalidSampleRate(Double)
    case transcriptionAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .integrityFailed(let path):
            return "The Bark model failed its integrity check (\(path))."
        case .invalidSampleRate(let sampleRate):
            return "The local speech model expected 16 kHz audio but received \(Int(sampleRate)) Hz."
        case .transcriptionAlreadyRunning:
            return "A local transcription is already running."
        }
    }
}
