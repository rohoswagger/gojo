import AVFoundation
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct DictationCaptureLivenessRegression {
    static func main() throws {
        try microphoneSilenceStillProvesLiveness()
        try promotionPreservesLivenessAndAudio()
        try promotionBeforeFirstBufferWaitsForAudio()
        try silentRecoveryCannotDiscardReceivedAudio()
        try silentRecoveryRetiresTheOldAccumulator()
        print("Dictation capture liveness regression passed")
    }

    private static func makeContinuous() throws -> LockedContinuousSampleAccumulator {
        LockedContinuousSampleAccumulator(
            channelCount: 1,
            segmenter: try DictationUtteranceSegmenter(sampleRate: 16_000, pauseDuration: 0.9),
            levelObserver: { _ in }
        )
    }

    private static func buffer(_ amplitude: Float, count: Int = 3_200) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        buffer.floatChannelData![0].initialize(repeating: amplitude, count: count)
        return buffer
    }

    private static func microphoneSilenceStillProvesLiveness() throws {
        let held = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        let continuous = try makeContinuous()
        require(!held.hasReceivedAudio(), "held capture must initially wait for its first buffer")
        require(!continuous.hasReceivedAudio(), "continuous capture must initially wait for its first buffer")
        held.append(buffer(0))
        continuous.append(buffer(0))
        require(held.hasReceivedAudio(), "a silent held buffer must prove that the tap is alive")
        require(continuous.hasReceivedAudio(), "a silent continuous buffer must prove that the tap is alive")
        require(!continuous.discardIfSilent(), "hardware silence must not trigger a capture rebuild")
    }

    private static func promotionPreservesLivenessAndAudio() throws {
        let held = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        let continuous = try makeContinuous()
        held.append(buffer(0.1))
        try held.promote(to: continuous)
        require(continuous.hasReceivedAudio(), "promoted held samples must retain the first-buffer signal")
        held.append(buffer(0.2))
        let captured = try continuous.finish()
        require(captured == [Array(repeating: Float(0.1), count: 3_200) + Array(repeating: Float(0.2), count: 3_200)],
                "promotion must preserve held samples and route later buffers in order")
    }

    private static func promotionBeforeFirstBufferWaitsForAudio() throws {
        let held = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        let continuous = try makeContinuous()
        try held.promote(to: continuous)
        require(!continuous.hasReceivedAudio(), "an empty promotion must remain eligible for liveness recovery")
        held.append(buffer(0))
        require(continuous.hasReceivedAudio(), "the first forwarded buffer must prove promoted capture liveness")
    }

    private static func silentRecoveryCannotDiscardReceivedAudio() throws {
        let continuous = try makeContinuous()
        continuous.appendMono(Array(repeating: 0.1, count: 3_200))
        require(!continuous.discardIfSilent(), "recovery must preserve audio that arrives after the watchdog check")
        let captured = try continuous.finish()
        require(captured == [Array(repeating: Float(0.1), count: 3_200)],
                "declining a silent rebuild must retain the exact received speech")
    }

    private static func silentRecoveryRetiresTheOldAccumulator() throws {
        let continuous = try makeContinuous()
        continuous.appendMono([])
        require(!continuous.hasReceivedAudio(), "an empty forwarding operation must not suppress recovery")
        require(continuous.discardIfSilent(), "an accumulator without input buffers must allow one rebuild")
        continuous.append(buffer(0.1))
        continuous.appendMono(Array(repeating: 0.2, count: 3_200))
        require(!continuous.hasReceivedAudio(), "the retired tap must not regain ownership after recovery")
        let captured = try continuous.finish()
        require(captured.isEmpty, "the retired tap must not enqueue audio into the replacement stream")
    }
}
