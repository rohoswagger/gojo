@preconcurrency import ArgmaxCore
@preconcurrency import AVFoundation
@preconcurrency import FluidAudio
import CryptoKit
import Foundation

actor ParakeetUnifiedDictationTranscriber: LocalDictationTranscribing, DictationStreamingTranscribing {
    private struct StreamingSession {
        let id: UUID
        let continuation: AsyncStream<(samples: [Float], sampleRate: Double)>.Continuation
        let consumeTask: Task<Void, Never>
    }

    private var manager: StreamingUnifiedAsrManager?
    private var validatedModelFolder: URL?
    private var loadTask: (generation: UInt, task: Task<StreamingUnifiedAsrManager, Error>)?
    private var loadGeneration: UInt = 0
    private var transcriptionTask: (generation: UInt, task: Task<String, Error>)?
    private var activeTranscriptionGeneration: UInt?
    private var transcriptionGeneration: UInt = 0
    private var streamingSession: StreamingSession?
    private var streamingSessionError: Error?

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
            throw ParakeetDictationError.invalidSampleRate(audio.sampleRate)
        }
        guard activeTranscriptionGeneration == nil else {
            throw ParakeetDictationError.transcriptionAlreadyRunning
        }
        guard streamingSession == nil else {
            throw ParakeetDictationError.transcriptionAlreadyRunning
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
            try await manager.reset()
            try await manager.appendAudio(
                Self.pcmBuffer(from: audio.samples, sampleRate: DictationAudio.transcriptionSampleRate)
            )
            return try await manager.finish()
        }
        transcriptionTask = (generation, task)
        return try await task.value
    }

    func prepare() async {
        _ = try? await loadManager()
    }

    func cancelTranscription() async {
        await cancelStreamingSession()
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

    func beginStreamingSession() async -> (@Sendable ([Float], Double) -> Void)? {
        guard activeTranscriptionGeneration == nil else { return nil }
        if streamingSession != nil {
            await cancelStreamingSession()
        }
        guard let manager else {
            Task { await self.prepare() }
            return nil
        }
        do {
            try await manager.reset()
        } catch {
            return nil
        }

        let (stream, continuation) = AsyncStream<(samples: [Float], sampleRate: Double)>.makeStream()
        let id = UUID()
        streamingSessionError = nil
        let consumeTask = Task { [weak self] in
            for await chunk in stream {
                await self?.consumeStreamChunk(chunk.samples, sampleRate: chunk.sampleRate, sessionID: id)
            }
        }
        streamingSession = StreamingSession(id: id, continuation: continuation, consumeTask: consumeTask)
        return { samples, sampleRate in
            continuation.yield((samples, sampleRate))
        }
    }

    private func consumeStreamChunk(_ samples: [Float], sampleRate: Double, sessionID: UUID) async {
        guard streamingSession?.id == sessionID, streamingSessionError == nil, let manager else { return }
        do {
            let buffer = try Self.pcmBuffer(from: samples, sampleRate: sampleRate)
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        } catch {
            // The windower marks audio consumed before decoding it, so a failed
            // chunk is unrecoverable mid-stream: a transcript finished past it
            // would silently omit that audio. Poison the session instead so
            // finish throws and the controller batch-transcribes the full take.
            if streamingSession?.id == sessionID {
                streamingSessionError = error
            }
        }
    }

    func finishStreamingSession() async throws -> String {
        guard let session = streamingSession else {
            throw ParakeetDictationError.streamingSessionUnavailable
        }
        // Drain queued chunks before the session guard in consumeStreamChunk
        // goes nil, or the utterance tail never reaches the model.
        session.continuation.finish()
        await session.consumeTask.value
        guard streamingSession?.id == session.id else {
            throw ParakeetDictationError.streamingSessionUnavailable
        }
        streamingSession = nil
        if let error = streamingSessionError {
            streamingSessionError = nil
            try? await manager?.reset()
            throw error
        }
        guard let manager else {
            throw ParakeetDictationError.streamingSessionUnavailable
        }
        return try await manager.finish()
    }

    func cancelStreamingSession() async {
        guard let session = streamingSession else { return }
        streamingSession = nil
        streamingSessionError = nil
        session.continuation.finish()
        session.consumeTask.cancel()
        _ = await session.consumeTask.value
        // A replacement session can begin while the consume task drains; it has
        // already reset the manager itself, and resetting again here would wipe
        // the audio prefix it has appended since.
        if streamingSession == nil {
            try? await manager?.reset()
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

    private func loadManager() async throws -> StreamingUnifiedAsrManager {
        if let manager { return manager }
        if let loadTask { return try await loadTask.task.value }

        loadGeneration &+= 1
        let generation = loadGeneration
        let task = Task<StreamingUnifiedAsrManager, Error> {
            let modelFolder = try await Self.resolvePinnedModelFolder(
                allowDownload: DictationModelRequest.transcription.allowsDownload
            )
            let manager = StreamingUnifiedAsrManager(encoderPrecision: .int8)
            try await manager.loadModels(from: modelFolder)
            return manager
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

    private static let repository = "FluidInference/parakeet-unified-en-0.6b-coreml"
    private static let revision = "4252711f6f060f9a2f91e5f081a806d7f45eebd8"
    private static let cachedModelFolderKey =
        "gojo.dictation.modelFolder.parakeet-unified-en-0.6b.\(revision).streaming"
    private static let maximumModelBytes: UInt64 = 609_439_216

    private static let downloadPatterns = [
        "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/*",
        "parakeet_unified_decoder.mlmodelc/*",
        "parakeet_unified_joint_decision_single_step.mlmodelc/*",
        "vocab.json",
        "metadata.json",
    ]

    private static let modelSHA256: [String: String] = [
        "metadata.json": "2b26a96b76fe1f7a04d3e867f50c75d6ce5dd1650d0dbcd4c35b591b22305f0e",
        "parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin": "9ae70f6559989f88b856b326e59315798f9f0d08207a19fcc2dd3287a30088a5",
        "parakeet_unified_decoder.mlmodelc/coremldata.bin": "ce99c4488840fc463d59f8d4d6d2a9e8ceae8138ead51e3c265dde4d2ba4a0e9",
        "parakeet_unified_decoder.mlmodelc/model.mil": "6e60965b89c93943aa2be2d991c2461108145851fde05e1d048223a32d4cb20d",
        "parakeet_unified_decoder.mlmodelc/weights/weight.bin": "96f990461a5986d5e7309ad1a0f36084fbf0f4b28aec35948f8b8d0dcbf8599e",
        "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/analytics/coremldata.bin": "ffbbab2cbdc941dd88fc41c41d3f7ac61cc31475a17a1cb06ed7f3b0b25c611b",
        "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/coremldata.bin": "e1ffdae252dcc276ff2964ee2259a63d9c519b8413302609300d692f6a79b824",
        "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/model.mil": "64a4bdf20760025c8df072872b9aa71fdbce938f469c976fda690354424cc93c",
        "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc/weights/weight.bin": "259e5818cf4acee1155409a048ec408eecd8cfc27ade04ba18bca243398cc9b6",
        "parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin": "163877ad14af97ec4107cd854fd1c6d336ee5d40ad25a657cc764fb763f452f5",
        "parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin": "68a081570a48b52ec9379e153bd56748a5408a50be16767601563f231eaeff03",
        "parakeet_unified_joint_decision_single_step.mlmodelc/model.mil": "03c21096090bcd0b71c896c5ae0eb815db31a91c6676f572a7868eee4299abe3",
        "parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin": "06831afa6d1beb0c0b10350ebf7886bc37638e951d14e738d7e06fbd2a05012f",
        "vocab.json": "e1a7bff4f5df133c0f4ad47b8e43c96f6bf1865d99126a4c4725ef51d0108bec",
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
        guard let folder = DictationModelStorage.hubRepositoryRoot(repository),
              DictationModelStorage.storedPath(
                  UserDefaults.standard.string(forKey: cachedModelFolderKey),
                  matches: folder
              ) else {
            clearCachedModelFolder()
            throw WhisperKitDictationError.modelRemovalFailed
        }
        let topLevelItems = [
            "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc",
            "parakeet_unified_encoder_int8.mlmodelc",
            "parakeet_unified_decoder.mlmodelc",
            "parakeet_unified_joint_decision_single_step.mlmodelc",
            "vocab.json",
            "metadata.json",
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
                // Reclaims disk space from the pre-streaming offline encoder,
                // which the streaming model no longer needs.
                try? FileManager.default.removeItem(
                    at: cachedURL.appendingPathComponent("parakeet_unified_encoder_int8.mlmodelc")
                )
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
        try? FileManager.default.removeItem(
            at: snapshot.appendingPathComponent("parakeet_unified_encoder_int8.mlmodelc")
        )
        UserDefaults.standard.set(snapshot.path, forKey: cachedModelFolderKey)
        return snapshot
    }

    private static func validateModel(at folder: URL) throws -> Bool {
        var totalBytes: UInt64 = 0
        for (relativePath, expectedHash) in modelSHA256 {
            let fileURL = folder.appendingPathComponent(relativePath)
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw ParakeetDictationError.integrityFailed(relativePath)
            }
            totalBytes += UInt64(fileSize)
            guard totalBytes <= maximumModelBytes,
                  try sha256(of: fileURL) == expectedHash else {
                throw ParakeetDictationError.integrityFailed(relativePath)
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

    private static func pcmBuffer(from samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw ParakeetDictationError.invalidSampleRate(sampleRate)
        }
        buffer.frameLength = buffer.frameCapacity
        if let destination = buffer.floatChannelData?[0], !samples.isEmpty {
            samples.withUnsafeBufferPointer { source in
                destination.update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}

enum ParakeetDictationError: LocalizedError {
    case integrityFailed(String)
    case invalidSampleRate(Double)
    case transcriptionAlreadyRunning
    case streamingSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .integrityFailed(let path):
            return "The Parakeet model failed its integrity check (\(path))."
        case .invalidSampleRate(let sampleRate):
            return "The local speech model expected 16 kHz audio but received \(Int(sampleRate)) Hz."
        case .transcriptionAlreadyRunning:
            return "A local transcription is already running."
        case .streamingSessionUnavailable:
            return "No live transcription session is active."
        }
    }
}
