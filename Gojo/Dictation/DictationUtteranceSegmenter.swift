import Foundation

struct DictationUtteranceSegmenter {
    enum ConfigurationError: Error, Equatable {
        case invalidSampleRate
        case invalidPauseDuration
    }

    static let speechRootMeanSquare: Float = 0.004
    static let maximumUtteranceDuration: TimeInterval = 20
    static let minimumSpeechDuration: TimeInterval = 0.12
    static let prerollDuration: TimeInterval = 0.2

    private struct Utterance {
        var samples: [Float]
        let continuesSpeech: Bool
        var speechSampleCount = 0
        var silenceSampleCount = 0
    }

    let sampleRate: Double
    let pauseSampleCount: Int
    let maximumUtteranceSampleCount: Int
    let minimumSpeechSampleCount: Int
    let analysisSampleCount: Int

    private var gate: DictationSpeechGate
    private let adaptiveSpeech: Bool
    private var utterance: Utterance?
    private var analysisSamples: [Float] = []
    private var prerollSamples: [Float]
    private var prerollCount = 0
    private var prerollIndex = 0
    private var continuesSpeech = false
    private var continuationSilenceCount = 0

    init(sampleRate: Double, pauseDuration: TimeInterval = 0.9, adaptiveSpeech: Bool = true) throws {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else {
            throw ConfigurationError.invalidSampleRate
        }
        guard pauseDuration.isFinite, pauseDuration > 0,
              pauseDuration <= Self.maximumUtteranceDuration else {
            throw ConfigurationError.invalidPauseDuration
        }
        self.sampleRate = sampleRate
        self.adaptiveSpeech = adaptiveSpeech
        gate = DictationSpeechGate(sampleRate: sampleRate, adaptive: adaptiveSpeech)
        pauseSampleCount = Int(ceil(sampleRate * pauseDuration))
        maximumUtteranceSampleCount = Int(ceil(sampleRate * Self.maximumUtteranceDuration))
        minimumSpeechSampleCount = Int(ceil(sampleRate * Self.minimumSpeechDuration))
        analysisSampleCount = Int(ceil(sampleRate * 0.01))
        prerollSamples = Array(repeating: 0, count: Int(ceil(sampleRate * Self.prerollDuration)))
        analysisSamples.reserveCapacity(analysisSampleCount)
    }

    var bufferedSampleCount: Int {
        (utterance?.samples.count ?? 0) + prerollCount + analysisSamples.count
    }

    var maximumBufferedSampleCount: Int {
        maximumUtteranceSampleCount + prerollSamples.count + analysisSampleCount
    }

    mutating func append(samples: [Float]) -> [[Float]] {
        var completed: [[Float]] = []
        var index = 0
        while index < samples.count {
            let count = min(analysisSampleCount - analysisSamples.count, samples.count - index)
            analysisSamples.append(contentsOf: samples[index..<(index + count)])
            index += count
            if analysisSamples.count == analysisSampleCount {
                consumeAnalysisSamples(completed: &completed)
                analysisSamples.removeAll(keepingCapacity: true)
            }
        }
        return completed
    }

    mutating func finish() -> [[Float]] {
        var completed: [[Float]] = []
        if !analysisSamples.isEmpty {
            consumeAnalysisSamples(completed: &completed)
        }
        completeUtterance(into: &completed)
        discard()
        return completed
    }

    mutating func discard() {
        utterance = nil
        analysisSamples.removeAll(keepingCapacity: true)
        prerollCount = 0
        prerollIndex = 0
        continuesSpeech = false
        continuationSilenceCount = 0
        gate = DictationSpeechGate(sampleRate: sampleRate, adaptive: adaptiveSpeech)
    }

    private mutating func consumeAnalysisSamples(completed: inout [[Float]]) {
        let isSpeech = gate.consume(frame: analysisSamples)
        var index = 0
        while index < analysisSamples.count {
            if utterance == nil {
                guard isSpeech else {
                    appendPreroll(analysisSamples[index...])
                    if continuesSpeech {
                        continuationSilenceCount += analysisSamples.count - index
                        if continuationSilenceCount >= pauseSampleCount {
                            continuesSpeech = false
                            continuationSilenceCount = 0
                            gate.endUtterance()
                        }
                    }
                    return
                }
                utterance = Utterance(samples: takePreroll(), continuesSpeech: continuesSpeech)
                continuesSpeech = false
                continuationSilenceCount = 0
            }

            let remainingDuration = maximumUtteranceSampleCount - utterance!.samples.count
            let remainingPause = isSpeech ? analysisSamples.count :
                pauseSampleCount - utterance!.silenceSampleCount
            let count = min(analysisSamples.count - index, remainingDuration, remainingPause)
            utterance!.samples.append(contentsOf: analysisSamples[index..<(index + count)])
            if isSpeech {
                utterance!.speechSampleCount += count
                utterance!.silenceSampleCount = 0
            } else {
                utterance!.silenceSampleCount += count
            }
            index += count

            if utterance!.samples.count == maximumUtteranceSampleCount ||
                utterance!.silenceSampleCount == pauseSampleCount {
                let reachedMaximum = utterance!.samples.count == maximumUtteranceSampleCount
                let carriesSpeech = utterance!.continuesSpeech ||
                    utterance!.speechSampleCount >= minimumSpeechSampleCount
                completeUtterance(into: &completed)
                continuesSpeech = reachedMaximum && carriesSpeech
                gate.endUtterance(continuing: continuesSpeech)
                continuationSilenceCount = 0
            }
        }
    }

    private mutating func completeUtterance(into completed: inout [[Float]]) {
        if let utterance, utterance.speechSampleCount > 0,
           utterance.continuesSpeech || utterance.speechSampleCount >= minimumSpeechSampleCount {
            completed.append(utterance.samples)
        }
        utterance = nil
    }

    private mutating func appendPreroll(_ samples: ArraySlice<Float>) {
        for sample in samples {
            prerollSamples[prerollIndex] = sample
            prerollIndex = (prerollIndex + 1) % prerollSamples.count
            prerollCount = min(prerollCount + 1, prerollSamples.count)
        }
    }

    private mutating func takePreroll() -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(prerollCount)
        let startIndex = (prerollIndex - prerollCount + prerollSamples.count) % prerollSamples.count
        for offset in 0..<prerollCount {
            samples.append(prerollSamples[(startIndex + offset) % prerollSamples.count])
        }
        prerollCount = 0
        prerollIndex = 0
        return samples
    }
}

struct DictationUtteranceMailbox {
    enum Failure: Error, Equatable {
        case overflow
    }

    static let capacity = 3

    private var segmenter: DictationUtteranceSegmenter
    private var completed: [[Float]] = []

    init(segmenter: DictationUtteranceSegmenter) {
        self.segmenter = segmenter
    }

    var bufferedSampleCount: Int {
        segmenter.bufferedSampleCount + completed.reduce(0) { $0 + $1.count }
    }

    var maximumBufferedSampleCount: Int {
        let preservedHoldSamples = completed.reduce(0) {
            $0 + max(0, $1.count - segmenter.maximumUtteranceSampleCount)
        }
        return segmenter.maximumBufferedSampleCount +
            (Self.capacity + 1) * segmenter.maximumUtteranceSampleCount + preservedHoldSamples
    }

    mutating func append(samples: [Float]) throws {
        try enqueue(segmenter.append(samples: samples))
    }

    mutating func seedCapture(samples: [Float]) throws {
        let phrases = segmenter.append(samples: samples)
        if !phrases.isEmpty {
            try enqueue([phrases.flatMap { $0 }])
        }
    }

    mutating func drain() -> [[Float]] {
        let result = completed
        completed.removeAll(keepingCapacity: false)
        return result
    }

    mutating func finish() throws -> [[Float]] {
        try enqueue(segmenter.finish())
        return drain()
    }

    mutating func discard() {
        segmenter.discard()
        completed.removeAll(keepingCapacity: false)
    }

    private mutating func enqueue(_ segments: [[Float]]) throws {
        completed.append(contentsOf: segments)
        guard completed.count <= Self.capacity else { throw Failure.overflow }
    }
}
