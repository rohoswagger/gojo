import AVFoundation
import Foundation

@main struct BarkInferenceLive {
    static func main() throws {
        let model = try BarkSpeechRuntime(folder: URL(fileURLWithPath: CommandLine.arguments[1]))
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]))
        precondition(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let short = try model.transcribe(samples)
        print("Short transcript: \(short)")
        fflush(stdout)
        precondition(short.lowercased().contains("meeting is tomorrow at ten")
                     || short.lowercased().contains("meeting is tomorrow at 10"))
        precondition(short.lowercased().contains("bring the blue notebook"))
        let silence = try model.transcribe([Float](repeating: 0, count: 16_000))
        precondition(silence.isEmpty, "silence must not invent words")
        let repeated = Array(repeating: samples + [Float](repeating: 0, count: 8_000), count: 4).flatMap { $0 }
        precondition(repeated.count > 236_000)
        let long = try model.transcribe(repeated)
        print("Long transcript: \(long)")
        precondition(long.lowercased().components(separatedBy: "blue notebook").count - 1 == 4,
                     "segmentation must preserve every repeated sentence")
        print("Bark real inference passed without an LLM")
    }
}
