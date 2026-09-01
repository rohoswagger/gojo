import Foundation
import Security

// MARK: - Dictation preferences

enum DictationProvider: String, CaseIterable, Identifiable, Sendable {
    case local
    case openRouter

    static let defaultsKey = "gojo.dictation.provider"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local"
        case .openRouter: return "OpenRouter"
        }
    }

    var prompt: String {
        switch self {
        case .local: return "Transcribe privately on this Mac using an installed voice model."
        case .openRouter: return "Send audio to OpenRouter for cloud transcription."
        }
    }
}

enum DictationOpenRouterSettings {
    static let modelDefaultsKey = "gojo.dictation.openRouterModel"
    static let cleanupModelDefaultsKey = "gojo.dictation.cleanupModel"
    static let polishingEnabledDefaultsKey = "gojo.dictation.polishingEnabled"
    static let customInstructionsDefaultsKey = "gojo.dictation.customInstructions"
    static let defaultTranscriptionModel = "soniox/stt-rt-v5"
    static let fallbackTranscriptionModel = "deepgram/nova-3"
    static let defaultCleanupModel = "openai/gpt-oss-20b"
}

// MARK: - Keychain

enum DictationKeychainError: LocalizedError, Sendable {
    case invalidKey
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Enter a valid OpenRouter API key."
        case .operationFailed: return "Gojo could not access its secure API-key storage."
        }
    }
}

enum DictationKeychain {
    private static let service = "rohoswagger.gojo.dictation"
    private static let account = "openrouter-api-key"

    static func save(_ key: String) throws {
        try saveOpenRouterAPIKey(key)
    }

    static func load() throws -> String? {
        try loadOpenRouterAPIKey()
    }

    static func delete() throws {
        try deleteOpenRouterAPIKey()
    }

    static func saveOpenRouterAPIKey(_ key: String) throws {
        guard !key.isEmpty, let value = key.data(using: .utf8) else {
            throw DictationKeychainError.invalidKey
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: value,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw DictationKeychainError.operationFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData] = value
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw DictationKeychainError.operationFailed(addStatus)
        }
    }

    static func loadOpenRouterAPIKey() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw DictationKeychainError.operationFailed(status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func deleteOpenRouterAPIKey() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DictationKeychainError.operationFailed(status)
        }
    }
}

// MARK: - Deterministic WAV encoding

enum DictationWAVEncoderError: LocalizedError, Sendable {
    case invalidSampleRate
    case oversizedAudio

    var errorDescription: String? {
        switch self {
        case .invalidSampleRate: return "Dictation audio must be 16 kHz mono audio."
        case .oversizedAudio: return "The dictation recording is too large to send."
        }
    }
}

enum DictationWAVEncoder {
    static let sampleRate: UInt32 = 16_000
    static let channels: UInt16 = 1
    static let bitsPerSample: UInt16 = 16

    static func encode(_ audio: DictationAudio) throws -> Data {
        guard abs(audio.sampleRate - Double(sampleRate)) < 0.5 else {
            throw DictationWAVEncoderError.invalidSampleRate
        }
        guard audio.samples.count <= (Int(UInt32.max) - 44) / 2 else {
            throw DictationWAVEncoderError.oversizedAudio
        }

        let dataSize = UInt32(audio.samples.count * 2)
        let riffSize = UInt32(36) + dataSize
        var wav = Data(capacity: Int(dataSize) + 44)
        appendASCII("RIFF", to: &wav)
        appendUInt32LE(riffSize, to: &wav)
        appendASCII("WAVE", to: &wav)
        appendASCII("fmt ", to: &wav)
        appendUInt32LE(16, to: &wav) // PCM fmt chunk size
        appendUInt16LE(1, to: &wav) // PCM format
        appendUInt16LE(channels, to: &wav)
        appendUInt32LE(sampleRate, to: &wav)
        appendUInt32LE(sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8), to: &wav)
        appendUInt16LE(channels * (bitsPerSample / 8), to: &wav)
        appendUInt16LE(bitsPerSample, to: &wav)
        appendASCII("data", to: &wav)
        appendUInt32LE(dataSize, to: &wav)

        for sample in audio.samples {
            let value: Int16
            if sample.isNaN || sample <= -1 {
                value = Int16.min
            } else if sample >= 1 {
                value = Int16.max
            } else {
                value = Int16((sample * Float(Int16.max)).rounded(.toNearestOrAwayFromZero))
            }
            appendUInt16LE(UInt16(bitPattern: value), to: &wav)
        }
        return wav
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}

extension DictationAudio {
    func pcm16WAVData() throws -> Data {
        try DictationWAVEncoder.encode(self)
    }
}

// MARK: - OpenRouter wire types and client

struct OpenRouterTranscriptionModel: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String?
    let architecture: Architecture?

    struct Architecture: Codable, Equatable, Sendable {
        let outputModalities: [String]?
        let modality: String?

        enum CodingKeys: String, CodingKey {
            case outputModalities = "output_modalities"
            case modality
        }
    }

    var supportsTranscription: Bool {
        architecture?.outputModalities?.contains {
            $0.caseInsensitiveCompare("transcription") == .orderedSame
        } ?? architecture?.modality?.localizedCaseInsensitiveContains("transcription") ?? false
    }

    var displayName: String {
        guard let name, !name.isEmpty else { return id }
        return name
    }
}

struct OpenRouterMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

struct OpenRouterTranscriptionRequest: Encodable, Equatable, Sendable {
    let model: String
    let inputAudio: InputAudio
    let language: String?
    let temperature: Double?

    struct InputAudio: Encodable, Equatable, Sendable {
        let data: String
        let format: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case inputAudio = "input_audio"
        case language
        case temperature
    }
}

struct OpenRouterChatRequest: Encodable, Equatable, Sendable {
    let model: String
    let messages: [OpenRouterMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let provider: Provider?

    struct Provider: Encodable, Equatable, Sendable {
        let sort: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, provider
        case maxTokens = "max_tokens"
    }
}

enum OpenRouterDictationError: LocalizedError, Sendable {
    case missingAPIKey
    case unauthorized
    case paymentRequired
    case rateLimited
    case serverUnavailable
    case requestFailed
    case invalidResponse
    case unsupportedModel
    case emptyResponse
    case truncatedResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add an OpenRouter API key in Dictation settings."
        case .unauthorized: return "OpenRouter rejected the API key. Check it and try again."
        case .paymentRequired: return "OpenRouter needs available credits to transcribe this recording."
        case .rateLimited: return "OpenRouter is busy. Wait a moment and try again."
        case .serverUnavailable: return "OpenRouter is temporarily unavailable. Try again shortly."
        case .requestFailed: return "OpenRouter could not process the dictation request."
        case .invalidResponse: return "OpenRouter returned an invalid dictation response."
        case .unsupportedModel: return "No supported OpenRouter transcription model is available."
        case .emptyResponse: return "OpenRouter returned an empty dictation response."
        case .truncatedResponse: return "OpenRouter could not safely finish polishing this transcript."
        }
    }
}

protocol OpenRouterDictationClient: Sendable {
    func listTranscriptionModels(apiKey: String?) async throws -> [OpenRouterTranscriptionModel]
    func transcribe(audio: Data, model: String, apiKey: String, language: String?) async throws -> String
    func chatCompletion(
        model: String,
        apiKey: String,
        messages: [OpenRouterMessage],
        temperature: Double,
        maxTokens: Int,
        sort: String
    ) async throws -> String
}

actor OpenRouterAPIClient: OpenRouterDictationClient {
    let session: URLSession
    let baseURL: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listTranscriptionModels(apiKey: String? = nil) async throws -> [OpenRouterTranscriptionModel] {
        var components = URLComponents(url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "output_modalities", value: "transcription")]
        guard let url = components?.url else { throw OpenRouterDictationError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addHeaders(to: &request, apiKey: apiKey, contentType: nil)
        let (data, response) = try await send(request)
        try validate(response)
        let envelope: ModelEnvelope
        do {
            envelope = try decoder.decode(ModelEnvelope.self, from: data)
        } catch {
            throw OpenRouterDictationError.invalidResponse
        }
        let models = envelope.data.filter(\.supportsTranscription)
        guard !models.isEmpty else { throw OpenRouterDictationError.unsupportedModel }
        return models
    }

    func transcribe(audio: Data, model: String, apiKey: String, language: String? = nil) async throws -> String {
        try Task.checkCancellation()
        let requestBody = OpenRouterTranscriptionRequest(
            model: model,
            inputAudio: .init(data: audio.base64EncodedString(), format: "wav"),
            language: language,
            temperature: 0
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(requestBody)
        addHeaders(to: &request, apiKey: apiKey, contentType: "application/json")
        let (data, response) = try await send(request)
        try validate(response)
        try Task.checkCancellation()
        let result: TranscriptionResponse
        do {
            result = try decoder.decode(TranscriptionResponse.self, from: data)
        } catch {
            throw OpenRouterDictationError.invalidResponse
        }
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterDictationError.emptyResponse
        }
        return result.text
    }

    func chatCompletion(
        model: String,
        apiKey: String,
        messages: [OpenRouterMessage],
        temperature: Double,
        maxTokens: Int,
        sort: String = "latency"
    ) async throws -> String {
        try Task.checkCancellation()
        let requestBody = OpenRouterChatRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false,
            provider: .init(sort: sort)
        )
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(requestBody)
        addHeaders(to: &request, apiKey: apiKey, contentType: "application/json")
        let (data, response) = try await send(request)
        try validate(response)
        try Task.checkCancellation()
        let result: ChatResponse
        do {
            result = try decoder.decode(ChatResponse.self, from: data)
        } catch {
            throw OpenRouterDictationError.invalidResponse
        }
        guard let choice = result.choices.first else {
            throw OpenRouterDictationError.invalidResponse
        }
        if choice.finishReason == "length" {
            throw OpenRouterDictationError.truncatedResponse
        }
        guard let content = choice.message.content else {
            throw OpenRouterDictationError.invalidResponse
        }
        return content
    }

    private func addHeaders(to request: inout URLRequest, apiKey: String?, contentType: String?) {
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterDictationError.invalidResponse
            }
            return (data, httpResponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenRouterDictationError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw OpenRouterDictationError.requestFailed
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300: return
        case 401, 403: throw OpenRouterDictationError.unauthorized
        case 402: throw OpenRouterDictationError.paymentRequired
        case 429: throw OpenRouterDictationError.rateLimited
        case 500 ... 599: throw OpenRouterDictationError.serverUnavailable
        default: throw OpenRouterDictationError.requestFailed
        }
    }

    private struct ModelEnvelope: Decodable {
        let data: [OpenRouterTranscriptionModel]
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct Message: Decodable {
            let content: String?
        }
    }
}

// MARK: - Model selection and transcription adapter

enum OpenRouterDictationModelSelection {
    static func select(
        preferredModel: String?,
        from models: [OpenRouterTranscriptionModel]
    ) -> String? {
        let ids = models.filter(\.supportsTranscription).map(\.id)
        guard !ids.isEmpty else { return nil }
        if let preferredModel, ids.contains(preferredModel) {
            return preferredModel
        }
        if ids.contains(DictationOpenRouterSettings.defaultTranscriptionModel) {
            return DictationOpenRouterSettings.defaultTranscriptionModel
        }
        if ids.contains(DictationOpenRouterSettings.fallbackTranscriptionModel) {
            return DictationOpenRouterSettings.fallbackTranscriptionModel
        }
        return ids.first
    }
}

actor OpenRouterDictationTranscriber: LocalDictationTranscribing {
    private let client: OpenRouterDictationClient
    private let apiKeyProvider: @Sendable () -> String?
    private let modelProvider: @Sendable () -> String?
    private let languageProvider: @Sendable () -> String?
    private var transcriptionTask: Task<String, Error>?
    private var transcriptionID: UUID?

    init(
        client: OpenRouterDictationClient = OpenRouterAPIClient(),
        apiKeyProvider: @escaping @Sendable () -> String? = {
            try? DictationKeychain.loadOpenRouterAPIKey()
        },
        modelProvider: @escaping @Sendable () -> String? = {
            UserDefaults.standard.string(forKey: DictationOpenRouterSettings.modelDefaultsKey)
        },
        languageProvider: @escaping @Sendable () -> String? = { nil }
    ) {
        self.client = client
        self.apiKeyProvider = apiKeyProvider
        self.modelProvider = modelProvider
        self.languageProvider = languageProvider
    }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        transcriptionTask?.cancel()
        let client = self.client
        let apiKeyProvider = self.apiKeyProvider
        let modelProvider = self.modelProvider
        let languageProvider = self.languageProvider
        let requestID = UUID()
        let task = Task<String, Error> {
            try Task.checkCancellation()
            guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                throw OpenRouterDictationError.missingAPIKey
            }
            let wav = try DictationWAVEncoder.encode(audio)
            guard let model = modelProvider(), !model.isEmpty else {
                throw OpenRouterDictationError.unsupportedModel
            }
            return try await client.transcribe(
                audio: wav,
                model: model,
                apiKey: apiKey,
                language: languageProvider()
            )
        }
        transcriptionTask = task
        transcriptionID = requestID
        defer {
            if transcriptionID == requestID {
                transcriptionTask = nil
                transcriptionID = nil
            }
        }
        return try await task.value
    }

    func cancelTranscription() async {
        let task = transcriptionTask
        let requestID = transcriptionID
        task?.cancel()
        if let task {
            _ = await task.result
        }
        if transcriptionID == requestID {
            transcriptionTask = nil
            transcriptionID = nil
        }
    }
}

// MARK: - LLM polishing adapter

actor OpenRouterDictationPolisher: DictationTextPolishing {
    private let client: OpenRouterDictationClient
    private let apiKeyProvider: @Sendable () -> String?
    private let styleProvider: @Sendable () -> DictationWritingStyle
    private let customInstructionsProvider: @Sendable () -> String?
    private let modelProvider: @Sendable () -> String
    private let enabledProvider: @Sendable () -> Bool
    private var polishingTask: Task<String, Error>?
    private var polishingID: UUID?

    init(
        client: OpenRouterDictationClient = OpenRouterAPIClient(),
        apiKeyProvider: @escaping @Sendable () -> String? = {
            try? DictationKeychain.loadOpenRouterAPIKey()
        },
        styleProvider: @escaping @Sendable () -> DictationWritingStyle = {
            DictationWritingStyle(rawValue: UserDefaults.standard.string(
                forKey: DictationWritingStyle.defaultsKey
            ) ?? "") ?? .punctuated
        },
        customInstructionsProvider: @escaping @Sendable () -> String? = {
            UserDefaults.standard.string(forKey: DictationOpenRouterSettings.customInstructionsDefaultsKey)
        },
        modelProvider: @escaping @Sendable () -> String = {
            UserDefaults.standard.string(forKey: DictationOpenRouterSettings.cleanupModelDefaultsKey)
                ?? DictationOpenRouterSettings.defaultCleanupModel
        },
        enabledProvider: @escaping @Sendable () -> Bool = {
            let provider = DictationProvider(
                rawValue: UserDefaults.standard.string(forKey: DictationProvider.defaultsKey) ?? ""
            ) ?? .local
            let enabled = UserDefaults.standard.object(
                forKey: DictationOpenRouterSettings.polishingEnabledDefaultsKey
            ) as? Bool ?? false
            return provider == .openRouter && enabled
        }
    ) {
        self.client = client
        self.apiKeyProvider = apiKeyProvider
        self.styleProvider = styleProvider
        self.customInstructionsProvider = customInstructionsProvider
        self.modelProvider = modelProvider
        self.enabledProvider = enabledProvider
    }

    func polish(_ transcript: String) async throws -> String {
        guard enabledProvider(), !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript
        }
        polishingTask?.cancel()
        let client = self.client
        let apiKeyProvider = self.apiKeyProvider
        let styleProvider = self.styleProvider
        let customInstructionsProvider = self.customInstructionsProvider
        let modelProvider = self.modelProvider
        let requestID = UUID()
        let task = Task<String, Error> {
            try Task.checkCancellation()
            guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
                throw OpenRouterDictationError.missingAPIKey
            }
            let style = styleProvider()
            let systemPrompt = Self.systemPrompt(style: style, customInstructions: customInstructionsProvider())
            let result = try await client.chatCompletion(
                model: modelProvider(),
                apiKey: apiKey,
                messages: [
                    OpenRouterMessage(role: "system", content: systemPrompt),
                    OpenRouterMessage(role: "user", content: transcript),
                ],
                temperature: 0,
                maxTokens: Self.outputTokenBudget(for: transcript),
                sort: "latency"
            )
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OpenRouterDictationError.emptyResponse
            }
            return result
        }
        polishingTask = task
        polishingID = requestID
        defer {
            if polishingID == requestID {
                polishingTask = nil
                polishingID = nil
            }
        }
        return try await task.value
    }

    func cancelPolishing() async {
        let task = polishingTask
        let requestID = polishingID
        task?.cancel()
        if let task {
            _ = await task.result
        }
        if polishingID == requestID {
            polishingTask = nil
            polishingID = nil
        }
    }

    static func systemPrompt(style: DictationWritingStyle, customInstructions: String?) -> String {
        var prompt = """
        You are Gojo's dictation editor. Return only the edited text, with no explanation, quotation marks, or preamble.
        Preserve the speaker's meaning, facts, names, numbers, URLs, code, and ordering. Remove only obvious filler words, false starts, and accidental repetition. Never invent details, summarize, answer questions, or turn a request into an answer.
        Style: \(style.label). \(style.prompt)
        """
        if let customInstructions {
            let trimmed = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                prompt += "\nAdditional style instructions from the user: \(trimmed)"
            }
        }
        return prompt
    }

    static func outputTokenBudget(for transcript: String) -> Int {
        min(4_096, max(1_024, transcript.utf8.count))
    }
}
