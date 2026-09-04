@preconcurrency import ArgmaxCore
@preconcurrency import FluidAudio
import CryptoKit
import Foundation

actor ParakeetV3DictationTranscriber: LocalDictationTranscribing {
    private var manager: AsrManager?
    private var validatedModelFolder: URL?
    private var loadTask: (generation: UInt, task: Task<AsrManager, Error>)?
    private var loadGeneration: UInt = 0
    private var transcriptionTask: (generation: UInt, task: Task<String, Error>)?
    private var activeTranscriptionGeneration: UInt?
    private var transcriptionGeneration: UInt = 0

    init() {
        ModelHub.offlineMode = true
    }

    func install() async throws {
        validatedModelFolder = try await Self.resolvePinnedModelFolder(
            allowDownload: DictationModelRequest.settingsDownload.allowsDownload
        )
    }

    func remove() async throws {
        await unload()
        try Self.removeCachedModel()
        validatedModelFolder = nil
    }

    func isModelInstalled() -> Bool {
        guard let folder = Self.cachedModelFolder() else {
            validatedModelFolder = nil
            return false
        }
        if validatedModelFolder == folder { return true }
        guard (try? Self.validateModel(at: folder)) == true else {
            Self.clearCachedModelFolder()
            validatedModelFolder = nil
            return false
        }
        validatedModelFolder = folder
        return true
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        guard audio.sampleRate == DictationAudio.transcriptionSampleRate else {
            throw ParakeetV3DictationError.invalidSampleRate(audio.sampleRate)
        }
        guard activeTranscriptionGeneration == nil else {
            throw ParakeetV3DictationError.transcriptionAlreadyRunning
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
        guard activeTranscriptionGeneration == generation else { throw CancellationError() }

        let task = Task<String, Error> {
            try Task.checkCancellation()
            let decoderLayers = await manager.decoderLayerCount
            var decoderState = try TdtDecoderState(decoderLayers: decoderLayers)
            let result = try await manager.transcribe(
                audio.samples,
                decoderState: &decoderState
            )
            try Task.checkCancellation()
            return result.text
        }
        transcriptionTask = (generation, task)
        let transcript = try await task.value
        guard activeTranscriptionGeneration == generation else { throw CancellationError() }
        return transcript
    }

    func prepare() async {
        _ = try? await loadManager()
    }

    func cancelTranscription() async {
        transcriptionGeneration &+= 1
        let cancelledGeneration = activeTranscriptionGeneration
        let cancelledTranscription = transcriptionTask
        cancelledTranscription?.task.cancel()
        if let task = cancelledTranscription?.task {
            _ = await task.result
        }
        if activeTranscriptionGeneration == cancelledGeneration {
            activeTranscriptionGeneration = nil
        }
        if transcriptionTask?.generation == cancelledTranscription?.generation {
            transcriptionTask = nil
        }
    }

    func unload() async {
        await cancelTranscription()
        let pendingLoad = loadTask
        loadGeneration &+= 1
        pendingLoad?.task.cancel()
        if let task = pendingLoad?.task {
            _ = await task.result
        }
        loadTask = nil
        if let manager {
            await manager.cleanup()
        }
        manager = nil
    }

    private func loadManager() async throws -> AsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.task.value }

        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task<AsrManager, Error> {
            let snapshot = try await Self.resolvePinnedModelFolder(
                allowDownload: DictationModelRequest.transcription.allowsDownload
            )
            try Task.checkCancellation()
            let modelFolder = try Self.prepareFluidAudioLayout(for: snapshot)
            let models = try await Self.loadModelsOffline(from: modelFolder)
            try Task.checkCancellation()
            return AsrManager(models: models)
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
            validatedModelFolder = Self.cachedModelFolder()
            loadTask = nil
            return loadedManager
        } catch {
            if loadTask?.generation == generation {
                loadTask = nil
            }
            throw error
        }
    }

    private static let repository = "FluidInference/parakeet-tdt-0.6b-v3-coreml"
    private static let revision = "aed02740059203c4a87495924f685de3722ae9ce"
    private static let fluidAudioFolderName = "parakeet-tdt-0.6b-v3"
    private static let cachedModelFolderKey =
        "gojo.dictation.modelFolder.parakeet-tdt-0.6b-v3.int8.\(revision)"
    private static let maximumModelBytes: UInt64 = 483_105_645

    private static let downloadPatterns = [
        "Preprocessor.mlmodelc/*",
        "Encoder.mlmodelc/*",
        "Decoder.mlmodelc/*",
        "JointDecisionv3.mlmodelc/*",
        "parakeet_vocab.json",
    ]

    private static let modelSHA256: [String: String] = [
        "Preprocessor.mlmodelc/analytics/coremldata.bin": "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d",
        "Preprocessor.mlmodelc/coremldata.bin": "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d",
        "Preprocessor.mlmodelc/metadata.json": "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf",
        "Preprocessor.mlmodelc/model.mil": "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93",
        "Preprocessor.mlmodelc/weights/weight.bin": "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea",
        "Encoder.mlmodelc/analytics/coremldata.bin": "42e638870d73f26b332918a3496ce36793fbb413a81cbd3d16ba01328637a105",
        "Encoder.mlmodelc/coremldata.bin": "d48034a167a82e88fc3df64f60af963ab3983538271175b8319e7d5720a0fb86",
        "Encoder.mlmodelc/metadata.json": "da24da9cca943fb29d7fa8e376d57fca7cb3aa08ca51b956b0b0e56813f087e9",
        "Encoder.mlmodelc/model.mil": "ed7b19156ca29fa7dfd6891deb9fda4b0e8893f68597c985d135736546a43808",
        "Encoder.mlmodelc/weights/weight.bin": "e2020f323703477a5b21d7c2d282c403e371afb5962e79877e3033e73ba6f421",
        "Decoder.mlmodelc/analytics/coremldata.bin": "4238c4e81ecd0dc94bd7dfbb60f7e2cc824107c1ffe0387b8607b72833dba350",
        "Decoder.mlmodelc/coremldata.bin": "18647af085d87bd8f3121c8a9b4d4564c1ede038dab63d295b4e745cf2d7fb99",
        "Decoder.mlmodelc/metadata.json": "a39e93cd8371b8ded92635c7804fcd0590f0d1dd9415c6d19a0484be073077d9",
        "Decoder.mlmodelc/model.mil": "ef2a0a281695398a62fde86ac269c68f73d5b578d7ed3b31f2ba91a2d1ea1f35",
        "Decoder.mlmodelc/weights/weight.bin": "48adf0f0d47c406c8253d4f7fef967436a39da14f5a65e66d5a4b407be355d41",
        "JointDecisionv3.mlmodelc/analytics/coremldata.bin": "26def4bf73dd56d29dee21c8ef97cb8969e62f6120ed1adc91e46828e2737b6c",
        "JointDecisionv3.mlmodelc/coremldata.bin": "f5fc08b741400f0088492c9e839418b1e18522f19cba28d361dd030c5f398342",
        "JointDecisionv3.mlmodelc/metadata.json": "d9307211b9a37e0f0ac260c7660b1571a3de25841035cfdf9b58fd40425f890f",
        "JointDecisionv3.mlmodelc/model.mil": "be60732943389a047175111a83f8839f3eb39d4803adafa828a0871b2f39818d",
        "JointDecisionv3.mlmodelc/weights/weight.bin": "4e0e63d840032f7f07ddb1d64446051166281e5491bf22da8a945c41f6eedb3e",
        "parakeet_vocab.json": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735",
    ]

    private static func cachedModelFolder() -> URL? {
        guard let expectedURL = DictationModelStorage.hubRepositoryRoot(repository),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: cachedModelFolderKey),
                  matches: expectedURL
              ) else {
            clearCachedModelFolder()
            return nil
        }
        let hasEveryRequiredFile = modelSHA256.keys.allSatisfy { relativePath in
            FileManager.default.fileExists(
                atPath: expectedURL.appendingPathComponent(relativePath).path
            )
        }
        guard hasEveryRequiredFile else {
            UserDefaults.standard.removeObject(forKey: cachedModelFolderKey)
            return nil
        }
        return expectedURL
    }

    private static func clearCachedModelFolder() {
        UserDefaults.standard.removeObject(forKey: cachedModelFolderKey)
    }

    private static func removeCachedModel() throws {
        do {
            if let root = try? modelLayoutRoot(createIfNeeded: false) {
                try DictationModelStorage.removeAllowlistedTopLevelItems(
                    from: root,
                    topLevelItems: [fluidAudioFolderName]
                )
            }
        } catch {
            throw WhisperKitDictationError.modelRemovalFailed
        }

        guard let folder = DictationModelStorage.hubRepositoryRoot(repository),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: cachedModelFolderKey),
                  matches: folder
              ) else {
            clearCachedModelFolder()
            throw WhisperKitDictationError.modelRemovalFailed
        }
        let topLevelItems = [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc",
            "parakeet_vocab.json",
        ]
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

    private static func resolvePinnedModelFolder(allowDownload: Bool) async throws -> URL {
        if let cachedURL = cachedModelFolder() {
            if (try? validateModel(at: cachedURL)) == true {
                return cachedURL
            }
            clearCachedModelFolder()
        }

        guard allowDownload else {
            throw WhisperKitDictationError.modelNotInstalled
        }

        let hub = HubApiWrapper(useBackgroundSession: true)
        let snapshot = try await hub.snapshot(
            from: HubApiWrapper.Repo(id: repository),
            revision: revision,
            matching: downloadPatterns
        )
        guard let expectedURL = DictationModelStorage.hubRepositoryRoot(repository),
              snapshot.standardizedFileURL.path == expectedURL.standardizedFileURL.path else {
            throw WhisperKitDictationError.modelUnavailable(repository)
        }
        _ = try validateModel(at: snapshot)
        UserDefaults.standard.set(snapshot.path, forKey: cachedModelFolderKey)
        return snapshot
    }

    private static func prepareFluidAudioLayout(for snapshot: URL) throws -> URL {
        let root = try modelLayoutRoot()
        let modelFolder = root.appendingPathComponent(fluidAudioFolderName, isDirectory: true)
        let fileManager = FileManager.default

        let existingSymlink = try? fileManager.destinationOfSymbolicLink(atPath: modelFolder.path)
        if fileManager.fileExists(atPath: modelFolder.path) || existingSymlink != nil {
            let resolvedFolder = modelFolder.resolvingSymlinksInPath().standardizedFileURL
            if resolvedFolder == snapshot.resolvingSymlinksInPath().standardizedFileURL {
                return modelFolder
            }
            try fileManager.removeItem(at: modelFolder)
        }

        try fileManager.createSymbolicLink(at: modelFolder, withDestinationURL: snapshot)
        guard modelSHA256.keys.allSatisfy({ relativePath in
            fileManager.fileExists(atPath: modelFolder.appendingPathComponent(relativePath).path)
        }) else {
            try? fileManager.removeItem(at: modelFolder)
            throw ParakeetV3DictationError.localLayoutFailed
        }
        return modelFolder
    }

    private static func modelLayoutRoot(createIfNeeded: Bool = true) throws -> URL {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw ParakeetV3DictationError.localLayoutFailed
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "computer.handy.gojo"
        let root = caches
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("PinnedDictationModels", isDirectory: true)
            .appendingPathComponent("parakeet-v3-int8-\(revision)", isDirectory: true)
        if createIfNeeded {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    private static func loadModelsOffline(from modelFolder: URL) async throws -> AsrModels {
        ModelHub.offlineMode = true
        return try await AsrModels.load(
            from: modelFolder,
            version: .v3,
            encoderPrecision: .int8
        )
    }

    private static func validateModel(at folder: URL) throws -> Bool {
        var totalBytes: UInt64 = 0
        for (relativePath, expectedHash) in modelSHA256 {
            let fileURL = folder.appendingPathComponent(relativePath)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw ParakeetV3DictationError.integrityFailed(relativePath)
            }
            totalBytes += UInt64(fileSize)
            guard totalBytes <= maximumModelBytes,
                  try sha256(of: fileURL) == expectedHash else {
                throw ParakeetV3DictationError.integrityFailed(relativePath)
            }
        }
        return true
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

enum ParakeetV3DictationError: LocalizedError {
    case integrityFailed(String)
    case invalidSampleRate(Double)
    case localLayoutFailed
    case transcriptionAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .integrityFailed(let path):
            return "The Parakeet v3 model failed its integrity check (\(path))."
        case .invalidSampleRate(let sampleRate):
            return "The local speech model expected 16 kHz audio but received \(Int(sampleRate)) Hz."
        case .localLayoutFailed:
            return "Gojo could not prepare the Parakeet v3 model for offline use."
        case .transcriptionAlreadyRunning:
            return "A local transcription is already running."
        }
    }
}
