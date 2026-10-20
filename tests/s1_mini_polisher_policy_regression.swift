import Foundation

protocol DictationTextPolishing: Sendable {
    func polish(_ transcript: String, options: DictationTextOptions) async throws -> String
    func cancelPolishing() async
}

private actor Gate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private enum RuntimeFailure: Error { case failed }

private actor RuntimeProbe {
    static let shared = RuntimeProbe()
    private var events: [String] = []
    private var waiters: [(String, CheckedContinuation<Void, Never>)] = []
    private var inferenceCount = 0
    private var installed = true
    private var failsInference = false
    private var failsModelURL = false
    private var output = "Clean text."
    private var storeGate: Gate?
    private var inferenceGate: Gate?
    private var preparationGate: Gate?

    func reset() {
        precondition(waiters.isEmpty)
        events = []
        inferenceCount = 0
        installed = true
        failsInference = false
        failsModelURL = false
        output = "Clean text."
        storeGate = nil
        inferenceGate = nil
        preparationGate = nil
    }

    func configure(
        installed: Bool = true,
        output: String = "Clean text.",
        failsInference: Bool = false,
        failsModelURL: Bool = false,
        storeGate: Gate? = nil,
        inferenceGate: Gate? = nil,
        preparationGate: Gate? = nil
    ) {
        self.installed = installed
        self.output = output
        self.failsInference = failsInference
        self.failsModelURL = failsModelURL
        self.storeGate = storeGate
        self.inferenceGate = inferenceGate
        self.preparationGate = preparationGate
    }

    func record(_ event: String) {
        events.append(event)
        let ready = waiters.filter { $0.0 == event }
        waiters.removeAll { $0.0 == event }
        for waiter in ready { waiter.1.resume() }
    }

    func wait(for event: String) async {
        guard !events.contains(event) else { return }
        await withCheckedContinuation { waiters.append((event, $0)) }
    }

    func snapshot() -> [String] { events }

    func isInstalled() async -> Bool {
        let gate = storeGate
        record("storeStarted")
        await gate?.wait()
        record("storeEnded")
        return installed
    }

    func modelURL() throws -> URL {
        if failsModelURL { throw RuntimeFailure.failed }
        return URL(fileURLWithPath: "/tmp/not-an-installed-model.gguf")
    }

    func prepare() async {
        let gate = preparationGate
        record("prepareStarted")
        await withTaskCancellationHandler {
            await gate?.wait()
        } onCancel: {
            Task { await self.record("prepareCancelled") }
        }
        record("prepareEnded")
    }

    func infer() async throws -> String {
        inferenceCount += 1
        let attempt = inferenceCount
        let gate = inferenceGate
        let response = output
        let fails = failsInference
        record("inference\(attempt)Started")
        await withTaskCancellationHandler {
            await gate?.wait()
        } onCancel: {
            Task { await self.record("inference\(attempt)Cancelled") }
        }
        record("inference\(attempt)Ended")
        try Task.checkCancellation()
        if fails { throw RuntimeFailure.failed }
        return response
    }
}

actor S1MiniModelStore {
    func isInstalled() async -> Bool { await RuntimeProbe.shared.isInstalled() }
    func modelURL() async throws -> URL { try await RuntimeProbe.shared.modelURL() }
    func install() async throws { await RuntimeProbe.shared.record("install") }
    func remove() async throws { await RuntimeProbe.shared.record("remove") }
}

actor S1MiniLlamaRuntime {
    func polish(_ transcript: String, style: DictationWritingStyle, modelURL: URL) async throws -> String {
        try await RuntimeProbe.shared.infer()
    }

    func prepare(modelURL: URL) async throws {
        await RuntimeProbe.shared.prepare()
    }

    func unload() async { await RuntimeProbe.shared.record("unload") }
}

private actor CompletionProbe {
    private(set) var done = false
    func finish() { done = true }
}

@main
struct S1MiniPolisherPolicyRegression {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func precedes(_ first: String, _ second: String, in events: [String]) -> Bool {
        guard let lhs = events.firstIndex(of: first), let rhs = events.firstIndex(of: second) else { return false }
        return lhs < rhs
    }

    static func main() async throws {
        let deadline = Task {
            try await Task.sleep(for: .seconds(20))
            fatalError("polisher regression did not complete")
        }
        defer { deadline.cancel() }
        let probe = RuntimeProbe.shared
        let options = DictationTextOptions(commands: .punctuation, cleanup: .s1Mini(.punctuated))

        await probe.reset()
        let disabled = S1MiniDictationPolisher()
        let plain = try await disabled.polish("Hello comma world period", options: DictationTextOptions(commands: .punctuation))
        require(plain == "Hello, world.", "disabled cleanup still executes the shared final-text policy")
        require(await probe.snapshot().isEmpty, "disabled cleanup does not touch the model store or runtime")

        await probe.reset()
        await probe.configure(installed: false)
        let missing = try await S1MiniDictationPolisher().polish("Hello comma world", options: options)
        require(missing == "Hello, world", "missing cleanup weights preserve deterministic finalization")
        require(!(await probe.snapshot()).contains("inference1Started"), "uninstalled cleanup does not run inference")

        await probe.reset()
        await probe.configure(failsModelURL: true)
        let storageFailure = try await S1MiniDictationPolisher().polish("hello comma world", options: options)
        require(storageFailure == "hello, world", "cleanup storage failure still renders the corrected original")

        await probe.reset()
        await probe.configure(output: "Hello comma World period")
        let safe = try await S1MiniDictationPolisher().polish("hello comma world period", options: options)
        require(safe == "Hello, World.", "production polish accepts safe semantic cleanup before command rendering")

        await probe.reset()
        await probe.configure(output: "Hello World.")
        let unsafe = try await S1MiniDictationPolisher().polish("hello comma world period", options: options)
        require(unsafe == "hello, world.", "production polish falls back when S1 consumes command phrases")

        await probe.reset()
        await probe.configure(failsInference: true)
        let failed = try await S1MiniDictationPolisher().polish("hello comma world period", options: options)
        require(failed == "hello, world.", "runtime inference failure still renders the corrected original")

        await probe.reset()
        let storeGate = Gate()
        await probe.configure(storeGate: storeGate)
        let pending = S1MiniDictationPolisher()
        let pendingPolish = Task { try await pending.polish("hello comma world", options: options) }
        await probe.wait(for: "storeStarted")
        await pending.cancelPolishing()
        await storeGate.release()
        require(try await pendingPolish.value == "hello, world", "cancel invalidates polish suspended before runtime work was registered")
        require(!(await probe.snapshot()).contains("inference1Started"), "cancelled preflight cannot start inference later")

        await probe.reset()
        let inferenceGate = Gate()
        await probe.configure(output: "Hello comma world", inferenceGate: inferenceGate)
        let active = S1MiniDictationPolisher()
        let first = Task { try await active.polish("hello comma world", options: options) }
        await probe.wait(for: "inference1Started")
        let released = CompletionProbe()
        let release = Task {
            await active.releaseModels()
            await released.finish()
        }
        await probe.wait(for: "inference1Cancelled")
        require(!(await released.done), "release waits for owned inference to finish cancellation")
        require(!(await probe.snapshot()).contains("unload"), "runtime is not unloaded during owned inference")
        await probe.configure(output: "Next comma take")
        let next = Task { try await active.polish("next comma take", options: options) }
        await inferenceGate.release()
        await release.value
        do {
            _ = try await first.value
            fatalError("release must cancel active inference")
        } catch is CancellationError {}
        require(try await next.value == "Next, take", "new work proceeds after an existing release drains")
        let releasedEvents = await probe.snapshot()
        require(precedes("inference1Ended", "unload", in: releasedEvents), "owned inference ends before runtime unload")
        require(precedes("unload", "inference2Started", in: releasedEvents), "new inference waits for runtime unload to finish")
        require(!releasedEvents.contains("remove"), "idle release preserves installed model files")

        await probe.reset()
        let preparationGate = Gate()
        await probe.configure(preparationGate: preparationGate)
        let warming = S1MiniDictationPolisher()
        let preparation = Task { await warming.prepareIfInstalled() }
        await probe.wait(for: "prepareStarted")
        let warmReleased = CompletionProbe()
        let releaseWarm = Task {
            await warming.releaseModels()
            await warmReleased.finish()
        }
        await probe.wait(for: "prepareCancelled")
        require(!(await warmReleased.done), "release waits for owned warmup to drain")
        await preparationGate.release()
        await preparation.value
        await releaseWarm.value
        require(precedes("prepareEnded", "unload", in: await probe.snapshot()), "warmup completes before runtime unload")

        await probe.reset()
        let warmStoreGate = Gate()
        await probe.configure(storeGate: warmStoreGate)
        let preflighting = S1MiniDictationPolisher()
        let warmPreflight = Task { await preflighting.prepareIfInstalled() }
        await probe.wait(for: "storeStarted")
        await preflighting.releaseModels()
        await warmStoreGate.release()
        await warmPreflight.value
        require(!(await probe.snapshot()).contains("prepareStarted"), "a stale warmup preflight cannot reload after release")
        print("PASS S1-mini frozen policy and runtime ownership")
    }
}
