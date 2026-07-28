@preconcurrency import AVFoundation
import Dispatch
import Foundation
import os

#if DEBUG
private let dictationAudioLatencyLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "latency"
)

private let dictationAudioPipelineLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "pipeline"
)
#endif

enum AVAudioEngineCaptureError: Error, Equatable {
    case alreadyCapturing
    case notCapturing
    case inputUnavailable
    case unsupportedInputFormat
    case sampleBufferTooLarge
    case converterUnavailable
    case conversionFailed(String)
}

actor AVAudioEngineCaptureService: DictationAudioCapturing {
    typealias LevelObserver = @Sendable (Float) -> Void

    private struct CaptureContext {
        let engine: AVAudioEngine
        let inputNode: AVAudioInputNode
        let accumulator: LockedMonoSampleAccumulator
        let sampleRate: Double
    }

    private var context: CaptureContext?
    private var preparedContext: CaptureContext?
    private let levelObserver: LevelObserver

    init(levelObserver: @escaping LevelObserver = { _ in }) {
        self.levelObserver = levelObserver
    }

    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func prepareForCaptureIfAuthorized() async {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              context == nil,
              preparedContext == nil else { return }
        do {
            preparedContext = try makeCaptureContext()
        } catch {
            #if DEBUG
            dictationAudioLatencyLogger.debug(
                "stage=audioPrewarmFailed error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    func startCapture() async throws {
        guard context == nil else { throw AVAudioEngineCaptureError.alreadyCapturing }
        let startTime = ProcessInfo.processInfo.systemUptime

        let wasPrepared = preparedContext != nil
        let captureContext: CaptureContext
        if let preparedContext {
            self.preparedContext = nil
            captureContext = preparedContext
            #if DEBUG
            dictationAudioLatencyLogger.notice("stage=audioPreparedReused ms=0")
            #endif
        } else {
            captureContext = try makeCaptureContext()
        }

        do {
            try startPreparedCaptureContext(captureContext, startTime: startTime)
        } catch where wasPrepared {
            captureContext.inputNode.removeTap(onBus: 0)
            captureContext.engine.stop()
            let freshContext = try makeCaptureContext()
            try startPreparedCaptureContext(freshContext, startTime: startTime)
        }
    }

    private func makeCaptureContext() throws -> CaptureContext {
        #if DEBUG
        let startTime = ProcessInfo.processInfo.systemUptime
        #endif
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        #if DEBUG
        let formatMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
        )
        dictationAudioLatencyLogger.notice(
            "stage=audioFormatReady ms=\(formatMilliseconds, privacy: .public)"
        )
        #endif
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AVAudioEngineCaptureError.inputUnavailable
        }
        guard let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: hardwareFormat.channelCount,
            interleaved: false
        ) else {
            throw AVAudioEngineCaptureError.unsupportedInputFormat
        }

        let accumulator = LockedMonoSampleAccumulator(
            channelCount: Int(tapFormat.channelCount),
            levelObserver: levelObserver
        )
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: tapFormat) { buffer, _ in
            accumulator.append(buffer)
        }
        #if DEBUG
        let tapMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
        )
        dictationAudioLatencyLogger.notice(
            "stage=audioTapInstalled ms=\(tapMilliseconds, privacy: .public)"
        )
        #endif

        engine.prepare()
        #if DEBUG
        let prepareMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
        )
        dictationAudioLatencyLogger.notice(
            "stage=audioEnginePrepared ms=\(prepareMilliseconds, privacy: .public)"
        )
        #endif
        return CaptureContext(
            engine: engine,
            inputNode: inputNode,
            accumulator: accumulator,
            sampleRate: tapFormat.sampleRate
        )
    }

    private func startPreparedCaptureContext(
        _ captureContext: CaptureContext,
        startTime: TimeInterval
    ) throws {
        do {
            try captureContext.engine.start()
            #if DEBUG
            let engineMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
            )
            dictationAudioLatencyLogger.notice(
                "stage=audioEngineStart ms=\(engineMilliseconds, privacy: .public)"
            )
            #endif
            context = captureContext
            levelObserver(0)
        } catch {
            let inputNode = captureContext.inputNode
            let engine = captureContext.engine
            inputNode.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
    }

    func stopCapture() async throws -> DictationAudio {
        guard let context else { throw AVAudioEngineCaptureError.notCapturing }
        self.context = nil

        context.inputNode.removeTap(onBus: 0)
        context.engine.stop()
        levelObserver(0)
        Task { await self.prepareForCaptureIfAuthorized() }

        let samples = context.accumulator.drain()
        #if DEBUG
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let duration = context.sampleRate > 0 ? Double(samples.count) / context.sampleRate : 0
        dictationAudioPipelineLogger.notice(
            "audioCaptured duration=\(duration, privacy: .public) samples=\(samples.count, privacy: .public) peak=\(peak, privacy: .public)"
        )
        #endif
        return try Self.normalize(samples: samples, from: context.sampleRate)
    }

    func cancelCapture() async {
        guard let context else { return }
        self.context = nil
        context.inputNode.removeTap(onBus: 0)
        context.engine.stop()
        context.accumulator.discard()
        levelObserver(0)
        Task { await self.prepareForCaptureIfAuthorized() }
    }

    static func normalize(samples: [Float], from sourceSampleRate: Double) throws -> DictationAudio {
        guard !samples.isEmpty else { return DictationAudio(samples: []) }
        guard sourceSampleRate > 0 else { throw AVAudioEngineCaptureError.unsupportedInputFormat }
        if abs(sourceSampleRate - DictationAudio.transcriptionSampleRate) < 0.5 {
            return DictationAudio(samples: samples)
        }
        guard samples.count <= Int(UInt32.max) else {
            throw AVAudioEngineCaptureError.sampleBufferTooLarge
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ), let destinationFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: DictationAudio.transcriptionSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: destinationFormat),
           let sourceBuffer = AVAudioPCMBuffer(
               pcmFormat: sourceFormat,
               frameCapacity: AVAudioFrameCount(samples.count)
           ), let sourceData = sourceBuffer.floatChannelData?[0] else {
            throw AVAudioEngineCaptureError.converterUnavailable
        }

        sourceBuffer.frameLength = sourceBuffer.frameCapacity
        samples.withUnsafeBufferPointer { source in
            if let baseAddress = source.baseAddress {
                sourceData.update(from: baseAddress, count: source.count)
            }
        }

        let ratio = DictationAudio.transcriptionSampleRate / sourceSampleRate
        let estimatedFrames = Int(ceil(Double(samples.count) * ratio)) + 512
        guard estimatedFrames <= Int(UInt32.max),
              let destinationBuffer = AVAudioPCMBuffer(
                  pcmFormat: destinationFormat,
                  frameCapacity: AVAudioFrameCount(estimatedFrames)
              ) else {
            throw AVAudioEngineCaptureError.sampleBufferTooLarge
        }

        let inputProvider = AudioConverterInputProvider(sourceBuffer: sourceBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: destinationBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.nextBuffer(inputStatus: inputStatus)
        }

        if status == .error {
            throw AVAudioEngineCaptureError.conversionFailed(
                conversionError?.localizedDescription ?? "Unknown AVAudioConverter failure"
            )
        }
        guard let destinationData = destinationBuffer.floatChannelData?[0] else {
            throw AVAudioEngineCaptureError.conversionFailed("Converter returned no Float PCM data")
        }

        let convertedSamples = Array(
            UnsafeBufferPointer(start: destinationData, count: Int(destinationBuffer.frameLength))
        )
        return DictationAudio(samples: convertedSamples)
    }
}

private final class AudioConverterInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let sourceBuffer: AVAudioPCMBuffer
    private var didSupplySource = false

    init(sourceBuffer: AVAudioPCMBuffer) {
        self.sourceBuffer = sourceBuffer
    }

    func nextBuffer(
        inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        if didSupplySource {
            inputStatus.pointee = .endOfStream
            return nil
        }

        didSupplySource = true
        inputStatus.pointee = .haveData
        return sourceBuffer
    }
}

/// Converts microphone energy into a stable, display-ready value while keeping
/// publication below 25 Hz. The audio tap owns one instance, so no locking is
/// needed inside the meter itself.
struct DictationAudioLevelMeter {
    static let publishIntervalNanoseconds: UInt64 = 40_000_000

    private var smoothedLevel: Float = 0
    private var lastPublishTime: UInt64?

    mutating func consume(
        sumOfSquares: Double,
        peak: Float,
        sampleCount: Int,
        timestamp: UInt64
    ) -> Float? {
        guard sampleCount > 0 else { return nil }

        let rms = Float(sqrt(max(0, sumOfSquares) / Double(sampleCount)))
        let rmsLevel = Self.normalize(amplitude: rms, floorDecibels: -52)
        let peakLevel = Self.normalize(amplitude: peak, floorDecibels: -45)
        let rawLevel = max(rmsLevel, peakLevel * 0.72)

        // Fast attack keeps speech feeling immediate. The gentler release
        // prevents the bars from flickering between adjacent audio buffers.
        let smoothing: Float = rawLevel > smoothedLevel ? 0.68 : 0.22
        smoothedLevel += (rawLevel - smoothedLevel) * smoothing
        if smoothedLevel < 0.012 { smoothedLevel = 0 }

        if let lastPublishTime,
           timestamp >= lastPublishTime,
           timestamp - lastPublishTime < Self.publishIntervalNanoseconds {
            return nil
        }
        lastPublishTime = timestamp
        return min(max(smoothedLevel, 0), 1)
    }

    mutating func reset() {
        smoothedLevel = 0
        lastPublishTime = nil
    }

    private static func normalize(amplitude: Float, floorDecibels: Float) -> Float {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(max(amplitude, 0.000_000_1))
        return min(max((decibels - floorDecibels) / -floorDecibels, 0), 1)
    }
}

private final class LockedMonoSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let channelCount: Int
    private let levelObserver: AVAudioEngineCaptureService.LevelObserver
    private var samples: [Float] = []
    private var meter = DictationAudioLevelMeter()

    init(
        channelCount: Int,
        levelObserver: @escaping AVAudioEngineCaptureService.LevelObserver
    ) {
        self.channelCount = max(1, channelCount)
        self.levelObserver = levelObserver
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let availableChannels = min(channelCount, Int(buffer.format.channelCount))
        guard availableChannels > 0 else { return }

        var mono = [Float](repeating: 0, count: frameCount)
        var sumOfSquares = 0.0
        var peak: Float = 0
        let scale = 1 / Float(availableChannels)
        for frameIndex in 0..<frameCount {
            var sample: Float = 0
            for channelIndex in 0..<availableChannels {
                sample += channels[channelIndex][frameIndex]
            }
            sample *= scale
            mono[frameIndex] = sample
            sumOfSquares += Double(sample) * Double(sample)
            peak = max(peak, abs(sample))
        }

        lock.lock()
        samples.append(contentsOf: mono)
        let level = meter.consume(
            sumOfSquares: sumOfSquares,
            peak: peak,
            sampleCount: frameCount,
            timestamp: DispatchTime.now().uptimeNanoseconds
        )
        lock.unlock()
        if let level { levelObserver(level) }
    }

    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: false)
        return result
    }

    func discard() {
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        meter.reset()
        lock.unlock()
    }
}
