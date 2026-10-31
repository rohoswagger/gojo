import AVFoundation
import Foundation
import FluidAudio

@main struct BarkCleanInferenceLive {
    static func main() async throws {
        let model = BarkSpeechEngine.clean(try await loadManager())
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: CommandLine.arguments[2]))
        precondition(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let text = try await model.transcribe(samples)
        print("Clean transcript: \(text)")
        fflush(stdout)
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        precondition(words.contains("meeting") && words.contains("tomorrow") && words.contains("notebook"))
        precondition(!words.contains("um") && !words.contains("uh"), "Clean must remove spoken fillers without an LLM")
        precondition(!text.contains("<unk>"), "special tokens must not reach the transcript")
        let long = try await model.transcribe(Array(repeating: samples, count: 4).flatMap { $0 })
        print("Long Clean transcript: \(long)")
        precondition(long.lowercased().components(separatedBy: "notebook").count - 1 == 4)
        await model.cleanup()
        print("Bark Clean real inference passed without an LLM")
    }

    private static func loadManager() async throws -> AsrManager {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        return AsrManager(models: try BarkSpeechEngine.loadCleanModels(from: folder))
    }
}
