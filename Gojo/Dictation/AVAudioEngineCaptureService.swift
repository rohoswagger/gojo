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

enum AVAudioEngineCaptureError: Error, Equatable, LocalizedError {
    case alreadyCapturing
    case notCapturing
    case inputUnavailable
    case inputConfigurationChanged
    case unsupportedInputFormat
    case sampleBufferTooLarge
    case converterUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .inputConfigurationChanged:
            return "The microphone changed and dictation stopped. Start dictation again."
        default:
            return nil
        }
    }
}

actor AVAudioEngineCaptureService: DictationAudioCapturing {
    typealias LevelObserver = @Sendable (Float) -> Void

    private struct CaptureContext {
        let engine: AVAudioEngine
        let inputNode: AVAudioInputNode
        let accumulator: LockedMonoSampleAccumulator
        let sampleRate: Double
    }

    private struct ContinuousCaptureContext {
        let id: UUID
        let engine: AVAudioEngine
        let inputNode: AVAudioInputNode
        let accumulator: LockedContinuousSampleAccumulator
        let sampleRate: Double
        let pauseDuration: TimeInterval
        let continuation: AsyncThrowingStream<DictationAudio, Error>.Continuation
    }

    private var context: CaptureContext?
    private var preparedContext: CaptureContext?
    private var continuousContext: ContinuousCaptureContext?
    private var continuousPump: Task<Void, Never>?
    private let authorizationStatus: @Sendable () -> AVAuthorizationStatus
    private let makeAudioEngine: @Sendable () throws -> AVAudioEngine
    private let levelObserver: LevelObserver
    private var livenessWatchdog: Task<Void, Never>?
    private var configurationChangeObserver: (any NSObjectProtocol)?

    init(
        authorizationStatus: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        makeAudioEngine: @escaping @Sendable () throws -> AVAudioEngine = { AVAudioEngine() },
        levelObserver: @escaping LevelObserver = { _ in }
    ) {
        self.authorizationStatus = authorizationStatus
        self.makeAudioEngine = makeAudioEngine
        self.levelObserver = levelObserver
    }

    func requestPermission() async -> Bool {
        switch authorizationStatus() {
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
        observeConfigurationChangesIfNeeded()
        guard authorizationStatus() == .authorized,
              context == nil,
              continuousContext == nil,
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
        observeConfigurationChangesIfNeeded()
        guard context == nil, continuousContext == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
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

    func startContinuousCapture(
        pauseDuration: TimeInterval
    ) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        try await makeContinuousCapture(pauseDuration: pauseDuration, promoting: false)
    }

    func promoteCaptureToContinuous(pauseDuration: TimeInterval) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        guard context != nil else { throw AVAudioEngineCaptureError.notCapturing }
        return try await makeContinuousCapture(pauseDuration: pauseDuration, promoting: true)
    }

    private func makeContinuousCapture(pauseDuration: TimeInterval, promoting: Bool) async throws -> AsyncThrowingStream<DictationAudio, Error> {
        observeConfigurationChangesIfNeeded()
        guard continuousContext == nil, promoting || context == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
        let existingCapture = promoting ? context : nil
        if let existingCapture, !existingCapture.engine.isRunning {
            throw AVAudioEngineCaptureError.inputConfigurationChanged
        }
        discardPreparedCapture()

        let engine = try existingCapture?.engine ?? makeAudioEngine()
        let inputNode = existingCapture?.inputNode ?? engine.inputNode
        let tapFormat = try Self.tapFormat(for: inputNode)
        let segmenter = try DictationUtteranceSegmenter(
            sampleRate: tapFormat.sampleRate,
            pauseDuration: pauseDuration
        )
        let accumulator = LockedContinuousSampleAccumulator(
            channelCount: Int(tapFormat.channelCount),
            segmenter: segmenter,
            levelObserver: levelObserver
        )
        let (stream, continuation) = AsyncThrowingStream<DictationAudio, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(3)
        )
        let id = UUID()
        do {
            if let existingCapture {
                try existingCapture.accumulator.promote(to: accumulator)
                context = nil
            } else {
                inputNode.installTap(onBus: 0, bufferSize: 2_048, format: tapFormat) { buffer, _ in
                    accumulator.append(buffer)
                }
                engine.prepare()
                try engine.start()
            }
        } catch {
            if let existingCapture {
                context = nil
                livenessWatchdog?.cancel()
                livenessWatchdog = nil
                existingCapture.accumulator.discard()
            }
            inputNode.removeTap(onBus: 0)
            engine.stop()
            accumulator.discard()
            continuation.finish(throwing: error)
            throw error
        }

        continuousContext = ContinuousCaptureContext(
            id: id,
            engine: engine,
            inputNode: inputNode,
            accumulator: accumulator,
            sampleRate: tapFormat.sampleRate,
            pauseDuration: pauseDuration,
            continuation: continuation
        )
        startLivenessWatchdog(engineID: ObjectIdentifier(engine))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.terminateContinuousCapture(id: id) }
        }
        continuousPump = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(40))
                } catch {
                    return
                }
                guard let self else { return }
                await self.drainContinuousCapture(id: id)
            }
        }
        levelObserver(0)
        return stream
    }

    func stopContinuousCapture() async throws {
        guard let continuousContext else { throw AVAudioEngineCaptureError.notCapturing }
        stopActiveContinuousCapture(continuousContext)
        do {
            let segments = try continuousContext.accumulator.finish()
            try Self.yield(segments, to: continuousContext)
            continuousContext.continuation.finish()
        } catch {
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish(throwing: error)
            throw error
        }
    }

    private func drainContinuousCapture(id: UUID) {
        guard let continuousContext, continuousContext.id == id else { return }
        do {
            let segments = try continuousContext.accumulator.drain()
            try Self.yield(segments, to: continuousContext)
        } catch {
            stopActiveContinuousCapture(continuousContext)
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish(throwing: error)
        }
    }

    private func terminateContinuousCapture(id: UUID) {
        guard let continuousContext, continuousContext.id == id else { return }
        stopActiveContinuousCapture(continuousContext)
        continuousContext.accumulator.discard()
        continuousContext.continuation.finish()
    }

    private func stopActiveContinuousCapture(_ captureContext: ContinuousCaptureContext) {
        guard continuousContext?.id == captureContext.id else { return }
        livenessWatchdog?.cancel()
        livenessWatchdog = nil
        continuousContext = nil
        continuousPump?.cancel()
        continuousPump = nil
        captureContext.inputNode.removeTap(onBus: 0)
        captureContext.engine.stop()
        levelObserver(0)
        Task { await self.prepareForCaptureIfAuthorized() }
    }

    private static func yield(
        _ segments: [[Float]],
        to context: ContinuousCaptureContext
    ) throws {
        for samples in segments {
            let audio = try normalize(samples: samples, from: context.sampleRate)
            #if DEBUG
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            let duration = Double(samples.count) / context.sampleRate
            dictationAudioPipelineLogger.notice(
                "audioCaptured duration=\(duration, privacy: .public) samples=\(samples.count, privacy: .public) peak=\(peak, privacy: .public)"
            )
            #endif
            switch context.continuation.yield(audio) {
            case .enqueued:
                break
            case .dropped:
                throw DictationContinuousCaptureError.bufferOverflow
            case .terminated:
                throw CancellationError()
            @unknown default:
                throw DictationContinuousCaptureError.bufferOverflow
            }
        }
    }

    func discardPreparedCapture() {
        guard let preparedContext else { return }
        self.preparedContext = nil
        preparedContext.inputNode.removeTap(onBus: 0)
        preparedContext.engine.stop()
    }

    private func observeConfigurationChangesIfNeeded() {
        guard configurationChangeObserver == nil else { return }
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let engine = notification.object as? AVAudioEngine else { return }
            let engineID = ObjectIdentifier(engine)
            Task { [weak self] in
                await self?.handleConfigurationChange(engineID: engineID)
            }
        }
    }

    func handleConfigurationChange(engineID: ObjectIdentifier) async {
        if let preparedContext, ObjectIdentifier(preparedContext.engine) == engineID {
            discardPreparedCapture()
        }
        if let continuousContext,
           ObjectIdentifier(continuousContext.engine) == engineID,
           !continuousContext.engine.isRunning {
            stopActiveContinuousCapture(continuousContext)
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish(
                throwing: AVAudioEngineCaptureError.inputConfigurationChanged
            )
        }
    }

    private static func tapFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate.isFinite,
              (8_000...192_000).contains(hardwareFormat.sampleRate),
              (1...32).contains(hardwareFormat.channelCount) else {
            throw AVAudioEngineCaptureError.inputUnavailable
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardwareFormat.sampleRate,
            channels: hardwareFormat.channelCount,
            interleaved: false
        ) else {
            throw AVAudioEngineCaptureError.unsupportedInputFormat
        }
        return format
    }

    private func makeCaptureContext() throws -> CaptureContext {
        #if DEBUG
        let startTime = ProcessInfo.processInfo.systemUptime
        #endif
        let engine = try makeAudioEngine()
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
            startLivenessWatchdog(engineID: ObjectIdentifier(captureContext.engine))
        } catch {
            let inputNode = captureContext.inputNode
            let engine = captureContext.engine
            inputNode.removeTap(onBus: 0)
            engine.stop()
            throw error
        }
    }

    /// After sleep/wake a stale engine can start successfully yet deliver no
    /// input buffers, so a silent tap after 700ms triggers one rebuild
    /// against the current audio device.
    private func startLivenessWatchdog(engineID: ObjectIdentifier) {
        livenessWatchdog?.cancel()
        livenessWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.rebuildCaptureIfSilent(engineID: engineID)
        }
    }

    private func rebuildCaptureIfSilent(engineID: ObjectIdentifier) {
        if let continuousContext,
           ObjectIdentifier(continuousContext.engine) == engineID,
           !continuousContext.accumulator.hasReceivedAudio() {
            rebuildContinuousCapture(continuousContext)
            return
        }
        guard let context,
              ObjectIdentifier(context.engine) == engineID,
              !context.accumulator.hasReceivedAudio() else { return }
        self.context = nil
        context.inputNode.removeTap(onBus: 0)
        context.engine.stop()
        do {
            let freshContext = try makeCaptureContext()
            try freshContext.engine.start()
            self.context = freshContext
            #if DEBUG
            dictationAudioLatencyLogger.notice("stage=audioLivenessRebuild")
            #endif
        } catch {
            #if DEBUG
            dictationAudioLatencyLogger.debug(
                "stage=audioLivenessRebuildFailed error=\(String(describing: error), privacy: .public)"
            )
            #endif
        }
    }

    private func rebuildContinuousCapture(_ captureContext: ContinuousCaptureContext) {
        var freshCapture: CaptureContext?
        do {
            let freshContext = try makeCaptureContext()
            freshCapture = freshContext
            let segmenter = try DictationUtteranceSegmenter(
                sampleRate: freshContext.sampleRate,
                pauseDuration: captureContext.pauseDuration
            )
            let accumulator = LockedContinuousSampleAccumulator(
                channelCount: Int(freshContext.inputNode.outputFormat(forBus: 0).channelCount),
                segmenter: segmenter,
                levelObserver: levelObserver
            )
            try freshContext.accumulator.promote(to: accumulator)
            guard captureContext.accumulator.discardIfSilent() else {
                freshContext.inputNode.removeTap(onBus: 0)
                freshContext.engine.stop()
                return
            }
            captureContext.engine.stop()
            try freshContext.engine.start()
            captureContext.inputNode.removeTap(onBus: 0)
            continuousContext = ContinuousCaptureContext(
                id: captureContext.id,
                engine: freshContext.engine,
                inputNode: freshContext.inputNode,
                accumulator: accumulator,
                sampleRate: freshContext.sampleRate,
                pauseDuration: captureContext.pauseDuration,
                continuation: captureContext.continuation
            )
            #if DEBUG
            dictationAudioLatencyLogger.notice("stage=audioLivenessRebuild")
            #endif
        } catch {
            freshCapture?.inputNode.removeTap(onBus: 0)
            freshCapture?.engine.stop()
            stopActiveContinuousCapture(captureContext)
            captureContext.accumulator.discard()
            captureContext.continuation.finish(throwing: error)
        }
    }

    func stopCapture() async throws -> DictationAudio {
        guard let context else { throw AVAudioEngineCaptureError.notCapturing }
        stopActiveCapture(context)

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
        if let continuousContext {
            stopActiveContinuousCapture(continuousContext)
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish()
        }
        guard let context else { return }
        stopActiveCapture(context)
        context.accumulator.discard()
    }

    private func stopActiveCapture(_ context: CaptureContext) {
        livenessWatchdog?.cancel()
        livenessWatchdog = nil
        self.context = nil
        context.inputNode.removeTap(onBus: 0)
        context.engine.stop()
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

final class LockedMonoSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let channelCount: Int
    private let levelObserver: AVAudioEngineCaptureService.LevelObserver
    private var samples: [Float] = []
    private var continuousDestination: LockedContinuousSampleAccumulator?
    private var meter = DictationAudioLevelMeter()
    private var receivedFirstBuffer = false

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
        if let continuousDestination {
            continuousDestination.appendMono(mono)
        } else {
            samples.append(contentsOf: mono)
        }
        receivedFirstBuffer = true
        let level = meter.consume(
            sumOfSquares: sumOfSquares,
            peak: peak,
            sampleCount: frameCount,
            timestamp: DispatchTime.now().uptimeNanoseconds
        )
        lock.unlock()
        if let level { levelObserver(level) }
    }

    func promote(to destination: LockedContinuousSampleAccumulator) throws {
        lock.lock()
        defer { lock.unlock() }
        try destination.seed(samples)
        samples.removeAll(keepingCapacity: false)
        continuousDestination = destination
    }

    func hasReceivedAudio() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedFirstBuffer
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

final class LockedContinuousSampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let channelCount: Int
    private let levelObserver: AVAudioEngineCaptureService.LevelObserver
    private var mailbox: DictationUtteranceMailbox
    private var meter = DictationAudioLevelMeter()
    private var isAccepting = true
    private var failure: Error?
    private var receivedFirstBuffer = false

    init(
        channelCount: Int,
        segmenter: DictationUtteranceSegmenter,
        levelObserver: @escaping AVAudioEngineCaptureService.LevelObserver
    ) {
        self.channelCount = channelCount
        mailbox = DictationUtteranceMailbox(segmenter: segmenter)
        self.levelObserver = levelObserver
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard isAccepting else {
            lock.unlock()
            return
        }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            lock.unlock()
            return
        }
        guard frameCount <= 16_384, let channels = buffer.floatChannelData else {
            fail(AVAudioEngineCaptureError.sampleBufferTooLarge)
            lock.unlock()
            return
        }
        let availableChannels = min(channelCount, Int(buffer.format.channelCount))
        guard availableChannels > 0 else {
            fail(AVAudioEngineCaptureError.unsupportedInputFormat)
            lock.unlock()
            return
        }

        var mono = [Float](repeating: 0, count: frameCount)
        var sumOfSquares = 0.0
        var peak: Float = 0
        let scale = 1 / Float(availableChannels)
        for frameIndex in 0..<frameCount {
            var sample: Float = 0
            for channelIndex in 0..<availableChannels {
                sample += channels[channelIndex][frameIndex] * scale
            }
            guard sample.isFinite else {
                fail(AVAudioEngineCaptureError.unsupportedInputFormat)
                lock.unlock()
                return
            }
            mono[frameIndex] = sample
            sumOfSquares += Double(sample) * Double(sample)
            peak = max(peak, abs(sample))
        }

        do {
            try mailbox.append(samples: mono)
        } catch {
            fail(DictationContinuousCaptureError.bufferOverflow)
        }
        receivedFirstBuffer = true
        let level = meter.consume(
            sumOfSquares: sumOfSquares,
            peak: peak,
            sampleCount: frameCount,
            timestamp: DispatchTime.now().uptimeNanoseconds
        )
        lock.unlock()
        if let level { levelObserver(level) }
    }

    func seed(_ samples: [Float]) throws {
        lock.lock()
        defer { lock.unlock() }
        try mailbox.seedCapture(samples: samples)
        if !samples.isEmpty { receivedFirstBuffer = true }
    }

    func appendMono(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard isAccepting else { return }
        if !samples.isEmpty { receivedFirstBuffer = true }
        do {
            try mailbox.append(samples: samples)
        } catch {
            fail(DictationContinuousCaptureError.bufferOverflow)
        }
    }

    func hasReceivedAudio() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedFirstBuffer
    }

    func discardIfSilent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !receivedFirstBuffer else { return false }
        isAccepting = false
        mailbox.discard()
        meter.reset()
        return true
    }

    func drain() throws -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        if let failure { throw failure }
        return mailbox.drain()
    }

    func finish() throws -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        isAccepting = false
        if let failure { throw failure }
        do {
            return try mailbox.finish()
        } catch {
            throw DictationContinuousCaptureError.bufferOverflow
        }
    }

    func discard() {
        lock.lock()
        isAccepting = false
        mailbox.discard()
        meter.reset()
        lock.unlock()
    }

    private func fail(_ error: Error) {
        isAccepting = false
        failure = error
        mailbox.discard()
    }
}
