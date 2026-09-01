import CryptoKit
import Foundation
import llama

enum S1MiniModelOperation: Equatable, Sendable {
    case installing
    case removing
}

enum S1MiniPolisherError: LocalizedError {
    case storageUnavailable
    case unsafeStorage
    case downloadFailed
    case invalidDownload
    case modelLoadFailed
    case contextCreationFailed
    case inputTooLong
    case inferenceFailed

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            return "Gojo could not open its cleanup-model folder."
        case .unsafeStorage:
            return "Gojo refused to use an unsafe cleanup-model path."
        case .downloadFailed:
            return "The S1-mini download failed. Check your connection and try again."
        case .invalidDownload:
            return "The downloaded S1-mini file failed its integrity check."
        case .modelLoadFailed:
            return "Gojo could not load S1-mini. Try removing and downloading it again."
        case .contextCreationFailed:
            return "Gojo could not prepare enough memory for transcript cleanup."
        case .inputTooLong:
            return "This transcript is too long for local cleanup."
        case .inferenceFailed:
            return "S1-mini could not clean this transcript."
        }
    }
}

private actor S1MiniModelStore {
    private var cachedInstalled: Bool?

    func modelURL() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw S1MiniPolisherError.storageUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Gojo", isDirectory: true)
            .appendingPathComponent("DictationCleanup", isDirectory: true)
            .appendingPathComponent(S1MiniModel.fileName, isDirectory: false)
    }

    func isInstalled() async -> Bool {
        if let cachedInstalled { return cachedInstalled }
        guard let url = try? modelURL() else {
            cachedInstalled = false
            return false
        }
        let installed = (try? validateModel(at: url)) == true
        cachedInstalled = installed
        return installed
    }

    func install() async throws {
        if await isInstalled() { return }
        let destination = try modelURL()
        let root = destination.deletingLastPathComponent()
        try prepareStorageRoot(root)
        try validateReplaceableModelNodeIfPresent(at: destination)

        let (temporaryDownload, response): (URL, URLResponse)
        do {
            (temporaryDownload, response) = try await URLSession.shared.download(
                from: S1MiniModel.downloadURL
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw S1MiniPolisherError.downloadFailed
        }
        defer { try? FileManager.default.removeItem(at: temporaryDownload) }

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw S1MiniPolisherError.downloadFailed
        }
        guard try validateModel(at: temporaryDownload) else {
            throw S1MiniPolisherError.invalidDownload
        }
        try Task.checkCancellation()

        let staging = root.appendingPathComponent(
            ".\(S1MiniModel.fileName).\(UUID().uuidString).partial",
            isDirectory: false
        )
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: temporaryDownload, to: staging)
        try Task.checkCancellation()

        try removeModelFileIfPresent(at: destination)
        try FileManager.default.moveItem(at: staging, to: destination)
        cachedInstalled = true
    }

    func remove() throws {
        let destination = try modelURL()
        let root = destination.deletingLastPathComponent()
        try validateStorageRootIfPresent(root)
        guard destination.path == root
            .appendingPathComponent(S1MiniModel.fileName, isDirectory: false)
            .standardizedFileURL.path else {
            throw S1MiniPolisherError.unsafeStorage
        }

        try removeModelFileIfPresent(at: destination)
        cachedInstalled = false
    }

    private func prepareStorageRoot(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try validateStorageRootIfPresent(root)
    }

    private func validateStorageRootIfPresent(_ root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) == nil,
              root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw S1MiniPolisherError.unsafeStorage
        }
    }

    private func removeModelFileIfPresent(at url: URL) throws {
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            try fileManager.removeItem(at: url)
            return
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        guard !isDirectory.boolValue,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw S1MiniPolisherError.unsafeStorage
        }
        try fileManager.removeItem(at: url)
    }

    private func validateReplaceableModelNodeIfPresent(at url: URL) throws {
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil { return }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        guard !isDirectory.boolValue,
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw S1MiniPolisherError.unsafeStorage
        }
    }

    private func validateModel(at url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              values.fileSize == S1MiniModel.downloadSize else {
            return false
        }
        return try sha256(of: url) == S1MiniModel.sha256
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private actor S1MiniLlamaRuntime {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var loadedPath: String?
    private var backendInitialized = false

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        if backendInitialized { llama_backend_free() }
    }

    func prepare(modelURL: URL) throws {
        if loadedPath == modelURL.path, model != nil, context != nil { return }
        unload()
        if !backendInitialized {
            llama_backend_init()
            backendInitialized = true
        }

        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 99
        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParameters) else {
            throw S1MiniPolisherError.modelLoadFailed
        }

        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = 2_048
        contextParameters.n_batch = 2_048
        contextParameters.n_ubatch = 512
        let threads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
        contextParameters.n_threads = Int32(threads)
        contextParameters.n_threads_batch = Int32(threads)
        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw S1MiniPolisherError.contextCreationFailed
        }

        model = loadedModel
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)
        loadedPath = modelURL.path
    }

    func unload() {
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
        vocab = nil
        loadedPath = nil
    }

    func polish(_ transcript: String, style: DictationWritingStyle, modelURL: URL) throws -> String {
        try Task.checkCancellation()
        try prepare(modelURL: modelURL)
        guard let context, let vocab else { throw S1MiniPolisherError.modelLoadFailed }

        let prompt = S1MiniModel.prompt(transcript: transcript, style: style)
        let tokens = try tokenize(prompt, vocab: vocab)
        let maximumOutputTokens = min(512, max(96, transcript.utf8.count / 2))
        guard !tokens.isEmpty, tokens.count + maximumOutputTokens <= 2_048 else {
            throw S1MiniPolisherError.inputTooLong
        }

        llama_memory_clear(llama_get_memory(context), true)
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = Int32(tokens.count)
        for (index, token) in tokens.enumerated() {
            batch.token[index] = token
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]?[0] = 0
            batch.logits[index] = 0
        }
        batch.logits[tokens.count - 1] = 1
        guard llama_decode(context, batch) == 0 else {
            throw S1MiniPolisherError.inferenceFailed
        }

        guard let sampler = llama_sampler_init_greedy() else {
            throw S1MiniPolisherError.inferenceFailed
        }
        defer { llama_sampler_free(sampler) }

        var output = ""
        var utf8Buffer: [CChar] = []
        var position = Int32(tokens.count)
        var reachedEndToken = false
        for _ in 0..<maximumOutputTokens {
            try Task.checkCancellation()
            let token = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
            llama_sampler_accept(sampler, token)
            if llama_vocab_is_eog(vocab, token) {
                reachedEndToken = true
                break
            }
            output += tokenPiece(token, vocab: vocab, buffer: &utf8Buffer)

            batch.n_tokens = 1
            batch.token[0] = token
            batch.pos[0] = position
            batch.n_seq_id[0] = 1
            batch.seq_id[0]?[0] = 0
            batch.logits[0] = 1
            guard llama_decode(context, batch) == 0 else {
                throw S1MiniPolisherError.inferenceFailed
            }
            position += 1
        }
        guard reachedEndToken else {
            // Never surface a prefix that only looks valid because generation
            // exhausted its budget before the model emitted an end token.
            throw S1MiniPolisherError.inferenceFailed
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let capacity = max(32, text.utf8.count + 8)
        var tokens = [llama_token](repeating: 0, count: capacity)
        let count = llama_tokenize(
            vocab,
            text,
            Int32(text.utf8.count),
            &tokens,
            Int32(tokens.count),
            llama_vocab_get_add_bos(vocab),
            true
        )
        guard count >= 0 else { throw S1MiniPolisherError.inputTooLong }
        return Array(tokens.prefix(Int(count)))
    }

    private func tokenPiece(
        _ token: llama_token,
        vocab: OpaquePointer,
        buffer: inout [CChar]
    ) -> String {
        var bytes = [CChar](repeating: 0, count: 16)
        var count = llama_token_to_piece(vocab, token, &bytes, Int32(bytes.count), 0, false)
        if count < 0 {
            bytes = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &bytes, Int32(bytes.count), 0, false)
        }
        guard count > 0 else { return "" }
        buffer.append(contentsOf: bytes.prefix(Int(count)))
        let data = Data(buffer.map { UInt8(bitPattern: $0) })
        guard let string = String(data: data, encoding: .utf8) else {
            if buffer.count >= 4 { buffer.removeAll(keepingCapacity: true) }
            return ""
        }
        buffer.removeAll(keepingCapacity: true)
        return string
    }
}

actor S1MiniDictationPolisher: DictationTextPolishing {
    private let store = S1MiniModelStore()
    private let runtime = S1MiniLlamaRuntime()
    private let enabledProvider: @Sendable () -> Bool
    private let styleProvider: @Sendable () -> DictationWritingStyle
    private let vocabularyProvider: @Sendable () -> [DictationVocabularyEntry]
    private var polishingTask: Task<String, Error>?

    init(
        enabledProvider: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: DictationOpenRouterSettings.polishingEnabledDefaultsKey)
        },
        styleProvider: @escaping @Sendable () -> DictationWritingStyle = {
            DictationWritingStyle(rawValue: UserDefaults.standard.string(
                forKey: DictationWritingStyle.defaultsKey
            ) ?? "") ?? .punctuated
        },
        vocabularyProvider: @escaping @Sendable () -> [DictationVocabularyEntry] = {
            guard let data = UserDefaults.standard.data(forKey: DictationVocabularyPolicy.defaultsKey),
                  let entries = try? JSONDecoder().decode([DictationVocabularyEntry].self, from: data) else {
                return []
            }
            return DictationVocabularyPolicy.sanitized(entries)
        }
    ) {
        self.enabledProvider = enabledProvider
        self.styleProvider = styleProvider
        self.vocabularyProvider = vocabularyProvider
    }

    func polish(_ transcript: String) async throws -> String {
        let vocabulary = vocabularyProvider()
        let correctedRaw = S1MiniVocabularyPipeline.prepare(
            transcript: transcript,
            vocabulary: vocabulary
        )
        guard enabledProvider(), await store.isInstalled() else { return correctedRaw }

        let style = styleProvider()
        let modelURL = try await store.modelURL()
        let task = Task<String, Error> { [runtime] in
            try await runtime.polish(correctedRaw, style: style, modelURL: modelURL)
        }
        polishingTask = task
        defer { polishingTask = nil }
        do {
            let polished = try await task.value
            let finalized = S1MiniVocabularyPipeline.finalize(
                correctedRawTranscript: correctedRaw,
                polishedTranscript: polished,
                vocabulary: vocabulary
            )
            return style.applyOutputConventions(to: finalized)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return correctedRaw
        }
    }

    func cancelPolishing() async {
        let task = polishingTask
        task?.cancel()
        if let task { _ = await task.result }
        polishingTask = nil
    }

    func isModelInstalled() async -> Bool {
        await store.isInstalled()
    }

    func installModel() async throws {
        try await store.install()
    }

    func removeModel() async throws {
        await cancelPolishing()
        await runtime.unload()
        try await store.remove()
    }

    func prepareIfInstalled() async {
        guard await store.isInstalled(), let url = try? await store.modelURL() else { return }
        try? await runtime.prepare(modelURL: url)
    }
}
