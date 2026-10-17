import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func samples(_ amplitude: Float, count: Int) -> [Float] {
    (0..<count).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
}

@main
struct DictationPauseSegmentationRegression {
    static func main() throws {
        try silenceDoesNotAccumulate()
        try pauseUsesSourceSamples()
        try shortPauseKeepsOneUtterance()
        try stopFlushesOnce()
        try longSpeechSplitsWithoutOverlap()
        try prerollHasNoRepeatedSpeech()
        try energyThresholdUsesRawSamples()
        try mailboxIsBounded()
        try promotedHoldBudgetIncludesPreservedSpeech()
        try malformedConfigurationIsRejected()
        print("Dictation pause segmentation regression passed")
    }

    private static func silenceDoesNotAccumulate() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        for _ in 0..<120 {
            require(segmenter.append(samples: samples(0, count: 16_000)).isEmpty,
                    "silence must not yield utterances")
            require(segmenter.bufferedSampleCount <= 3_200,
                    "two minutes of silence must retain only 200 ms preroll")
        }
        require(segmenter.finish().isEmpty, "stopping during silence must not yield audio")
        require(segmenter.bufferedSampleCount == 0, "finish must release buffered audio")
    }

    private static func pauseUsesSourceSamples() throws {
        for rate in [16_000.0, 44_100, 48_000] {
            var segmenter = try DictationUtteranceSegmenter(sampleRate: rate)
            let speechCount = Int(rate * 0.12)
            let pauseCount = Int(rate * 0.9)
            require(segmenter.append(samples: samples(0.02, count: speechCount)).isEmpty,
                    "speech must wait for its pause")
            require(segmenter.append(samples: samples(0, count: pauseCount - 1)).isEmpty,
                    "a pause one source sample short must not yield")
            let utterances = segmenter.append(samples: [0])
            require(utterances.count == 1, "the final source pause sample must yield")
            require(utterances[0].count == speechCount + pauseCount,
                    "segment length must use hardware sample rate")
            require(segmenter.finish().isEmpty, "stop must not repeat a paused utterance")
        }
    }

    private static func shortPauseKeepsOneUtterance() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000, pauseDuration: 0.5)
        let first = samples(0.02, count: 3_200)
        let pause = samples(0, count: 7_840)
        let second = samples(0.03, count: 3_200)
        require(segmenter.append(samples: first + pause + second).isEmpty,
                "490 ms pause must keep speech together with a 500 ms setting")
        let utterances = segmenter.append(samples: samples(0, count: 8_000))
        require(utterances == [first + pause + second + samples(0, count: 8_000)],
                "speech on either side of a short pause must keep its exact samples")
    }

    private static func stopFlushesOnce() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let speech = samples(0.02, count: 2_000)
        require(segmenter.append(samples: speech).isEmpty, "ongoing speech must remain buffered")
        require(segmenter.finish() == [speech], "stop must flush the final partial analysis frame")
        require(segmenter.finish().isEmpty, "a second finish must not flush again")
        _ = segmenter.append(samples: samples(0.03, count: 3_200))
        segmenter.discard()
        require(segmenter.finish().isEmpty, "cancel must discard unfinished speech")

        var click = try DictationUtteranceSegmenter(sampleRate: 16_000)
        _ = click.append(samples: samples(0.4, count: 1_760))
        require(click.finish().isEmpty, "under 120 ms of loud energy must be rejected")
    }

    private static func longSpeechSplitsWithoutOverlap() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let speech = samples(0.02, count: 16_000 * 41)
        var utterances: [[Float]] = []
        for offset in stride(from: 0, to: speech.count, by: 2_047) {
            utterances += segmenter.append(samples: Array(speech[offset..<min(offset + 2_047, speech.count)]))
            require(segmenter.bufferedSampleCount <= segmenter.maximumBufferedSampleCount,
                    "continuous speech storage must stay bounded")
        }
        utterances += segmenter.finish()
        require(utterances.map(\.count) == [320_000, 320_000, 16_000],
                "41 seconds must split into 20, 20, and 1 second")
        require(utterances.flatMap { $0 } == speech,
                "maximum-duration boundaries must neither duplicate nor omit samples")

        var shortTail = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let continuingSpeech = samples(0.02, count: 320_800)
        let completed = shortTail.append(samples: continuingSpeech) + shortTail.finish()
        require(completed.map(\.count) == [320_000, 800],
                "a short speech tail after a forced split must survive")
        require(completed.flatMap { $0 } == continuingSpeech,
                "forced split must preserve a tail shorter than speech admission duration")
    }

    private static func prerollHasNoRepeatedSpeech() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let first = samples(0.02, count: 3_200)
        let second = samples(0.03, count: 3_200)
        let silence = samples(0, count: 14_400)
        let firstOutput = segmenter.append(samples: samples(0, count: 16_000) + first + silence)
        require(firstOutput == [samples(0, count: 3_200) + first + silence],
                "leading silence must retain only 200 ms preroll")
        _ = segmenter.append(samples: samples(0, count: 6_400) + second)
        let secondOutput = segmenter.finish()
        require(secondOutput == [samples(0, count: 3_200) + second],
                "preroll after a completed utterance must contain fresh silence only")
    }

    private static func energyThresholdUsesRawSamples() throws {
        var quiet = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let quietSpeech = samples(0.005, count: 3_200)
        _ = quiet.append(samples: quietSpeech)
        require(quiet.finish() == [quietSpeech], "quiet speech above raw RMS floor must survive")

        var noise = try DictationUtteranceSegmenter(sampleRate: 16_000)
        _ = noise.append(samples: samples(0.002, count: 160_000))
        require(noise.finish().isEmpty, "noise below raw RMS floor must not become an utterance")

        var loudNoise = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let sustainedNoise = samples(0.006, count: 3_200)
        _ = loudNoise.append(samples: sustainedNoise)
        require(loudNoise.finish() == [sustainedNoise],
                "energy detection also admits sustained background noise above its threshold")
    }

    private static func mailboxIsBounded() throws {
        let segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        var mailbox = DictationUtteranceMailbox(segmenter: segmenter)
        let utterance = samples(0.02, count: 3_200) + samples(0, count: 14_400)
        for _ in 0..<DictationUtteranceMailbox.capacity {
            try mailbox.append(samples: utterance)
            require(mailbox.bufferedSampleCount <= mailbox.maximumBufferedSampleCount,
                    "completed raw audio storage must stay bounded")
        }
        do {
            try mailbox.append(samples: utterance)
            require(false, "a fourth undrained utterance must fail explicitly")
        } catch DictationUtteranceMailbox.Failure.overflow {
            require(mailbox.bufferedSampleCount == 0, "overflow must release all pending raw audio")
        }

        try mailbox.append(samples: utterance)
        require(mailbox.drain() == [utterance], "drain must return queued audio in order")
        require(mailbox.drain().isEmpty, "drain must remove completed utterances")
    }

    private static func promotedHoldBudgetIncludesPreservedSpeech() throws {
        var mailbox = DictationUtteranceMailbox(segmenter: try DictationUtteranceSegmenter(sampleRate: 8_000))
        let ordinaryBudget = mailbox.maximumBufferedSampleCount
        let heldSpeech = samples(0.02, count: 800_000)
        try mailbox.seedCapture(samples: heldSpeech)
        require(mailbox.bufferedSampleCount <= mailbox.maximumBufferedSampleCount,
                "promotion accounting must include the preserved long hold prefix")
        require(mailbox.drain() == [heldSpeech], "promotion must retain every held sample once")
        require(mailbox.maximumBufferedSampleCount == ordinaryBudget,
                "draining the held prefix must restore the ordinary continuous budget")
    }

    private static func malformedConfigurationIsRejected() throws {
        for rate in [0.0, .nan, .infinity, 384_000] {
            do {
                _ = try DictationUtteranceSegmenter(sampleRate: rate)
                require(false, "invalid or excessive input rates must be rejected")
            } catch DictationUtteranceSegmenter.ConfigurationError.invalidSampleRate {}
        }
        for pause in [0.0, -1, .nan, .infinity, 21] {
            do {
                _ = try DictationUtteranceSegmenter(sampleRate: 16_000, pauseDuration: pause)
                require(false, "invalid or excessive pause durations must be rejected")
            } catch DictationUtteranceSegmenter.ConfigurationError.invalidPauseDuration {}
        }
    }
}
