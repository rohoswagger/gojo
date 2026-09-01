import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: @autoclosure () -> T, _ expected: T, _ message: String) {
    let actual = actual()
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

private func uint16LE(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func uint32LE(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private final class OpenRouterURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseStatus = 200
    private static var responseData = Data()
    private static var requests: [URLRequest] = []

    static func configure(status: Int, data: Data) {
        lock.lock()
        responseStatus = status
        responseData = data
        requests = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let status = Self.responseStatus
        let data = Self.responseData
        var capturedRequest = request
        if capturedRequest.httpBody == nil,
           let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            capturedRequest.httpBody = body
        }
        Self.requests.append(capturedRequest)
        Self.lock.unlock()

        guard let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor BlockingOpenRouterClient: OpenRouterDictationClient {
    enum Operation {
        case transcription
        case chat
    }

    private let operation: Operation
    private let chatResult: String
    private var transcriptionCalls = 0
    private var chatCalls = 0

    init(operation: Operation, chatResult: String = "polished") {
        self.operation = operation
        self.chatResult = chatResult
    }

    func listTranscriptionModels(apiKey: String?) async throws -> [OpenRouterTranscriptionModel] { [] }

    func transcribe(audio: Data, model: String, apiKey: String, language: String?) async throws -> String {
        transcriptionCalls += 1
        if operation == .transcription {
            try await Task.sleep(for: .seconds(10))
        }
        return "raw"
    }

    func chatCompletion(
        model: String,
        apiKey: String,
        messages: [OpenRouterMessage],
        temperature: Double,
        maxTokens: Int,
        sort: String
    ) async throws -> String {
        chatCalls += 1
        if operation == .chat {
            try await Task.sleep(for: .seconds(10))
        }
        return chatResult
    }

    func counts() -> (Int, Int) { (transcriptionCalls, chatCalls) }
}

private func model(_ id: String, transcription: Bool = true) -> OpenRouterTranscriptionModel {
    OpenRouterTranscriptionModel(
        id: id,
        name: id,
        architecture: .init(
            outputModalities: transcription ? ["transcription"] : ["text"],
            modality: transcription ? "audio->transcription" : "text->text"
        )
    )
}

private func expectError(
    _ expected: OpenRouterDictationError,
    operation: () async throws -> Void,
    message: String
) async {
    do {
        try await operation()
        assertCondition(false, "\(message): expected an error")
    } catch let actual as OpenRouterDictationError {
        switch (expected, actual) {
        case (.unauthorized, .unauthorized),
             (.paymentRequired, .paymentRequired),
             (.rateLimited, .rateLimited),
             (.serverUnavailable, .serverUnavailable),
             (.requestFailed, .requestFailed),
             (.invalidResponse, .invalidResponse),
             (.truncatedResponse, .truncatedResponse):
            return
        default:
            assertCondition(false, "\(message): unexpected error \(actual)")
        }
    } catch {
        assertCondition(false, "\(message): unexpected error \(error)")
    }
}

@main
struct OpenRouterDictationRegressionRunner {
    static func main() async {
        testWAVEncoding()
        testModelSelection()
        testStylePrompts()
        await testAPIClientWireContractAndResponses()
        await testAPIClientErrorMapping()
        await testAdaptersCancellationAndDisabledPolishing()
        print("openrouter-dictation-regression-pass")
    }

    static func testWAVEncoding() {
        let wav: Data
        do {
            wav = try DictationWAVEncoder.encode(
                DictationAudio(samples: [-1, -0.5, 0, 0.5, 1, .nan])
            )
        } catch {
            assertCondition(false, "WAV encoding should not throw: \(error)")
            return
        }

        assertEqual(wav.count, 56, "WAV should contain a 44-byte header plus six PCM16 samples")
        assertEqual(String(data: wav[0..<4], encoding: .ascii), "RIFF", "WAV should start with RIFF")
        assertEqual(uint32LE(wav, 4), 48, "RIFF size should exclude its leading tag and length")
        assertEqual(String(data: wav[8..<12], encoding: .ascii), "WAVE", "WAV should identify WAVE")
        assertEqual(String(data: wav[12..<16], encoding: .ascii), "fmt ", "WAV should include a format chunk")
        assertEqual(uint16LE(wav, 20), 1, "WAV should use PCM encoding")
        assertEqual(uint16LE(wav, 22), 1, "WAV should be mono")
        assertEqual(uint32LE(wav, 24), 16_000, "WAV should use the canonical 16 kHz sample rate")
        assertEqual(uint32LE(wav, 28), 32_000, "WAV byte rate should match 16 kHz mono PCM16")
        assertEqual(uint16LE(wav, 32), 2, "WAV block alignment should be one PCM16 sample")
        assertEqual(uint16LE(wav, 34), 16, "WAV should use 16-bit samples")
        assertEqual(String(data: wav[36..<40], encoding: .ascii), "data", "WAV should include a data chunk")
        assertEqual(uint32LE(wav, 40), 12, "WAV data length should match six PCM16 samples")
        assertEqual(
            Array(wav[44..<56]),
            [0x00, 0x80, 0x00, 0xc0, 0x00, 0x00, 0x00, 0x40, 0xff, 0x7f, 0x00, 0x80],
            "WAV samples should be deterministic little-endian PCM16, including clamping and NaN handling"
        )

        do {
            _ = try DictationWAVEncoder.encode(DictationAudio(samples: [0], sampleRate: 48_000))
            assertCondition(false, "WAV encoding should reject a non-16 kHz source")
        } catch DictationWAVEncoderError.invalidSampleRate {
            // Expected.
        } catch {
            assertCondition(false, "non-16 kHz source should return the sample-rate error")
        }
    }

    static func testModelSelection() {
        let soniox = DictationOpenRouterSettings.defaultTranscriptionModel
        let deepgram = DictationOpenRouterSettings.fallbackTranscriptionModel
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: "saved/model",
                from: [model("saved/model"), model(soniox), model(deepgram)]
            ),
            "saved/model",
            "a supported saved selection must not be replaced during refresh"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: nil,
                from: [model("other/model"), model(soniox), model(deepgram)]
            ),
            soniox,
            "Soniox should be the initial default only when the live catalog confirms it"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: "saved/model",
                from: [model("saved/model"), model(deepgram)]
            ),
            "saved/model",
            "a saved supported model should win when Soniox is absent"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: "saved/model",
                from: [model(soniox, transcription: false), model("saved/model")]
            ),
            "saved/model",
            "a catalog entry named Soniox must not win unless it advertises transcription support"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: "unsupported/model",
                from: [model("other/model"), model(deepgram)]
            ),
            deepgram,
            "Deepgram should be the fallback when preferred and Soniox are unavailable"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: nil,
                from: [model("first/model"), model("second/model")]
            ),
            "first/model",
            "the first compatible catalog model should be the final fallback"
        )
        assertEqual(
            OpenRouterDictationModelSelection.select(
                preferredModel: nil,
                from: [model("text-only", transcription: false)]
            ),
            nil,
            "non-transcription models must not be selected"
        )
    }

    static func testStylePrompts() {
        assertEqual(
            DictationWritingStyle.punctuated.label,
            "Conversational",
            "the spoken-English default should be called Conversational"
        )
        assertCondition(
            DictationWritingStyle.casual.prompt.contains("all lowercase"),
            "casual style should explicitly request lowercase text"
        )
        assertCondition(
            DictationWritingStyle.punctuated.prompt.contains("conversational"),
            "conversational style should explicitly preserve conversational English"
        )
        for style in DictationWritingStyle.allCases {
            let prompt = OpenRouterDictationPolisher.systemPrompt(
                style: style,
                customInstructions: "  Keep emoji use minimal.  "
            )
            assertCondition(
                prompt.contains("Return only the edited text, with no explanation, quotation marks, or preamble."),
                "\(style.label) should strictly request output-only text"
            )
            assertCondition(
                prompt.contains("Never invent details, summarize, answer questions, or turn a request into an answer."),
                "\(style.label) should prohibit meaning-changing edits"
            )
            assertCondition(
                prompt.contains("Style: \(style.label). \(style.prompt)"),
                "\(style.label) should include its exact style contract"
            )
            assertCondition(
                prompt.contains("Additional style instructions from the user: Keep emoji use minimal."),
                "\(style.label) should trim and include custom instructions"
            )
        }
    }

    static func testAPIClientWireContractAndResponses() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenRouterURLProtocol.self]
        let client = OpenRouterAPIClient(
            baseURL: URL(string: "https://unit.test/api/v1")!,
            session: URLSession(configuration: configuration)
        )
        let audio = Data([0, 1, 2, 3])

        OpenRouterURLProtocol.configure(status: 200, data: Data(#"{"text":"transcribed"}"#.utf8))
        do {
            let transcript = try await client.transcribe(
                audio: audio,
                model: "deepgram/nova-3",
                apiKey: "test-key",
                language: "en"
            )
            assertEqual(transcript, "transcribed", "a successful transcription response should decode text")
        } catch {
            assertCondition(false, "successful transcription should not throw: \(error)")
        }

        guard let transcriptionRequest = OpenRouterURLProtocol.capturedRequests().first else {
            assertCondition(false, "transcription request should be captured")
            return
        }
        assertEqual(transcriptionRequest.url?.path, "/api/v1/audio/transcriptions", "STT should use the dedicated endpoint")
        assertEqual(transcriptionRequest.httpMethod, "POST", "STT should post audio")
        assertEqual(transcriptionRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-key", "STT should use bearer auth")
        assertEqual(transcriptionRequest.value(forHTTPHeaderField: "Content-Type"), "application/json", "STT should send JSON")
        guard let transcriptionBody = transcriptionRequest.httpBody,
              let transcriptionJSON = try? JSONSerialization.jsonObject(with: transcriptionBody) as? [String: Any],
              let inputAudio = transcriptionJSON["input_audio"] as? [String: Any]
        else {
            assertCondition(false, "STT request should contain JSON input_audio")
            return
        }
        assertEqual(transcriptionJSON["model"] as? String, "deepgram/nova-3", "STT request should preserve the selected model")
        assertEqual(transcriptionJSON["language"] as? String, "en", "STT request should preserve the language hint")
        assertEqual(inputAudio["format"] as? String, "wav", "STT format must match the encoded WAV bytes")
        assertEqual(inputAudio["data"] as? String, audio.base64EncodedString(), "STT should send raw base64, never a data URI")
        assertCondition(
            !(inputAudio["data"] as? String ?? "").hasPrefix("data:"),
            "STT input_audio data must not be a data URI"
        )

        OpenRouterURLProtocol.configure(
            status: 201,
            data: Data(#"{"choices":[{"message":{"content":"polished"}}]}"#.utf8)
        )
        do {
            let result = try await client.chatCompletion(
                model: "openai/gpt-5-nano",
                apiKey: "test-key",
                messages: [OpenRouterMessage(role: "user", content: "raw")],
                temperature: 0,
                maxTokens: 128,
                sort: "latency"
            )
            assertEqual(result, "polished", "a successful chat response should decode content")
        } catch {
            assertCondition(false, "successful chat request should not throw: \(error)")
        }
        guard let chatRequest = OpenRouterURLProtocol.capturedRequests().first,
              let chatBody = chatRequest.httpBody,
              let chatJSON = try? JSONSerialization.jsonObject(with: chatBody) as? [String: Any],
              let provider = chatJSON["provider"] as? [String: Any]
        else {
            assertCondition(false, "chat request should be captured with provider routing")
            return
        }
        assertEqual(chatRequest.url?.path, "/api/v1/chat/completions", "polishing should use chat completions")
        assertEqual(provider["sort"] as? String, "latency", "polishing should ask OpenRouter for latency routing")
        assertEqual(chatJSON["stream"] as? Bool, false, "polishing should use a bounded non-streaming response")

        OpenRouterURLProtocol.configure(
            status: 200,
            data: Data(#"{"data":[{"id":"good","name":"Good","architecture":{"output_modalities":["transcription"]}},{"id":"bad","architecture":{"output_modalities":["text"]}}]}"#.utf8)
        )
        do {
            let models = try await client.listTranscriptionModels(apiKey: "test-key")
            assertEqual(models.map(\.id), ["good"], "model discovery should filter to transcription-capable entries")
        } catch {
            assertCondition(false, "successful model discovery should not throw: \(error)")
        }
        guard let modelRequest = OpenRouterURLProtocol.capturedRequests().first else {
            assertCondition(false, "model discovery request should be captured")
            return
        }
        let components = URLComponents(url: modelRequest.url!, resolvingAgainstBaseURL: false)
        assertEqual(modelRequest.httpMethod, "GET", "model discovery should be GET")
        assertEqual(
            components?.queryItems?.first(where: { $0.name == "output_modalities" })?.value,
            "transcription",
            "model discovery should request only STT models"
        )
    }

    static func testAPIClientErrorMapping() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OpenRouterURLProtocol.self]
        let client = OpenRouterAPIClient(
            baseURL: URL(string: "https://unit.test/api/v1")!,
            session: URLSession(configuration: configuration)
        )
        for (status, error) in [
            (401, OpenRouterDictationError.unauthorized),
            (402, .paymentRequired),
            (429, .rateLimited),
            (500, .serverUnavailable),
            (503, .serverUnavailable),
            (418, .requestFailed),
        ] {
            OpenRouterURLProtocol.configure(status: status, data: Data())
            await expectError(error, operation: {
                _ = try await client.transcribe(audio: Data(), model: "model", apiKey: "key", language: nil)
            }, message: "HTTP \(status) should map deterministically")
        }
        OpenRouterURLProtocol.configure(status: 200, data: Data(#"{}"#.utf8))
        await expectError(.invalidResponse, operation: {
            _ = try await client.transcribe(audio: Data(), model: "model", apiKey: "key", language: nil)
        }, message: "a malformed 2xx transcription payload should be rejected")
        OpenRouterURLProtocol.configure(status: 200, data: Data(#"{"choices":[]}"#.utf8))
        await expectError(.invalidResponse, operation: {
            _ = try await client.chatCompletion(
                model: "model",
                apiKey: "key",
                messages: [],
                temperature: 0,
                maxTokens: 1,
                sort: "latency"
            )
        }, message: "a chat payload without content should be rejected")
        OpenRouterURLProtocol.configure(
            status: 200,
            data: Data(#"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#.utf8)
        )
        await expectError(.truncatedResponse, operation: {
            _ = try await client.chatCompletion(
                model: "model",
                apiKey: "key",
                messages: [],
                temperature: 0,
                maxTokens: 1,
                sort: "latency"
            )
        }, message: "a valid but length-truncated cleanup must fall back to the raw transcript")
    }

    static func testAdaptersCancellationAndDisabledPolishing() async {
        let audio = DictationAudio(samples: [0, 0, 0])
        let transcriptionClient = BlockingOpenRouterClient(operation: .transcription)
        let transcriber = OpenRouterDictationTranscriber(
            client: transcriptionClient,
            apiKeyProvider: { "key" },
            modelProvider: { "model" }
        )
        let transcriptionTask = Task { try await transcriber.transcribe(audio) }
        for _ in 0..<100 where (await transcriptionClient.counts()).0 == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        await transcriber.cancelTranscription()
        switch await transcriptionTask.result {
        case .failure(_ as CancellationError):
            break
        default:
            assertCondition(false, "cancelling the transcription adapter should cancel its in-flight client request")
        }

        let chatClient = BlockingOpenRouterClient(operation: .chat)
        let polisher = OpenRouterDictationPolisher(
            client: chatClient,
            apiKeyProvider: { "key" },
            styleProvider: { .punctuated },
            customInstructionsProvider: { nil },
            modelProvider: { "model" },
            enabledProvider: { true }
        )
        let polishTask = Task { try await polisher.polish("raw") }
        for _ in 0..<100 where (await chatClient.counts()).1 == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        await polisher.cancelPolishing()
        switch await polishTask.result {
        case .failure(_ as CancellationError):
            break
        default:
            assertCondition(false, "cancelling the polisher should cancel its in-flight client request")
        }

        let disabledClient = BlockingOpenRouterClient(operation: .chat)
        let disabledPolisher = OpenRouterDictationPolisher(
            client: disabledClient,
            apiKeyProvider: { nil },
            styleProvider: { .formal },
            customInstructionsProvider: { nil },
            modelProvider: { "model" },
            enabledProvider: { false }
        )
        do {
            let result = try await disabledPolisher.polish("  leave this alone  ")
            assertEqual(result, "  leave this alone  ", "disabled polishing should be a no-op")
        } catch {
            assertCondition(false, "disabled polishing should never require an API key: \(error)")
        }
        let disabledCounts = await disabledClient.counts()
        assertEqual(disabledCounts.1, 0, "disabled polishing must not call OpenRouter")

        let casualClient = BlockingOpenRouterClient(
            operation: .transcription,
            chatResult: "Ready For Texting."
        )
        let casualPolisher = OpenRouterDictationPolisher(
            client: casualClient,
            apiKeyProvider: { "key" },
            styleProvider: { .casual },
            customInstructionsProvider: { nil },
            modelProvider: { "model" },
            enabledProvider: { true }
        )
        do {
            let result = try await casualPolisher.polish("ready for texting")
            assertEqual(result, "ready for texting.", "casual OpenRouter cleanup should always be lowercase")
        } catch {
            assertCondition(false, "casual OpenRouter cleanup should succeed: \(error)")
        }
    }
}
