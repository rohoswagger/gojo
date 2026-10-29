import Foundation

@main struct BarkRuntimeRegression {
    static func main() throws {
        let clean = BarkModelVariant.clean
        let verbatim = BarkModelVariant.verbatim
        precondition(clean.modelID != verbatim.modelID)
        precondition(clean.repository != verbatim.repository)
        precondition(clean.cachedModelFolderKey != verbatim.cachedModelFolderKey)
        precondition(clean.removalItems == ["bark-3.0-clean"] && verbatim.removalItems == ["coreml"])
        precondition(clean.modelSHA256.count == 21)
        precondition(clean.modelSHA256.keys.allSatisfy { $0.hasPrefix("bark-3.0-clean/") })
        precondition(verbatim.modelSHA256.keys.allSatisfy { $0.hasPrefix("coreml/ane/") })
        precondition(Set(clean.downloadPatterns) == Set(clean.modelSHA256.keys))
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let weights = try BarkTensorArchive(url: folder.appendingPathComponent("fixture.npz"))
        let matrix = try weights.weight("matrix")
        precondition(matrix.shape == [2, 3])
        precondition(matrix.values == [0.5, -1, 1.5, 8, -10, 12], "int8 weights use a separate scale per row")
        let bias = try weights.weight("bias").values
        precondition(bias == [1, -2, 3], "float32 tensors retain their values")
        do {
            _ = try BarkTensorArchive(url: folder.appendingPathComponent("invalid.npz"))
            fatalError("truncated archives must fail")
        } catch BarkRuntimeError.invalidWeights {}

        var mel = [Float](repeating: 0, count: 128 * 257)
        for band in 0..<128 { mel[band * 257 + band] = 1 }
        let audio = (0..<1600).map { i -> Float in
            Float(sin(Double(i) * 0.031) * 0.2 + cos(Double(i * i) * 0.00001) * 0.1)
        }
        let (features, valid) = try BarkSpeechRuntime.frontend(audio, mel: mel)
        let publisherNumpyFeatures: [Float] = [1.1589929, 1.1887834, 0.04556794, 0.9887835, -0.096114576, 0.03118252,
            0.04041743, -0.04926303, 0.36366728, 0.8109059, 0.76290405, 0.72373825,
            -0.52292156, -0.05429378, 0.1302216, 0.4684884, 0.3692783, 0.3288673,
            0.3460477, 1.000016, 1.5115987, -0.11342774, 0.18200532, 0.28105205,
            -1.1723197, -2.078591, -1.8012233, -2.004968, -1.224724, -1.6146721]
        precondition(valid == 10 && features.count == 11 * 128)
        for frame in 0..<10 {
            for band in 0..<3 {
                precondition(abs(features[frame * 128 + band] - publisherNumpyFeatures[frame * 3 + band]) < 0.0002,
                             "native STFT, mel and normalization must match the reference")
            }
        }
        precondition(features.suffix(128).allSatisfy { $0 == 0 }, "the invalid final frame is masked")
        let publisherSegmentSizes = [
            (235_999, [235_999]),
            (236_000, [236_000]),
            (236_001, [235_920, 81]),
            (600_000, [80_080, 80_000, 80_000, 80_000, 80_000, 199_920]),
        ]
        for (sampleCount, expectedSizes) in publisherSegmentSizes {
            let audio = [Float](repeating: 0.1, count: sampleCount)
            let segments = BarkSpeechRuntime.segments(audio)
            precondition(segments.map(\.count) == expectedSizes, "segment boundaries must match the publisher reference")
            precondition(segments.first?.lowerBound == 0 && segments.last?.upperBound == audio.count)
            precondition(segments.allSatisfy { $0.count <= 236_000 && !$0.isEmpty })
            for (a, b) in zip(segments, segments.dropFirst()) { precondition(a.upperBound == b.lowerBound) }
        }
        print("Bark tensor, frontend and segmentation regression passed")
    }
}
