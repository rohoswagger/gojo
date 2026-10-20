import Foundation

private func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

private final class CurrentAPIKey: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String? = "initial-key"

    var value: String? {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}

private actor ExplicitRequestClient: OpenRouterDictationClient {
    private(set) var models: [String] = []
    private(set) var keys: [String] = []
    private(set) var languages: [String?] = []
    private var blocks = false
    private var waiter: CheckedContinuation<Void, Never>?

    func listTranscriptionModels(apiKey: String?) async throws -> [OpenRouterTranscriptionModel] { [] }
    func block() { blocks = true }
    func unblock() { blocks = false; waiter?.resume(); waiter = nil }

    func transcribe(audio: Data, model: String, apiKey: String, language: String?) async throws -> String {
        models.append(model)
        keys.append(apiKey)
        languages.append(language)
        if blocks { await withCheckedContinuation { waiter = $0 } }
        return "result for \(model)"
    }
}

private actor CancellationProbe {
    private(set) var complete = false
    func finish() { complete = true }
}

@main
struct DictationCloudRequestRegression {
    static func main() async throws {
        let client = ExplicitRequestClient()
        let key = CurrentAPIKey()
        let backend = OpenRouterDictationTranscriber(client: client, apiKeyProvider: { key.value })
        let request = DictationRecognitionRequest.openRouter(modelID: "frozen-a")
        let plan = DictationSessionPlan(recognition: request)
        try await backend.beginSession(plan)
        try await backend.prepare(request: request)
        let audio = DictationAudio(samples: [0.1])
        require(try await backend.transcribe(audio, request: request) == "result for frozen-a",
                "cloud recognition must use the explicit frozen model")
        require(await client.models == ["frozen-a"], "cloud request must retain its model identifier")
        let languages = await client.languages
        require(languages.count == 1 && languages[0] == nil,
                "cloud recognition must not invent a language capability")
        do {
            try await backend.prepare(request: .openRouter(modelID: "later-preference"))
            fatalError("a later model preference replaced a frozen cloud session")
        } catch OpenRouterDictationError.unsupportedModel {}
        await backend.endSession(UUID())
        do {
            try await backend.beginSession(DictationSessionPlan(recognition: request))
            fatalError("a stale cleanup released another session's cloud pin")
        } catch OpenRouterDictationError.requestFailed {}

        key.value = nil
        do {
            _ = try await backend.transcribe(audio, request: request)
            fatalError("a frozen session retained a revoked API key")
        } catch OpenRouterDictationError.missingAPIKey {}
        require(await client.models.count == 1, "key revocation must reject before network work")
        key.value = "current-key"

        await client.block()
        let transcription = Task { try await backend.transcribe(audio, request: request) }
        for _ in 0..<500 {
            if await client.models.count == 2 { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        require(await client.models.count == 2, "controlled cloud request must have started")
        let completion = CancellationProbe()
        let cancellation = Task {
            await backend.cancelTranscription()
            await completion.finish()
        }
        try await Task.sleep(for: .milliseconds(20))
        require(!(await completion.complete), "cloud cancellation must await its client task")
        await client.unblock()
        await cancellation.value
        switch await transcription.result {
        case .failure(_ as CancellationError): break
        default: fatalError("cancelled cloud work published a late transcript")
        }
        await backend.endSession(plan.id)
        let next = DictationRecognitionRequest.openRouter(modelID: "frozen-b")
        let nextPlan = DictationSessionPlan(recognition: next)
        try await backend.beginSession(nextPlan)
        require(try await backend.transcribe(audio, request: next) == "result for frozen-b",
                "a later session must use its own model snapshot")
        require(await client.keys == ["initial-key", "current-key", "current-key"],
                "each request must consult current API-key consent")
        await backend.endSession(nextPlan.id)
        print("Dictation cloud request regression passed")
    }
}
