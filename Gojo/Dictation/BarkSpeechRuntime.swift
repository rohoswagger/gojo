import Accelerate
import CoreML
import Foundation

// Port of ConwayResearch/Underdog-Bark-3.0's bark_coreml.py at 85db2ad.
// CC-BY-4.0; see THIRD_PARTY_LICENSES for attribution and changes.
final class BarkSpeechRuntime: @unchecked Sendable {
    private static let sampleRate = 16_000
    private static let shortWindowSeconds = 8
    private static let maximumWindowSeconds = 15
    private static let leadingSilenceSamples = sampleRate / 4
    private static let maximumSegmentSamples = maximumWindowSeconds * sampleRate - leadingSilenceSamples

    static let revision = "85db2ad18ab41e534a222ee253c29191d77ed919"
    struct Vocabulary: Decodable {
        let pieces: [String]
        let vocab_size: Int
        let blank_id: Int
        let durations: [Int]
        let max_symbols_per_step: Int
        let special_ids: [Int]
    }
    private let vocabulary: Vocabulary
    private let embedding: BarkTensorArchive.Tensor
    private let lstm: [(BarkTensorArchive.Tensor, BarkTensorArchive.Tensor, [Float])]
    private let projection: BarkTensorArchive.Tensor
    private let projectionBias: [Float]
    private let head: BarkTensorArchive.Tensor
    private let headBias: [Float]
    private let mel: [Float]
    private let encoders: [Int: MLModel]

    init(folder: URL) throws {
        guard #available(macOS 15.0, *) else { throw BarkRuntimeError.unsupportedSystem }
        #if !arch(arm64)
        throw BarkRuntimeError.unsupportedSystem
        #else
        let archive = try BarkTensorArchive(url: folder.appendingPathComponent("decoder.npz"))
        vocabulary = try JSONDecoder().decode(Vocabulary.self, from: Data(contentsOf: folder.appendingPathComponent("vocab.json")))
        embedding = try archive.weight("decoder.embedding.weight")
        projection = try archive.weight("decoder.decoder_projector.weight")
        projectionBias = try archive.weight("decoder.decoder_projector.bias").values
        head = try archive.weight("joint.head.weight")
        headBias = try archive.weight("joint.head.bias").values
        mel = try archive.weight("mel_filters").values
        lstm = try (0..<2).map { layer in
            let prefix = "decoder.lstm."
            let bias1 = try archive.weight(prefix + "bias_ih_l\(layer)").values
            let bias2 = try archive.weight(prefix + "bias_hh_l\(layer)").values
            return (try archive.weight(prefix + "weight_ih_l\(layer)"),
                    try archive.weight(prefix + "weight_hh_l\(layer)"), zip(bias1, bias2).map(+))
        }
        let compiled = folder.appendingPathComponent("BarkEncoder-\(Self.revision).mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let temporary = try MLModel.compileModel(at: folder.appendingPathComponent("BarkEncoder.mlpackage"))
            defer { try? FileManager.default.removeItem(at: temporary) }
            do {
                try FileManager.default.moveItem(at: temporary, to: compiled)
            } catch {
                guard FileManager.default.fileExists(atPath: compiled.path) else { throw error }
            }
        }
        var models: [Int: MLModel] = [:]
        for seconds in [Self.shortWindowSeconds, Self.maximumWindowSeconds] {
            try Task.checkCancellation()
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndNeuralEngine
            configuration.functionName = "w\(seconds)"
            models[seconds] = try MLModel(contentsOf: compiled, configuration: configuration)
        }
        encoders = models
        #endif
    }

    func transcribe(_ samples: [Float]) throws -> String {
        guard !samples.isEmpty, samples.allSatisfy(\.isFinite) else { return "" }
        return try Self.segments(samples).map { range in
            try Task.checkCancellation()
            let audio = [Float](repeating: 0, count: Self.leadingSilenceSamples) + samples[range]
            let (features, valid) = try Self.frontend(audio, mel: mel)
            let window = audio.count <= Self.shortWindowSeconds * Self.sampleRate
                ? Self.shortWindowSeconds : Self.maximumWindowSeconds
            let frames = window * 100 + 1
            let input = try MLMultiArray(shape: [1, NSNumber(value: frames), 128], dataType: .float16)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: frames)], dataType: .int32)
            for i in 0..<input.count { input[i] = NSNumber(value: i < features.count ? features[i] : 0) }
            for i in 0..<frames { mask[i] = NSNumber(value: i < valid ? 1 : 0) }
            let provider = try MLDictionaryFeatureProvider(dictionary: ["features": input, "mask": mask])
            guard let encoder = encoders[window],
                  let encoded = try encoder.prediction(from: provider).featureValue(for: "encoded")?.multiArrayValue,
                  encoded.shape.count == 3, encoded.shape[2].intValue == 640 else {
                throw BarkRuntimeError.invalidEncoderOutput
            }
            var length = valid
            for _ in 0..<3 { length = (length - 1) / 2 + 1 }
            guard length <= encoded.shape[1].intValue else { throw BarkRuntimeError.invalidEncoderOutput }
            let strides = encoded.strides.map(\.intValue)
            let values = (0..<length).flatMap { t in
                (0..<640).map { encoded[t * strides[1] + $0 * strides[2]].floatValue }
            }
            guard values.allSatisfy(\.isFinite) else { throw BarkRuntimeError.invalidEncoderOutput }
            let ids = try decode(values)
            return ids.filter { !vocabulary.special_ids.contains($0) && $0 < vocabulary.pieces.count }
                .map { vocabulary.pieces[$0] }.joined().replacingOccurrences(of: "▁", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func segments(_ samples: [Float]) -> [Range<Int>] {
        let maximum = Self.maximumSegmentSamples
        guard samples.count > maximum else { return [0..<samples.count] }
        let frameCount = samples.count / 160
        let energy = (0..<frameCount).map { frame in
            samples[(frame * 160)..<((frame + 1) * 160)].reduce(Float(0)) { $0 + $1 * $1 } / 160
        }
        var smoothed = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            smoothed[frame] = energy[max(0, frame - 10)..<min(frameCount, frame + 10)].reduce(0, +) / 20
        }
        var ranges: [Range<Int>] = []
        var start = 0
        while samples.count - start > maximum {
            let low = (start + 80_000) / 160
            let high = (start + maximum) / 160
            let quietest = (low..<high).min { smoothed[$0] < smoothed[$1] }!
            let cut = quietest * 160 + 80
            ranges.append(start..<cut)
            start = cut
        }
        ranges.append(start..<samples.count)
        return ranges
    }

    static func frontend(_ audio: [Float], mel: [Float]) throws -> ([Float], Int) {
        let frames = 1 + audio.count / 160
        let valid = audio.count / 160
        guard valid > 0 else { throw BarkRuntimeError.invalidEncoderOutput }
        var emphasized = audio
        for i in 1..<audio.count { emphasized[i] = audio[i] - 0.97 * audio[i - 1] }
        var window = [Float](repeating: 0, count: 512)
        for i in 0..<400 { window[i + 56] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / 399)) }
        guard let dft = vDSP_DFT_zop_CreateSetup(nil, 512, .FORWARD) else { throw BarkRuntimeError.invalidEncoderOutput }
        defer { vDSP_DFT_DestroySetup(dft) }
        var features = [Float](repeating: 0, count: frames * 128)
        let imaginary = [Float](repeating: 0, count: 512)
        var realOut = imaginary
        var imaginaryOut = imaginary
        for frame in 0..<frames {
            try Task.checkCancellation()
            let signal = (0..<512).map { bin -> Float in
                let index = frame * 160 + bin - 256
                return index >= 0 && index < emphasized.count ? emphasized[index] * window[bin] : 0
            }
            vDSP_DFT_Execute(dft, signal, imaginary, &realOut, &imaginaryOut)
            let power = (0..<257).map { realOut[$0] * realOut[$0] + imaginaryOut[$0] * imaginaryOut[$0] }
            var bands = [Float](repeating: 0, count: 128)
            vDSP_mmul(mel, 1, power, 1, &bands, 1, 128, 1, 257)
            for band in 0..<128 { features[frame * 128 + band] = log(bands[band] + pow(2, -24)) }
        }
        for band in 0..<128 {
            let mean = (0..<valid).reduce(Float(0)) { $0 + features[$1 * 128 + band] } / Float(valid)
            let variance = (0..<valid).reduce(Float(0)) {
                let delta = features[$1 * 128 + band] - mean
                return $0 + delta * delta
            } / Float(max(1, valid - 1))
            let denominator = sqrt(variance) + 1e-5
            for frame in 0..<frames {
                let index = frame * 128 + band
                features[index] = frame < valid ? (features[index] - mean) / denominator : 0
            }
        }
        return (features, valid)
    }

    private func multiply(_ weight: BarkTensorArchive.Tensor, _ x: [Float], bias: [Float]) -> [Float] {
        var output = [Float](repeating: 0, count: bias.count)
        vDSP_mmul(weight.values, 1, x, 1, &output, 1,
                  vDSP_Length(weight.shape[0]), 1, vDSP_Length(weight.shape[1]))
        return zip(output, bias).map(+)
    }

    func decode(_ encoded: [Float]) throws -> [Int] {
        let hidden = embedding.shape[1]
        var state = (0..<2).map { _ in ([Float](repeating: 0, count: hidden), [Float](repeating: 0, count: hidden)) }
        func step(_ token: Int) -> [Float] {
            var x = Array(embedding.values[(token * hidden)..<((token + 1) * hidden)])
            for layer in 0..<2 {
                let (wi, wh, bias) = lstm[layer]
                let recurrent = multiply(wh, state[layer].0, bias: bias)
                let gates = multiply(wi, x, bias: recurrent)
                var h = [Float](repeating: 0, count: hidden)
                var c = h
                for j in 0..<hidden {
                    let i = 1 / (1 + exp(-gates[j]))
                    let f = 1 / (1 + exp(-gates[j + hidden]))
                    let g = tanh(gates[j + hidden * 2])
                    let o = 1 / (1 + exp(-gates[j + hidden * 3]))
                    c[j] = f * state[layer].1[j] + i * g
                    h[j] = o * tanh(c[j])
                }
                state[layer] = (h, c)
                x = h
            }
            return multiply(projection, x, bias: projectionBias)
        }
        var decoder = step(vocabulary.blank_id)
        var time = 0
        var symbols = 0
        var output: [Int] = []
        while time < encoded.count / 640 {
            try Task.checkCancellation()
            let joint = (0..<640).map { max(encoded[time * 640 + $0] + decoder[$0], 0) }
            let logits = multiply(head, joint, bias: headBias)
            guard logits.allSatisfy(\.isFinite) else { throw BarkRuntimeError.invalidEncoderOutput }
            let token = (0..<vocabulary.vocab_size).max { logits[$0] < logits[$1] }!
            let durationIndex = (0..<vocabulary.durations.count).max {
                logits[vocabulary.vocab_size + $0] < logits[vocabulary.vocab_size + $1]
            }!
            var duration = vocabulary.durations[durationIndex]
            if token == vocabulary.blank_id {
                time += max(duration, 1)
                symbols = 0
            } else {
                output.append(token)
                decoder = step(token)
                symbols += 1
                if duration == 0 && symbols >= vocabulary.max_symbols_per_step { duration = 1 }
                if duration > 0 { symbols = 0 }
                time += duration
            }
        }
        return output
    }
}
