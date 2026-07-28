@preconcurrency import ArgmaxCore
@preconcurrency import WhisperKit
import CryptoKit
import Foundation

actor WhisperKitDictationTranscriber: LocalDictationTranscribing {
    static let modelRepository = WhisperDictationModel.repository
    static let modelRevision = WhisperDictationModel.revision

    private final class LoadedWhisperKit: @unchecked Sendable {
        let value: WhisperKit

        init(_ value: WhisperKit) {
            self.value = value
        }
    }

    private struct ModelDescriptor: Sendable {
        let model: WhisperDictationModel
        let maximumBytes: UInt64
        let sha256: [String: String]
    }

    private var selectedModel: WhisperDictationModel
    private var model: (identifier: WhisperDictationModel, value: WhisperKit)?
    private var modelTask: (
        identifier: WhisperDictationModel,
        generation: UInt,
        task: Task<LoadedWhisperKit, Error>
    )?
    private var modelTaskGeneration: UInt = 0
    private var transcriptionTask: (generation: UInt, task: Task<String, Error>)?
    private var activeTranscriptionGeneration: UInt?
    private var transcriptionGeneration: UInt = 0

    init(selectedModel: WhisperDictationModel = .smallEnglish) {
        self.selectedModel = selectedModel
    }

    func install(_ requestedModel: WhisperDictationModel) async throws {
        _ = try await Self.resolvePinnedModelFolder(
            for: requestedModel,
            allowDownload: DictationModelRequest.settingsDownload.allowsDownload
        )
    }

    func remove(_ requestedModel: WhisperDictationModel) async throws {
        guard activeTranscriptionGeneration == nil else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
        }
        if model?.identifier == requestedModel {
            model = nil
        }
        if let pending = modelTask, pending.identifier == requestedModel {
            modelTaskGeneration &+= 1
            pending.task.cancel()
            _ = await pending.task.result
            if modelTask?.generation == pending.generation {
                modelTask = nil
            }
        }
        try Self.removeCachedModel(requestedModel)
    }

    func isModelInstalled(_ requestedModel: WhisperDictationModel) -> Bool {
        Self.cachedModelFolder(for: requestedModel) != nil
    }

    func selectModel(_ requestedModel: WhisperDictationModel) async throws {
        guard activeTranscriptionGeneration == nil else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
        }
        guard Self.cachedModelFolder(for: requestedModel) != nil else {
            throw WhisperKitDictationError.modelNotInstalled
        }
        guard requestedModel != selectedModel else { return }

        modelTaskGeneration &+= 1
        let pendingModelTask = modelTask
        pendingModelTask?.task.cancel()
        if let task = pendingModelTask?.task {
            _ = await task.result
        }
        modelTask = nil
        model = nil
        selectedModel = requestedModel
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        guard audio.sampleRate == DictationAudio.transcriptionSampleRate else {
            throw WhisperKitDictationError.invalidSampleRate(audio.sampleRate)
        }

        guard activeTranscriptionGeneration == nil else {
            throw WhisperKitDictationError.transcriptionAlreadyRunning
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

        let model = try await loadSelectedModel()
        try Task.checkCancellation()
        guard activeTranscriptionGeneration == generation else { throw CancellationError() }
        let options = DecodingOptions(
            language: "en",
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            noSpeechThreshold: 0.6,
            chunkingStrategy: .vad
        )
        let task = Task<String, Error> {
            let results = try await model.transcribe(
                audioArray: audio.samples,
                decodeOptions: options
            )
            return results.map(\.text).joined(separator: " ")
        }
        transcriptionTask = (generation, task)
        return try await task.value
    }

    func cancelTranscription() async {
        transcriptionGeneration &+= 1
        let cancelledGeneration = activeTranscriptionGeneration
        let cancelledTranscription = transcriptionTask
        let cancelledModelTask = modelTask
        cancelledTranscription?.task.cancel()
        cancelledModelTask?.task.cancel()

        // Core ML work may not stop synchronously when its Swift task is
        // cancelled. Keep the actor unavailable until both tasks have fully
        // unwound so a replacement session cannot reuse mutable WhisperKit
        // state concurrently.
        if let task = cancelledTranscription?.task {
            _ = await task.result
        }
        if let task = cancelledModelTask?.task {
            _ = await task.result
        }

        if activeTranscriptionGeneration == cancelledGeneration {
            activeTranscriptionGeneration = nil
        }
        if transcriptionTask?.generation == cancelledTranscription?.generation {
            transcriptionTask = nil
        }
        if modelTask?.generation == cancelledModelTask?.generation {
            modelTask = nil
        }
    }

    func unload() async {
        await cancelTranscription()
        let pendingModelTask = modelTask
        pendingModelTask?.task.cancel()
        if let task = pendingModelTask?.task {
            _ = await task.result
        }
        modelTask = nil
        model = nil
    }

    private func loadSelectedModel() async throws -> WhisperKit {
        let requestedModel = selectedModel
        if let model, model.identifier == requestedModel { return model.value }
        if let modelTask, modelTask.identifier == requestedModel {
            return try await modelTask.task.value.value
        }

        modelTask?.task.cancel()
        modelTaskGeneration &+= 1
        let generation = modelTaskGeneration
        let task = Task<LoadedWhisperKit, Error> {
            let modelFolder = try await Self.resolvePinnedModelFolder(
                for: requestedModel,
                allowDownload: DictationModelRequest.transcription.allowsDownload
            )
            let configuration = WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
            return try await LoadedWhisperKit(WhisperKit(configuration))
        }
        modelTask = (requestedModel, generation, task)
        do {
            let loadedModel = try await task.value.value
            guard modelTask?.generation == generation,
                  selectedModel == requestedModel else {
                throw CancellationError()
            }
            model = (requestedModel, loadedModel)
            modelTask = nil
            return loadedModel
        } catch {
            if modelTask?.generation == generation {
                modelTask = nil
            }
            throw error
        }
    }

    private static func cachedModelFolderKey(for model: WhisperDictationModel) -> String {
        "gojo.dictation.modelFolder.\(model.rawValue).\(modelRevision)"
    }

    private static func cachedModelFolder(for model: WhisperDictationModel) -> URL? {
        let cacheKey = cachedModelFolderKey(for: model)
        guard let expectedURL = expectedModelFolder(for: model),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: cacheKey),
                  matches: expectedURL
              ) else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            return nil
        }
        let descriptor = descriptor(for: model)
        let hasEveryRequiredFile = descriptor.sha256.keys.allSatisfy { relativePath in
            FileManager.default.fileExists(
                atPath: expectedURL.appending(path: relativePath).path
            )
        }
        guard hasEveryRequiredFile else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            return nil
        }
        return expectedURL
    }

    private static func removeCachedModel(_ model: WhisperDictationModel) throws {
        let cacheKey = cachedModelFolderKey(for: model)
        guard let repositoryRoot = DictationModelStorage.hubRepositoryRoot(modelRepository),
              let expectedURL = expectedModelFolder(for: model),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: cacheKey),
                  matches: expectedURL
              ) else {
            UserDefaults.standard.removeObject(forKey: cacheKey)
            throw WhisperKitDictationError.modelRemovalFailed
        }
        do {
            try DictationModelStorage.removeAllowlistedItems(
                from: repositoryRoot,
                topLevelItems: [model.folderName]
            )
            UserDefaults.standard.removeObject(forKey: cacheKey)
        } catch {
            throw WhisperKitDictationError.modelRemovalFailed
        }
    }

    private static func expectedModelFolder(for model: WhisperDictationModel) -> URL? {
        DictationModelStorage.hubRepositoryRoot(modelRepository)?
            .appendingPathComponent(model.folderName, isDirectory: true)
    }

    private static func resolvePinnedModelFolder(
        for requestedModel: WhisperDictationModel,
        allowDownload: Bool
    ) async throws -> URL {
        let descriptor = descriptor(for: requestedModel)
        let cacheKey = cachedModelFolderKey(for: requestedModel)
        if let cachedURL = cachedModelFolder(for: requestedModel) {
            if (try? validateModel(at: cachedURL, descriptor: descriptor)) == true {
                return cachedURL
            }
            UserDefaults.standard.removeObject(forKey: cacheKey)
        }

        guard allowDownload else {
            throw WhisperKitDictationError.modelNotInstalled
        }

        let hub = HubApiWrapper(useBackgroundSession: true)
        let repo = HubApiWrapper.Repo(id: modelRepository)
        let searchPath = "\(requestedModel.folderName)/*"
        let filenames = try await hub.getFilenames(
            from: repo,
            revision: modelRevision,
            matching: [searchPath]
        )
        let folders = Set(filenames.compactMap { $0.split(separator: "/").first.map(String.init) })
        guard let folder = folders.first, folders.count == 1 else {
            throw WhisperKitDictationError.modelUnavailable(requestedModel.rawValue)
        }

        let snapshot = try await hub.snapshot(
            from: repo,
            revision: modelRevision,
            matching: [searchPath]
        )
        let modelFolder = snapshot.appending(path: folder, directoryHint: .isDirectory)
        guard let expectedURL = expectedModelFolder(for: requestedModel),
              modelFolder.standardizedFileURL.path == expectedURL.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: modelFolder.path) else {
            throw WhisperKitDictationError.modelUnavailable(requestedModel.rawValue)
        }
        _ = try validateModel(at: modelFolder, descriptor: descriptor)
        UserDefaults.standard.set(modelFolder.path, forKey: cacheKey)
        return modelFolder
    }

    private static func descriptor(for model: WhisperDictationModel) -> ModelDescriptor {
        switch model {
        case .smallEnglish:
            return ModelDescriptor(model: model, maximumBytes: 230_000_000, sha256: smallEnglishSHA256)
        case .largeV3:
            return ModelDescriptor(model: model, maximumBytes: 626_718_238, sha256: largeV3SHA256)
        }
    }

    private static let smallEnglishSHA256: [String: String] = [
        "AudioEncoder.mlmodelc/analytics/coremldata.bin": "dedfa7d9707c7a23e5dac213d0a7ed1bcb770586a8010c8b97b5415c7ab03a98",
        "AudioEncoder.mlmodelc/coremldata.bin": "3fdc970c253d212db32bbb47c713e54d1b28677f9ff845834020dab59cfc5e9c",
        "AudioEncoder.mlmodelc/metadata.json": "cc5b8143fddf32493a28fbd9cdda8222a862912162a665f40290f94dcbf5b4b5",
        "AudioEncoder.mlmodelc/model.mil": "233a772aceff5bf09aa5a1a51c03fdb2e0bca257b430f9b92bf461ad51ccd584",
        "AudioEncoder.mlmodelc/model.mlmodel": "20bf50c2166e980a7b89b503a9b61e580198843408bf1a1f5493c7199f542221",
        "AudioEncoder.mlmodelc/weights/weight.bin": "87be26c3c1e2a804cd739fcd24a7c97ed3b860332c46de173ed69290f5982cb0",
        "MelSpectrogram.mlmodelc/analytics/coremldata.bin": "c4f367993f0198e9858a4d89fb054318982c91a9bb5946e29231421c2f1100b9",
        "MelSpectrogram.mlmodelc/coremldata.bin": "806321f1034184a10b04dc50816219dec8ae9789698712050c81edecb9bb5aa7",
        "MelSpectrogram.mlmodelc/metadata.json": "6a95b18553edd73f018fe954d203d9c3cfa70dfa596d140c20f519ca471fe6be",
        "MelSpectrogram.mlmodelc/model.mil": "7877c0f519a97a7c0dc1e0e9f8ae316bd864afcb2cffa89c770184b07e7767c9",
        "MelSpectrogram.mlmodelc/weights/weight.bin": "801024dbc7a89c677be1f8b285de3409e35f7d1786c9c8d9d0d6842ac57a1c83",
        "TextDecoder.mlmodelc/analytics/coremldata.bin": "4ca8f36ba20e72c389a2c207022bd645e32db617d79cda7679930099099c0691",
        "TextDecoder.mlmodelc/coremldata.bin": "572ff1890dfadfdb9193d1dc3e2bca618fbebbdf65e40d1f6ad4d5cfbee8b806",
        "TextDecoder.mlmodelc/metadata.json": "a84c1b3848f48edbd5101602ca39c5784884d4875e0cf4fe92d02cb610a7300e",
        "TextDecoder.mlmodelc/model.mil": "e3ca09e9e27ede692cdc7180f3e809a0d1c7cc3985d0f31c687bca398e1dfca4",
        "TextDecoder.mlmodelc/model.mlmodel": "768ef236a82b0836cd27b9b4d30310344766ea7d5df3385149c61082568a9a04",
        "TextDecoder.mlmodelc/weights/weight.bin": "e6cb706fa11e5352ad9e9c99b7e4bdbd9b0d73289c79303ada949a92a04c04af",
        "config.json": "5cbba95e3fda213c33957ddcd76070270e0ae55f926909f332790a1824810219",
        "generation_config.json": "6e822c9d1d1eed9a8733b3fbdd69d2f00222afac29dbfb173864988c1707a34d",
    ]

    private static let largeV3SHA256: [String: String] = [
        "AudioEncoder.mlmodelc/analytics/coremldata.bin": "56793886ab1adb9ca8a4e335efbe8af6640f40d958ab2d29c3ad2d7d6f712e95",
        "AudioEncoder.mlmodelc/coremldata.bin": "ffa9eb76e8e9d9be75a4d527e5249e61d67fd43081c5aa110fd24efa6c8c5ea3",
        "AudioEncoder.mlmodelc/metadata.json": "a87a3375afe79e88e27af30247e234e706b98679dedfd1b021a74f7ee108c669",
        "AudioEncoder.mlmodelc/model.mil": "3cec2580fb07b12a88087f0e1586c6ba2982980eb36499561e1ffca2b0950442",
        "AudioEncoder.mlmodelc/weights/weight.bin": "e4740fa28ed65907af754af893dfce98473fafb84dd8d718ad346985fe7678c1",
        "MelSpectrogram.mlmodelc/analytics/coremldata.bin": "c5be419f8622083ac7046306400643539f0e7577c843448c36defc090d41e7ce",
        "MelSpectrogram.mlmodelc/coremldata.bin": "2bfc12cffc2e45e039c7a18f384f09adffb72c182fcd93f9413d405d1a6c1130",
        "MelSpectrogram.mlmodelc/metadata.json": "2bc552e09a6f124d9e6c178dd1a6979e010206acb26308b2224887c9dcbeb35f",
        "MelSpectrogram.mlmodelc/model.mil": "c270b95b5f81d7f7d0b8a3e8f991d4e5812a37cad29349868a35b91f3a6a4463",
        "MelSpectrogram.mlmodelc/weights/weight.bin": "009d9fb8f6b589accfa08cebf1c712ef07c3405229ce3cfb3a57ee033c9d8a49",
        "TextDecoder.mlmodelc/analytics/coremldata.bin": "3913b8c9716b284a917cf3744f4d415f2a05e2b910594a14c6cc10092284d3f8",
        "TextDecoder.mlmodelc/coremldata.bin": "3faabaf66930e66956d8291d0ff485fb382496e30a91a7185548b9b898ce90a9",
        "TextDecoder.mlmodelc/metadata.json": "994f6030d7b1a8be999940444c3cf5d6a57d40ddd4423cf1d1fc93520aa1b052",
        "TextDecoder.mlmodelc/model.mil": "dbe833be9e64348c95b7fa598d0ae4309a91aedce4e82fa500a714b0e4b5d754",
        "TextDecoder.mlmodelc/weights/weight.bin": "d69700903d518ada33170ab77faaaf464496fb9ff65752c6d5a6109aa2fb02db",
        "config.json": "f01d83dd891791d6f12421c05d3ed8ebbe70866f10d6c9a7a7e80b558ce5a0f1",
        "generation_config.json": "7fbb053a023be11fbeccd8421811610308143daa93d9617c52aab4a0fa1491c6",
    ]

    private static func validateModel(at folder: URL, descriptor: ModelDescriptor) throws -> Bool {
        var totalBytes: UInt64 = 0
        for (relativePath, expectedHash) in descriptor.sha256 {
            let fileURL = folder.appending(path: relativePath)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw WhisperKitDictationError.modelIntegrityFailed(relativePath)
            }
            totalBytes += UInt64(fileSize)
            guard totalBytes <= descriptor.maximumBytes,
                  try sha256(of: fileURL) == expectedHash else {
                throw WhisperKitDictationError.modelIntegrityFailed(relativePath)
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

enum WhisperKitDictationError: LocalizedError {
    case invalidSampleRate(Double)
    case modelNotInstalled
    case modelUnavailable(String)
    case modelIntegrityFailed(String)
    case modelRemovalFailed
    case transcriptionAlreadyRunning

    var errorDescription: String? {
        switch self {
        case .invalidSampleRate(let sampleRate):
            return "The local speech model expected 16 kHz audio but received \(Int(sampleRate)) Hz."
        case .modelNotInstalled:
            return "Download a voice model in Gojo Settings first."
        case .modelUnavailable(let model):
            return "Gojo could not download the \(model) speech model."
        case .modelIntegrityFailed(let path):
            return "The local speech model failed its integrity check (\(path))."
        case .modelRemovalFailed:
            return "Gojo could not remove the local speech model."
        case .transcriptionAlreadyRunning:
            return "A local transcription is already running."
        }
    }
}
