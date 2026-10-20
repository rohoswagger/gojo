import Foundation

struct DictationSpeechGate {
    static let minimumSpeechDuration: TimeInterval = 0.12
    static let initialThreshold: Float = 0.004
    static let minimumThreshold: Float = 0.0015
    static let maximumThreshold: Float = initialThreshold
    static let noiseHistoryCapacity = 200

    let minimumSpeechSampleCount: Int
    let adaptive: Bool
    private let calibrationSampleCount: Int
    private var quietSamples = 0
    private var quietHistory: [Float] = []
    private var historyIndex = 0
    private var noiseFloor: Float = 0
    private(set) var consecutiveSpeechSampleCount = 0
    private(set) var longestSpeechSampleCount = 0
    private(set) var hasAcceptedSpeech = false
    private(set) var hasSignal = false
    private(set) var containsInvalidSamples = false

    init(sampleRate: Double, adaptive: Bool = true) {
        minimumSpeechSampleCount = Int(ceil(sampleRate * Self.minimumSpeechDuration))
        calibrationSampleCount = Int(ceil(sampleRate * 0.2))
        self.adaptive = adaptive
        quietHistory.reserveCapacity(Self.noiseHistoryCapacity)
    }

    var threshold: Float {
        guard adaptive, quietSamples >= calibrationSampleCount else { return Self.initialThreshold }
        return min(Self.maximumThreshold, max(Self.minimumThreshold, noiseFloor * 2.5))
    }

    var noiseHistoryCount: Int { quietHistory.count }

    mutating func consume(frame: [Float]) -> Bool {
        guard !frame.isEmpty else { return false }
        guard frame.allSatisfy(\.isFinite) else {
            containsInvalidSamples = true
            consecutiveSpeechSampleCount = 0
            return false
        }
        let energy = frame.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = Float(sqrt(energy / Double(frame.count)))
        hasSignal = hasSignal || frame.contains { $0 != 0 }
        let isSpeech = rms >= threshold
        if isSpeech {
            consecutiveSpeechSampleCount += frame.count
            longestSpeechSampleCount = max(longestSpeechSampleCount, consecutiveSpeechSampleCount)
            hasAcceptedSpeech = hasAcceptedSpeech || consecutiveSpeechSampleCount >= minimumSpeechSampleCount
        } else {
            consecutiveSpeechSampleCount = 0
            if !hasAcceptedSpeech { observeQuiet(rms, sampleCount: frame.count) }
        }
        return isSpeech
    }

    mutating func endUtterance(continuing: Bool = false) {
        consecutiveSpeechSampleCount = 0
        hasAcceptedSpeech = continuing
    }

    private mutating func observeQuiet(_ rms: Float, sampleCount: Int) {
        quietSamples = min(calibrationSampleCount, quietSamples + sampleCount)
        if quietHistory.count < Self.noiseHistoryCapacity {
            quietHistory.append(rms)
        } else {
            quietHistory[historyIndex] = rms
            historyIndex = (historyIndex + 1) % Self.noiseHistoryCapacity
        }
        let ordered = quietHistory.sorted()
        let estimate = ordered[(ordered.count - 1) / 4]
        if quietHistory.count == 1 {
            noiseFloor = estimate
        } else {
            noiseFloor += (estimate - noiseFloor) * (estimate > noiseFloor ? 0.02 : 0.2)
        }
    }

    static func analyze(samples: [Float], sampleRate: Double, adaptive: Bool = true) -> Self {
        var gate = Self(sampleRate: sampleRate, adaptive: adaptive)
        let frameCount = max(1, Int(ceil(sampleRate * 0.01)))
        for offset in stride(from: 0, to: samples.count, by: frameCount) {
            _ = gate.consume(frame: Array(samples[offset..<min(offset + frameCount, samples.count)]))
        }
        return gate
    }
}
