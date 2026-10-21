@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
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
    case noInputBuffers
    case unsupportedInputFormat
    case sampleBufferTooLarge
    case converterUnavailable
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputBuffers:
            return "The microphone delivered no audio. Check your input device in System Settings, then try again."
        case .alreadyCapturing:
            return "The microphone is already in use by dictation or a microphone test."
        case .inputUnavailable:
            return "No usable microphone input is available. Check your input device in System Settings."
        case .inputConfigurationChanged:
            return "The microphone changed and dictation stopped. Start dictation again."
        default:
            return nil
        }
    }
}

protocol DictationCaptureEngine: AnyObject, Sendable {
    var identity: ObjectIdentifier { get }
    var isRunning: Bool { get }
    var inputFormat: AVAudioFormat { get }
    var isInputAvailable: Bool { get }
    func matchesInputSelection(_ selection: DictationInputSelection) -> Bool
    func selectInput(_ selection: DictationInputSelection) throws -> DictationInputDevice?
    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func prepare()
    func start() throws
    func stop()
}

extension DictationCaptureEngine {
    var isInputAvailable: Bool { true }
    func matchesInputSelection(_ selection: DictationInputSelection) -> Bool { true }
    func selectInput(_ selection: DictationInputSelection) throws -> DictationInputDevice? { nil }
}

private final class SystemDictationCaptureEngine: DictationCaptureEngine, @unchecked Sendable {
    private let engine: AVAudioEngine
    private let inputNode: AVAudioInputNode
    private var selectedInput: DictationInputDevices.ResolvedInput?

    init(_ engine: AVAudioEngine) {
        self.engine = engine
        inputNode = engine.inputNode
    }

    var identity: ObjectIdentifier { ObjectIdentifier(engine) }
    var isRunning: Bool { engine.isRunning }
    var inputFormat: AVAudioFormat { inputNode.outputFormat(forBus: 0) }
    var isInputAvailable: Bool {
        guard let selectedInput else { return false }
        return matchesInputSelection(.deviceUID(selectedInput.device.id))
    }
    func matchesInputSelection(_ selection: DictationInputSelection) -> Bool {
        guard let selectedInput, let current = try? DictationInputDevices.resolve(selection) else { return false }
        return current.deviceID == selectedInput.deviceID
    }
    func selectInput(_ selection: DictationInputSelection) throws -> DictationInputDevice? {
        let input = try DictationInputDevices.resolve(selection)
        guard let unit = inputNode.audioUnit else { throw AVAudioEngineCaptureError.inputUnavailable }
        var deviceID = input.deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, size
        )
        guard status == noErr else { throw DictationInputDeviceError.selectionFailed(status) }
        var actual = AudioDeviceID(kAudioObjectUnknown)
        var actualSize = size
        let readStatus = AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &actualSize
        )
        guard readStatus == noErr, actual == deviceID else {
            throw DictationInputDeviceError.selectionFailed(readStatus)
        }
        selectedInput = input
        return input.device
    }
    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: format) { buffer, _ in receive(buffer) }
    }
    func removeTap() { inputNode.removeTap(onBus: 0) }
    func prepare() { engine.prepare() }
    func start() throws { try engine.start() }
    func stop() { engine.stop() }
}

private final class MicrophoneAuthorizationWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AVAuthorizationStatus, Error>?
    private var result: Result<AVAuthorizationStatus, Error>?

    func install(_ continuation: CheckedContinuation<AVAuthorizationStatus, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<AVAuthorizationStatus, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

actor AVAudioEngineCaptureService: DictationAudioCapturing {
    typealias LevelObserver = @Sendable (Float) -> Void

    private struct CaptureContext {
        let engine: any DictationCaptureEngine
        let accumulator: LockedMonoSampleAccumulator
        let sampleRate: Double
        let configuration: DictationCaptureConfiguration
        let inputDevice: DictationInputDevice?
    }

    private struct ContinuousCaptureContext {
        let id: UUID
        let engine: any DictationCaptureEngine
        let accumulator: LockedContinuousSampleAccumulator
        let sampleRate: Double
        let pauseDuration: TimeInterval
        let configuration: DictationCaptureConfiguration
        let inputDevice: DictationInputDevice?
        let continuation: AsyncThrowingStream<DictationAudio, Error>.Continuation
    }

    private var configuration = DictationCaptureConfiguration(
        input: .systemDefault, adaptiveSpeech: true, previewEnabled: false
    )
    private(set) var currentInputDevice: DictationInputDevice?
    private var terminalInputFailure: Error?
    private var inputDeviceObserver: DictationInputDeviceObserver?
    private var context: CaptureContext?
    private var preparedContext: CaptureContext?
    private var continuousContext: ContinuousCaptureContext?
    private var continuousPump: Task<Void, Never>?
    private var continuousStartID: UUID?
    private let authorizationStatus: @Sendable () -> AVAuthorizationStatus
    private let makeCaptureEngine: @Sendable () throws -> any DictationCaptureEngine
    private let requestAuthorization: @Sendable () async -> AVAuthorizationStatus
    private let readinessSleep: @Sendable () async throws -> Void
    private let readinessPollLimit: Int
    private var diagnosticID: UUID?
    private let levelObserver: LevelObserver
    private var configurationChangeObserver: (any NSObjectProtocol)?

    init(
        authorizationStatus: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        makeAudioEngine: @escaping @Sendable () throws -> AVAudioEngine = { AVAudioEngine() },
        requestAuthorization: @escaping @Sendable () async -> AVAuthorizationStatus = {
            await DictationMicrophonePermission.shared.requestAuthorization()
        },
        captureEngineFactory: (@Sendable () throws -> any DictationCaptureEngine)? = nil,
        readinessPollLimit: Int = 35,
        readinessSleep: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(20))
        },
        levelObserver: @escaping LevelObserver = { _ in }
    ) {
        self.authorizationStatus = authorizationStatus
        self.makeCaptureEngine = captureEngineFactory ?? { SystemDictationCaptureEngine(try makeAudioEngine()) }
        self.requestAuthorization = requestAuthorization
        self.readinessPollLimit = max(1, readinessPollLimit)
        self.readinessSleep = readinessSleep
        self.levelObserver = levelObserver
    }

    func configure(_ configuration: DictationCaptureConfiguration) async throws {
        guard context == nil, continuousContext == nil, diagnosticID == nil, continuousStartID == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
        guard self.configuration != configuration else { return }
        discardPreparedCapture()
        self.configuration = configuration
        currentInputDevice = nil
    }

    func captureSnapshot() async -> DictationCaptureSnapshot? {
        guard diagnosticID == nil, let context, context.configuration.previewEnabled,
              let snapshot = context.accumulator.previewSnapshot(), !snapshot.samples.isEmpty,
              let audio = try? Self.normalize(samples: snapshot.samples, from: context.sampleRate) else { return nil }
        return DictationCaptureSnapshot(
            totalSampleCount: snapshot.totalSampleCount,
            sourceOffset: snapshot.sourceOffset,
            audio: audio,
            isWindowed: snapshot.sourceOffset > 0
        )
    }

    func requestPermission() async throws -> Bool {
        try Task.checkCancellation()
        let waiter = MicrophoneAuthorizationWaiter()
        let status = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard waiter.install(continuation) else { return }
                Task { [requestAuthorization] in
                    waiter.finish(.success(await requestAuthorization()))
                }
            }
        } onCancel: {
            waiter.finish(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        try Self.requireAuthorization(status)
        return true
    }

    private static func requireAuthorization(_ status: AVAuthorizationStatus) throws {
        switch status {
        case .authorized: return
        case .denied: throw DictationMicrophoneAuthorizationFailure.denied
        case .restricted: throw DictationMicrophoneAuthorizationFailure.restricted
        case .notDetermined: throw DictationMicrophoneAuthorizationFailure.notDetermined
        @unknown default: throw DictationMicrophoneAuthorizationFailure.unknown(status.rawValue)
        }
    }

    private func checkAuthorization() throws {
        do {
            try Self.requireAuthorization(authorizationStatus())
        } catch {
            discardPreparedCapture()
            if let context {
                stopActiveCapture(context)
                context.accumulator.discard()
            }
            if let continuousContext {
                stopActiveContinuousCapture(continuousContext)
                continuousContext.accumulator.discard()
                continuousContext.continuation.finish(throwing: error)
            }
            throw error
        }
    }

    func prepareForCaptureIfAuthorized() async {
        observeConfigurationChangesIfNeeded()
        guard authorizationStatus() == .authorized else {
            discardPreparedCapture()
            return
        }
        guard diagnosticID == nil,
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
        guard diagnosticID == nil else { throw AVAudioEngineCaptureError.alreadyCapturing }
        try await startHeldCapture()
    }

    private func startHeldCapture() async throws {
        try Task.checkCancellation()
        try checkAuthorization()
        observeConfigurationChangesIfNeeded()
        guard context == nil, continuousContext == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
        terminalInputFailure = nil
        let wasPrepared = preparedContext != nil
        var captureContext = try takePreparedCaptureContext()
        do {
            do {
                try startPreparedCaptureContext(captureContext, startTime: ProcessInfo.processInfo.systemUptime)
            } catch {
                guard wasPrepared else { throw error }
                try Task.checkCancellation()
                captureContext = try makeCaptureContext()
                try startPreparedCaptureContext(captureContext, startTime: ProcessInfo.processInfo.systemUptime)
            }
            try await confirmHeldInput(captureContext)
        } catch {
            if let context, context.engine.identity == captureContext.engine.identity {
                stopActiveCapture(context)
                context.accumulator.discard()
            }
            throw error
        }
    }

    private func takePreparedCaptureContext() throws -> CaptureContext {
        try checkAuthorization()
        if let preparedContext {
            if preparedContext.engine.matchesInputSelection(configuration.input) {
                self.preparedContext = nil
                return preparedContext
            }
            discardPreparedCapture()
        }
        return try makeCaptureContext()
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
        try Task.checkCancellation()
        guard diagnosticID == nil else { throw AVAudioEngineCaptureError.alreadyCapturing }
        try checkAuthorization()
        observeConfigurationChangesIfNeeded()
        guard continuousContext == nil, promoting || context == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
        let existingCapture = promoting ? context : nil
        if let existingCapture, !existingCapture.engine.isRunning {
            throw AVAudioEngineCaptureError.inputConfigurationChanged
        }
        discardPreparedCapture()

        if !promoting { terminalInputFailure = nil }
        let activeConfiguration = existingCapture?.configuration ?? configuration
        let engine: any DictationCaptureEngine
        let inputDevice: DictationInputDevice?
        if let existingCapture {
            engine = existingCapture.engine
            inputDevice = existingCapture.inputDevice
        } else {
            engine = try makeCaptureEngine()
            inputDevice = try engine.selectInput(activeConfiguration.input)
        }
        let tapFormat = try Self.tapFormat(for: engine.inputFormat)
        let segmenter = try DictationUtteranceSegmenter(
            sampleRate: tapFormat.sampleRate,
            pauseDuration: pauseDuration,
            adaptiveSpeech: activeConfiguration.adaptiveSpeech
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
                engine.installTap(format: tapFormat) { buffer in
                    accumulator.append(buffer)
                }
                engine.prepare()
                try checkAuthorization()
                try engine.start()
            }
        } catch {
            if let existingCapture {
                context = nil
                existingCapture.accumulator.discard()
            }
            engine.removeTap()
            engine.stop()
            accumulator.discard()
            continuation.finish(throwing: error)
            throw error
        }

        continuousContext = ContinuousCaptureContext(
            id: id,
            engine: engine,
            accumulator: accumulator,
            sampleRate: tapFormat.sampleRate,
            pauseDuration: pauseDuration,
            configuration: activeConfiguration,
            inputDevice: inputDevice,
            continuation: continuation
        )
        currentInputDevice = inputDevice
        continuousStartID = id
        defer { if continuousStartID == id { continuousStartID = nil } }
        do {
            try await confirmContinuousInput(id: id)
        } catch {
            if let current = continuousContext, current.id == id {
                stopActiveContinuousCapture(current)
                current.accumulator.discard()
                current.continuation.finish(throwing: error)
            }
            throw error
        }
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
        guard let continuousContext else { throw terminalInputFailure ?? AVAudioEngineCaptureError.notCapturing }
        stopActiveContinuousCapture(continuousContext, prepareNext: true)
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

    private func stopActiveContinuousCapture(_ captureContext: ContinuousCaptureContext, prepareNext: Bool = false) {
        guard continuousContext?.id == captureContext.id else { return }
        continuousContext = nil
        continuousPump?.cancel()
        continuousPump = nil
        captureContext.engine.removeTap()
        captureContext.engine.stop()
        levelObserver(0)
        if prepareNext { Task { await self.prepareForCaptureIfAuthorized() } }
    }

    private static func yield(
        _ segments: [[Float]],
        to context: ContinuousCaptureContext
    ) throws {
        for samples in segments {
            let normalized = try normalize(samples: samples, from: context.sampleRate)
            let audio = DictationAudio(samples: normalized.samples, speechEvidence: .speech)
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
        preparedContext.engine.removeTap()
        preparedContext.engine.stop()
    }

    private func observeConfigurationChangesIfNeeded() {
        if inputDeviceObserver == nil {
            inputDeviceObserver = DictationInputDeviceObserver { [weak self] in
                Task { await self?.handleInputDevicesChanged() }
            }
        }
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
        if let preparedContext, preparedContext.engine.identity == engineID { discardPreparedCapture() }
        if let context, context.engine.identity == engineID {
            failActiveInput(AVAudioEngineCaptureError.inputConfigurationChanged)
        } else if let continuousContext, continuousContext.engine.identity == engineID {
            failActiveInput(AVAudioEngineCaptureError.inputConfigurationChanged)
        }
    }

    func handleInputDevicesChanged() {
        if let preparedContext, !preparedContext.engine.isInputAvailable { discardPreparedCapture() }
        if let engine = context?.engine ?? continuousContext?.engine, !engine.isInputAvailable {
            failActiveInput(DictationInputDeviceError.unavailable)
        }
    }

    private func failActiveInput(_ error: Error) {
        terminalInputFailure = error
        if let context {
            stopActiveCapture(context)
            context.accumulator.discard()
        }
        if let continuousContext {
            stopActiveContinuousCapture(continuousContext)
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish(throwing: error)
        }
    }

    private static func tapFormat(for hardwareFormat: AVAudioFormat) throws -> AVAudioFormat {
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
        try checkAuthorization()
        let engine = try makeCaptureEngine()
        let inputDevice = try engine.selectInput(configuration.input)
        let hardwareFormat = engine.inputFormat
        #if DEBUG
        let formatMilliseconds = Int(
            ((ProcessInfo.processInfo.systemUptime - startTime) * 1_000).rounded()
        )
        dictationAudioLatencyLogger.notice(
            "stage=audioFormatReady ms=\(formatMilliseconds, privacy: .public)"
        )
        #endif
        let tapFormat = try Self.tapFormat(for: hardwareFormat)

        let accumulator = LockedMonoSampleAccumulator(
            channelCount: Int(tapFormat.channelCount),
            sampleRate: tapFormat.sampleRate,
            previewEnabled: configuration.previewEnabled,
            levelObserver: levelObserver
        )
        engine.installTap(format: tapFormat) { buffer in
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
            accumulator: accumulator,
            sampleRate: tapFormat.sampleRate,
            configuration: configuration,
            inputDevice: inputDevice
        )
    }

    private func startPreparedCaptureContext(
        _ captureContext: CaptureContext,
        startTime: TimeInterval
    ) throws {
        do {
            try checkAuthorization()
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
            currentInputDevice = captureContext.inputDevice
            levelObserver(0)
        } catch {
            let engine = captureContext.engine
            engine.removeTap()
            engine.stop()
            throw error
        }
    }

    private func waitForInput(
        from engine: any DictationCaptureEngine,
        _ hasInput: @Sendable () -> Bool
    ) async throws -> Bool {
        for _ in 0..<readinessPollLimit {
            try Task.checkCancellation()
            try checkAuthorization()
            try checkActiveInput(engine)
            if hasInput() { return true }
            try await readinessSleep()
        }
        try Task.checkCancellation()
        try checkAuthorization()
        try checkActiveInput(engine)
        return hasInput()
    }

    private func checkActiveInput(_ engine: any DictationCaptureEngine) throws {
        guard context?.engine.identity == engine.identity || continuousContext?.engine.identity == engine.identity else {
            throw terminalInputFailure ?? CancellationError()
        }
        guard engine.isRunning else { throw AVAudioEngineCaptureError.inputConfigurationChanged }
    }

    private func confirmHeldInput(_ initial: CaptureContext) async throws {
        if try await waitForInput(from: initial.engine, { initial.accumulator.hasReceivedAudio() }) {
            guard context?.engine.identity == initial.engine.identity else { throw CancellationError() }
            return
        }
        guard context?.engine.identity == initial.engine.identity else { throw CancellationError() }
        guard initial.accumulator.discardIfSilent() else { return }
        self.context = nil
        initial.engine.removeTap()
        initial.engine.stop()
        let fresh = try makeCaptureContext()
        do {
            try startPreparedCaptureContext(fresh, startTime: ProcessInfo.processInfo.systemUptime)
            guard try await waitForInput(from: fresh.engine, { fresh.accumulator.hasReceivedAudio() }) else {
                throw AVAudioEngineCaptureError.noInputBuffers
            }
            guard context?.engine.identity == fresh.engine.identity else { throw CancellationError() }
        } catch {
            if context?.engine.identity == fresh.engine.identity { stopActiveCapture(fresh) }
            fresh.accumulator.discard()
            throw error
        }
    }

    private func confirmContinuousInput(id: UUID) async throws {
        guard let initial = continuousContext, initial.id == id else { throw CancellationError() }
        if try await waitForInput(from: initial.engine, { initial.accumulator.hasReceivedAudio() }) {
            guard continuousContext?.id == id else { throw CancellationError() }
            return
        }
        guard continuousContext?.id == id else { throw CancellationError() }
        guard initial.accumulator.discardIfSilent() else { return }
        initial.engine.removeTap()
        initial.engine.stop()
        continuousContext = nil
        let fresh = try makeCaptureContext()
        do {
            let accumulator = LockedContinuousSampleAccumulator(
                channelCount: Int(fresh.engine.inputFormat.channelCount),
                segmenter: try DictationUtteranceSegmenter(
                    sampleRate: fresh.sampleRate, pauseDuration: initial.pauseDuration,
                    adaptiveSpeech: initial.configuration.adaptiveSpeech
                ),
                levelObserver: levelObserver
            )
            try fresh.accumulator.promote(to: accumulator)
            try checkAuthorization()
            try fresh.engine.start()
            continuousContext = ContinuousCaptureContext(
                id: id, engine: fresh.engine, accumulator: accumulator,
                sampleRate: fresh.sampleRate, pauseDuration: initial.pauseDuration,
                configuration: initial.configuration, inputDevice: fresh.inputDevice, continuation: initial.continuation
            )
            currentInputDevice = fresh.inputDevice
            guard try await waitForInput(from: fresh.engine, { accumulator.hasReceivedAudio() }) else {
                throw AVAudioEngineCaptureError.noInputBuffers
            }
            guard continuousContext?.id == id else { throw CancellationError() }
        } catch {
            fresh.engine.removeTap()
            fresh.engine.stop()
            initial.continuation.finish(throwing: error)
            throw error
        }
    }

    func runMicrophoneDiagnostic() async throws {
        guard context == nil, continuousContext == nil, diagnosticID == nil else {
            throw AVAudioEngineCaptureError.alreadyCapturing
        }
        let id = UUID()
        diagnosticID = id
        discardPreparedCapture()
        defer { finishMicrophoneDiagnostic(id: id) }
        try await withTaskCancellationHandler {
            _ = try await requestPermission()
            guard diagnosticID == id else { throw CancellationError() }
            try await startHeldCapture()
            try await Task.sleep(for: .seconds(1))
            guard diagnosticID == id else { throw CancellationError() }
            try checkAuthorization()
            guard let context else { throw AVAudioEngineCaptureError.inputConfigurationChanged }
            try checkActiveInput(context.engine)
        } onCancel: {
            Task { await self.cancelMicrophoneDiagnostic(id: id) }
        }
    }

    func cancelMicrophoneDiagnostic() {
        guard let diagnosticID else { return }
        finishMicrophoneDiagnostic(id: diagnosticID)
    }

    private func cancelMicrophoneDiagnostic(id: UUID) {
        finishMicrophoneDiagnostic(id: id)
    }

    private func finishMicrophoneDiagnostic(id: UUID) {
        guard diagnosticID == id else { return }
        if let context {
            stopActiveCapture(context)
            context.accumulator.discard()
        }
        diagnosticID = nil
    }

    func stopCapture() async throws -> DictationAudio {
        guard let context else { throw terminalInputFailure ?? AVAudioEngineCaptureError.notCapturing }
        guard context.engine.isRunning else {
            failActiveInput(AVAudioEngineCaptureError.inputConfigurationChanged)
            throw AVAudioEngineCaptureError.inputConfigurationChanged
        }
        stopActiveCapture(context, prepareNext: true)

        let samples = context.accumulator.drain()
        #if DEBUG
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let duration = context.sampleRate > 0 ? Double(samples.count) / context.sampleRate : 0
        dictationAudioPipelineLogger.notice(
            "audioCaptured duration=\(duration, privacy: .public) samples=\(samples.count, privacy: .public) peak=\(peak, privacy: .public)"
        )
        #endif
        let gate = DictationSpeechGate.analyze(
            samples: samples, sampleRate: context.sampleRate, adaptive: context.configuration.adaptiveSpeech
        )
        let evidence: DictationSpeechEvidence = gate.hasAcceptedSpeech ? .speech :
            (gate.hasSignal ? .uncertain : .silence)
        let normalized = try Self.normalize(samples: samples, from: context.sampleRate)
        return DictationAudio(samples: normalized.samples, speechEvidence: evidence)
    }

    func cancelCapture() async {
        terminalInputFailure = nil
        if let continuousContext {
            stopActiveContinuousCapture(continuousContext)
            continuousContext.accumulator.discard()
            continuousContext.continuation.finish()
        }
        guard let context else { return }
        stopActiveCapture(context)
        context.accumulator.discard()
    }

    private func stopActiveCapture(_ context: CaptureContext, prepareNext: Bool = false) {
        self.context = nil
        context.engine.removeTap()
        context.engine.stop()
        levelObserver(0)
        if prepareNext { Task { await self.prepareForCaptureIfAuthorized() } }
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
    private let previewBuffer: DictationPreviewAudioBuffer?
    private var samples: [Float] = []
    private var continuousDestination: LockedContinuousSampleAccumulator?
    private var meter = DictationAudioLevelMeter()
    private var receivedFirstBuffer = false
    private var isAccepting = true

    init(
        channelCount: Int,
        sampleRate: Double = 16_000,
        previewEnabled: Bool = false,
        levelObserver: @escaping AVAudioEngineCaptureService.LevelObserver
    ) {
        previewBuffer = previewEnabled ? DictationPreviewAudioBuffer(sampleRate: sampleRate) : nil
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
        guard isAccepting else { lock.unlock(); return }
        if let continuousDestination {
            continuousDestination.appendMono(mono)
        } else {
            samples.append(contentsOf: mono)
            previewBuffer?.append(mono)
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
        previewBuffer?.discard()
    }

    func previewSnapshot() -> DictationPreviewAudioBuffer.Snapshot? {
        previewBuffer?.snapshot()
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
        samples.removeAll(keepingCapacity: false)
        previewBuffer?.discard()
        meter.reset()
        return true
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
        isAccepting = false
        samples.removeAll(keepingCapacity: false)
        previewBuffer?.discard()
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
