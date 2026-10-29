import Foundation
import WhisperKit

private func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

actor SDKProbe {
    static let shared = SDKProbe()
    private(set) var loads: [DictationModelID: Int] = [:]
    private(set) var decodes: [DictationModelID: Int] = [:]
    private(set) var cleanups: [DictationModelID: Int] = [:]
    private var blockedLoads: Set<DictationModelID> = []
    private var blockedDecodes: Set<DictationModelID> = []
    private var loadWaiters: [DictationModelID: CheckedContinuation<Void, Never>] = [:]
    private var decodeWaiters: [DictationModelID: CheckedContinuation<Void, Never>] = [:]

    static func deletedInstalledFiles() { fatalError("residency deleted installed model artifacts") }

    func blockDecode(_ model: DictationModelID) { blockedDecodes.insert(model) }
    func blockLoad(_ model: DictationModelID) { blockedLoads.insert(model) }

    func load(_ model: DictationModelID) async {
        loads[model, default: 0] += 1
        if blockedLoads.contains(model) {
            await withCheckedContinuation { loadWaiters[model] = $0 }
        }
    }

    func decode(_ model: DictationModelID) async -> String {
        decodes[model, default: 0] += 1
        if blockedDecodes.contains(model) {
            await withCheckedContinuation { decodeWaiters[model] = $0 }
        }
        return "completed noncooperative SDK decode"
    }

    func cleanup(_ model: DictationModelID) { cleanups[model, default: 0] += 1 }

    func unblockDecode(_ model: DictationModelID) {
        blockedDecodes.remove(model)
        decodeWaiters.removeValue(forKey: model)?.resume()
    }

    func unblockLoad(_ model: DictationModelID) {
        blockedLoads.remove(model)
        loadWaiters.removeValue(forKey: model)?.resume()
    }
}

enum ModelHub { static var offlineMode = true }
enum FakeEncoderPrecision { case int8 }
struct FakeAsrModels {}
struct TdtDecoderState { init(decoderLayers: Int) throws {} }
struct FakeTranscription { let text: String }

actor UnifiedAsrManager {
    init(encoderPrecision: FakeEncoderPrecision) {}
    func loadModels(from folder: URL) async throws { await SDKProbe.shared.load(.parakeetUnifiedEnglish) }
    func transcribe(_ samples: [Float]) async throws -> String {
        await SDKProbe.shared.decode(.parakeetUnifiedEnglish)
    }
    func cleanup() async { await SDKProbe.shared.cleanup(.parakeetUnifiedEnglish) }
}

actor AsrManager {
    var decoderLayerCount: Int { 2 }
    init(models: FakeAsrModels) {}
    func transcribe(_ samples: [Float], decoderState: inout TdtDecoderState) async throws -> FakeTranscription {
        FakeTranscription(text: await SDKProbe.shared.decode(.parakeetV3Multilingual))
    }
    func cleanup() async { await SDKProbe.shared.cleanup(.parakeetV3Multilingual) }
}

struct WhisperKitConfig {
    init(modelFolder: String, verbose: Bool, prewarm: Bool, load: Bool, download: Bool) {}
}

final class WhisperKit: @unchecked Sendable {
    let tokenizer: (any WhisperTokenizer)? = nil
    init(_ config: WhisperKitConfig) async throws { await SDKProbe.shared.load(.whisperSmallEnglish) }
    func transcribe(audioArray: [Float], decodeOptions: DecodingOptions) async throws -> [FakeTranscription] {
        [FakeTranscription(text: await SDKProbe.shared.decode(.whisperSmallEnglish))]
    }
    func unloadModels() async { await SDKProbe.shared.cleanup(.whisperSmallEnglish) }
}

enum BarkModelVariant: Sendable {
    case verbatim
    case clean
    var modelID: DictationModelID { self == .clean ? .underdogBark3CleanEnglish : .underdogBark3English }
    var modelSHA256: [String: String] { [:] }
}

enum BarkRuntimeError: Error { case unsupportedSystem }

struct BarkSpeechEngine: Sendable {
    let modelID: DictationModelID
    static func load(variant: BarkModelVariant, from root: URL) async throws -> Self {
        await SDKProbe.shared.load(variant.modelID)
        return Self(modelID: variant.modelID)
    }
    func transcribe(_ samples: [Float]) async throws -> String { await SDKProbe.shared.decode(modelID) }
    func cleanup() async { await SDKProbe.shared.cleanup(modelID) }
}

private actor CompletionProbe {
    private(set) var completed = false
    func finish() { completed = true }
}

@main
struct DictationRecognitionLifecycleRegression {
    static func main() async throws {
        for model in [DictationModelID.whisperSmallEnglish, .parakeetUnifiedEnglish, .parakeetV3Multilingual, .underdogBark3English, .underdogBark3CleanEnglish] {
            try await sessionPinsDecodeAndUnload(model)
        }
        for model in [DictationModelID.parakeetUnifiedEnglish, .underdogBark3English, .underdogBark3CleanEnglish] {
            try await cancellationDuringLoadDoesNotStartDecode(model)
        }
        print("Dictation recognition lifecycle regression passed with production actor methods and controlled SDK stubs")
    }

    private static func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        fatalError("SDK operation did not reach its controlled boundary")
    }

    private static func sessionPinsDecodeAndUnload(_ model: DictationModelID) async throws {
        let backend = LocalDictationTranscriber(selectedModel: .whisperSmallEnglish)
        let request = DictationRecognitionRequest.local(try DictationLocalRecognition(model: model))
        let plan = DictationSessionPlan(recognition: request)
        try await backend.prepare(request: request)
        try await backend.prepare(request: request)
        require(await SDKProbe.shared.loads[model] == 1, "preparation must reuse the loaded requested backend")
        try await backend.beginSession(plan)
        if model == .underdogBark3English || model == .underdogBark3CleanEnglish {
            do {
                try await backend.install(model)
                fatalError("installation replaced an active Bark session")
            } catch BarkDictationError.transcriptionAlreadyRunning {}
        }
        await backend.releaseModels()
        require(await SDKProbe.shared.cleanups[model, default: 0] == 0, "a session pin must prevent idle unload")
        do {
            try await backend.selectModel(.whisperLargeV3)
            fatalError("model selection replaced an active session")
        } catch WhisperKitDictationError.transcriptionAlreadyRunning {}
        do {
            try await backend.prepare(request: .openRouter(modelID: "another-provider"))
            fatalError("a live request replaced the pinned provider")
        } catch WhisperKitDictationError.incompatibleRecognitionRequest {}

        await SDKProbe.shared.blockDecode(model)
        let transcription = Task { try await backend.transcribe(DictationAudio(samples: [0.1]), request: request) }
        try await waitUntil { await SDKProbe.shared.decodes[model] == 1 }
        let completion = CompletionProbe()
        let cancellation = Task {
            await backend.cancelTranscription()
            await completion.finish()
        }
        try await Task.sleep(for: .milliseconds(20))
        require(!(await completion.completed), "cancellation must await noncooperative SDK work")
        do {
            _ = try await backend.transcribe(DictationAudio(samples: [0.2]), request: request)
            fatalError("a replacement decode overlapped the draining SDK task")
        } catch WhisperKitDictationError.transcriptionAlreadyRunning {
        } catch ParakeetDictationError.transcriptionAlreadyRunning {
        } catch ParakeetV3DictationError.transcriptionAlreadyRunning {
        } catch BarkDictationError.transcriptionAlreadyRunning {}
        await SDKProbe.shared.unblockDecode(model)
        await cancellation.value
        switch await transcription.result {
        case .failure(_ as CancellationError): break
        default: fatalError("a cancelled SDK decode published a transcript")
        }
        await backend.endSession(plan.id)
        await backend.releaseModels()
        require(await SDKProbe.shared.cleanups[model] == 1, "idle release must call the SDK unload operation")
        try await backend.prepare(request: request)
        require(await SDKProbe.shared.loads[model] == 2, "the next preparation must reload released resources")
        await backend.releaseModels()
        require(await SDKProbe.shared.cleanups[model] == 2, "reloaded resources must remain releasable")
    }

    private static func cancellationDuringLoadDoesNotStartDecode(_ model: DictationModelID) async throws {
        let initialLoads = await SDKProbe.shared.loads[model, default: 0]
        let initialDecodes = await SDKProbe.shared.decodes[model, default: 0]
        let backend = LocalDictationTranscriber(selectedModel: .whisperSmallEnglish)
        let request = DictationRecognitionRequest.local(try DictationLocalRecognition(model: model))
        await SDKProbe.shared.blockLoad(model)
        let transcription = Task { try await backend.transcribe(DictationAudio(samples: [0.1]), request: request) }
        try await waitUntil { await SDKProbe.shared.loads[model] == initialLoads + 1 }
        let cancellation = Task { await backend.cancelTranscription() }
        try await Task.sleep(for: .milliseconds(20))
        await SDKProbe.shared.unblockLoad(model)
        await cancellation.value
        switch await transcription.result {
        case .failure(_ as CancellationError): break
        default: fatalError("a cancelled preparation proceeded into decoding")
        }
        require(await SDKProbe.shared.decodes[model, default: 0] == initialDecodes,
                "cancellation during load must prevent any SDK decode")
    }
}
