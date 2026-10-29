@preconcurrency import CoreML
@preconcurrency import FluidAudio
import Foundation

enum BarkSpeechEngine: Sendable {
    case verbatim(BarkSpeechRuntime)
    case clean(AsrManager)

    static func load(variant: BarkModelVariant, from root: URL) async throws -> Self {
        try Task.checkCancellation()
        let folder = root.appendingPathComponent(variant.runtimeSubdirectory)
        switch variant {
        case .verbatim:
            return .verbatim(try BarkSpeechRuntime(folder: folder))
        case .clean:
            guard #available(macOS 15.0, *) else { throw BarkRuntimeError.unsupportedSystem }
            let models = try loadCleanModels(from: folder)
            try Task.checkCancellation()
            return .clean(AsrManager(models: models))
        }
    }

    // Load these pinned files directly: the SDK's repo loader otherwise resolves Parakeet's folder.
    static func loadCleanModels(from folder: URL) throws -> AsrModels {
        func model(_ name: String, units: MLComputeUnits) throws -> MLModel {
            try Task.checkCancellation()
            let configuration = MLModelConfiguration()
            configuration.computeUnits = units
            return try MLModel(contentsOf: folder.appendingPathComponent(name + ".mlmodelc"), configuration: configuration)
        }
        let vocabulary = try JSONDecoder().decode([String: String].self,
            from: Data(contentsOf: folder.appendingPathComponent("parakeet_vocab.json")))
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        return try AsrModels(
            encoder: model("Encoder", units: .cpuAndNeuralEngine),
            preprocessor: model("Preprocessor", units: .cpuOnly),
            decoder: model("Decoder", units: .cpuOnly),
            joint: model("JointDecisionv3", units: .cpuOnly),
            configuration: configuration,
            vocabulary: Dictionary(uniqueKeysWithValues: try vocabulary.map { key, value in
                guard let id = Int(key) else { throw BarkRuntimeError.invalidWeights }
                return (id, value)
            }),
            version: .v3
        )
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        switch self {
        case .verbatim(let runtime):
            return try runtime.transcribe(samples)
        case .clean(let manager):
            let layers = await manager.decoderLayerCount
            var state = try TdtDecoderState(decoderLayers: layers)
            let result = try await manager.transcribe(samples, decoderState: &state)
            return result.text.replacingOccurrences(of: "<unk>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func cleanup() async {
        if case .clean(let manager) = self { await manager.cleanup() }
    }
}
