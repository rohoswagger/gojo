import AVFoundation
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private func wave(_ amplitude: Float, _ count: Int) -> [Float] {
    (0..<count).map { $0.isMultiple(of: 2) ? amplitude : -amplitude }
}

@main
struct DictationAudioExperienceRegression {
    static func main() async throws {
        try gateUsesSustainedEvidence()
        try gateAdaptsAndFreezes()
        try adaptationPreservesBaselineSpeech()
        try callbackBoundariesPreserveQuietSpeech()
        try speechLobesAccumulateWithinAnUtterance()
        try forcedSplitCannotCreditLaterClicks()
        previewBoundsAndSnapshots()
        try accumulatorRetainsFinalAudio()
        try normalizationPreservesTails()
        try await heldCapturePreservesFaintSignal()
        try await engineSelectionAndRecovery()
        try await protocolConfigurationReachesCapture()
        try await protocolConfigurationControlsAdaptation()
        try await selectionFailureAndDeviceLoss()
        try await hotplugRetiresPreparedAndContinuousCapture()
        try await hotplugInterruptsStartupAndDiagnostic()
        print("Dictation audio experience regression passed")
    }

    private static func gateUsesSustainedEvidence() throws {
        let silence = DictationSpeechGate.analyze(samples: wave(0, 16_000), sampleRate: 16_000)
        require(!silence.hasAcceptedSpeech && !silence.hasSignal, "zero audio must report silence")
        let immediate = DictationSpeechGate.analyze(samples: wave(0.005, 1_920), sampleRate: 16_000)
        require(immediate.hasAcceptedSpeech, "120 ms speech must start without calibration silence")
        let short = DictationSpeechGate.analyze(samples: wave(0.4, 1_760), sampleRate: 16_000)
        require(!short.hasAcceptedSpeech && short.longestSpeechSampleCount == 1_760,
                "110 ms impulse must not satisfy sustained speech")
        let clicks = (0..<20).flatMap { _ in wave(0.2, 160) + wave(0, 640) }
        let clickGate = DictationSpeechGate.analyze(samples: clicks, sampleRate: 16_000)
        require(!clickGate.hasAcceptedSpeech && clickGate.longestSpeechSampleCount == 160,
                "isolated clicks must not accumulate speech credit")
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        _ = segmenter.append(samples: Array(clicks.prefix(8_000)))
        require(segmenter.finish().isEmpty, "continuous capture must reject less than 120 ms of cumulative signal")
        let invalid = DictationSpeechGate.analyze(samples: [.nan, .infinity], sampleRate: 16_000)
        require(invalid.containsInvalidSamples && !invalid.hasAcceptedSpeech, "nonfinite samples must fail admission")
    }

    private static func gateAdaptsAndFreezes() throws {
        var gate = DictationSpeechGate(sampleRate: 16_000)
        for _ in 0..<400 { _ = gate.consume(frame: wave(0.0005, 160)) }
        require(gate.noiseHistoryCount == 200, "noise history must stop at 200 frames")
        require(gate.threshold == 0.0015, "quiet baseline must permit the bounded lower threshold")
        let quietThreshold = gate.threshold
        for _ in 0..<12 { _ = gate.consume(frame: wave(0.002, 160)) }
        require(gate.hasAcceptedSpeech && gate.threshold == quietThreshold,
                "quiet speech must pass and freeze the threshold during its candidate run")
        for _ in 0..<200 { _ = gate.consume(frame: wave(0.0014, 160)) }
        require(gate.threshold == quietThreshold, "accepted utterance must freeze noise adaptation through its pause")

        var baseline = DictationSpeechGate(sampleRate: 16_000)
        for _ in 0..<200 { _ = baseline.consume(frame: wave(0.002, 160)) }
        require(!baseline.hasAcceptedSpeech,
                "observed low stationary energy must not establish speech")
        for _ in 0..<12 { _ = baseline.consume(frame: wave(0.008, 160)) }
        require(baseline.hasAcceptedSpeech, "speech above the established baseline must pass")
        let legacy = DictationSpeechGate.analyze(samples: wave(0, 3_200) + wave(0.002, 1_920), sampleRate: 16_000, adaptive: false)
        require(!legacy.hasAcceptedSpeech, "disabled adaptation must keep the legacy energy threshold")
    }

    private static func adaptationPreservesBaselineSpeech() throws {
        let input = wave(0.002, 16_000) + wave(0.0045, 4_800) + wave(0, 14_400)
        var fixed = try DictationUtteranceSegmenter(sampleRate: 16_000, adaptiveSpeech: false)
        var adaptive = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let fixedOutput = fixed.append(samples: input) + fixed.finish()
        let adaptiveOutput = adaptive.append(samples: input) + adaptive.finish()
        require(fixedOutput.count == 1 && adaptiveOutput == fixedOutput,
                "adaptation must preserve speech admitted by the fixed threshold over quieter background")
    }

    private static func callbackBoundariesPreserveQuietSpeech() throws {
        let input = wave(0, 6_400) + wave(0.002, 1_920) + wave(0, 14_400)
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        var output: [[Float]] = []
        var offset = 0
        let chunkSizes = [1, 271, 2_047, 333, 97]
        var iteration = 0
        while offset < input.count {
            let end = min(input.count, offset + chunkSizes[iteration % chunkSizes.count])
            output += segmenter.append(samples: Array(input[offset..<end]))
            offset = end
            iteration += 1
        }
        output += segmenter.finish()
        require(output == [wave(0, 3_200) + wave(0.002, 1_920) + wave(0, 14_400)],
                "irregular callbacks must preserve 200 ms preroll, short quiet speech, and the full pause tail")
    }

    private static func forcedSplitCannotCreditLaterClicks() throws {
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let longSpeech = wave(0.02, 320_000)
        require(segmenter.append(samples: longSpeech) == [longSpeech], "a forced split must retain its full accepted speech")
        require(segmenter.append(samples: wave(0, 14_400)).isEmpty, "silence after a forced split must expire continuation credit")
        _ = segmenter.append(samples: wave(0.2, 160))
        require(segmenter.finish().isEmpty, "a later isolated click must not inherit accepted speech from a completed split")
    }

    private static func speechLobesAccumulateWithinAnUtterance() throws {
        let input = wave(0.005, 960) + wave(0, 320) + wave(0.005, 960)
        for adaptiveSpeech in [false, true] {
            var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000, adaptiveSpeech: adaptiveSpeech)
            let output = segmenter.append(samples: input) + segmenter.finish()
            require(output == [input], "two 60 ms speech lobes must survive a 20 ms dip within the same utterance")
        }
        var segmenter = try DictationUtteranceSegmenter(sampleRate: 16_000)
        let short = wave(0.005, 800) + wave(0, 320) + wave(0.005, 800)
        _ = segmenter.append(samples: short)
        require(segmenter.finish().isEmpty, "100 ms of cumulative speech must remain below the utterance minimum")
    }

    private static func previewBoundsAndSnapshots() {
        let buffer = DictationPreviewAudioBuffer(sampleRate: 8_000)
        buffer.append([])
        for offset in stride(from: 0, to: 104_000, by: 8_000) {
            buffer.append((offset..<(offset + 8_000)).map(Float.init))
        }
        let snapshot = buffer.snapshot()
        require(snapshot.totalSampleCount == 104_000 && snapshot.sourceOffset == 8_000,
                "12 second preview must expose the original source timeline")
        require(snapshot.samples == (8_000..<104_000).map(Float.init), "preview must contain the exact bounded suffix")
        buffer.append([104_000])
        require(snapshot.samples.first == 8_000 && snapshot.samples.last == 103_999,
                "appending must leave an older snapshot unchanged")
        require(buffer.snapshot().sourceOffset == 8_001, "the next snapshot must clip the first retained chunk")

        let tiny = DictationPreviewAudioBuffer(sampleRate: 16_000)
        for value in 0..<1_100 { tiny.append([Float(value)]) }
        require(tiny.retainedChunkCount == 1_024, "preview metadata must retain at most 1024 chunks")
        require(tiny.snapshot() == .init(samples: (76..<1_100).map(Float.init), totalSampleCount: 1_100, sourceOffset: 76),
                "metadata cap must report the available source offset")
        let oversized = DictationPreviewAudioBuffer(sampleRate: 8_000)
        oversized.append((0..<200_000).map(Float.init))
        require(oversized.snapshot() == .init(samples: (104_000..<200_000).map(Float.init), totalSampleCount: 200_000, sourceOffset: 104_000),
                "an oversized callback must retain only the latest 12 seconds")
    }

    private static func accumulatorRetainsFinalAudio() throws {
        let accumulator = LockedMonoSampleAccumulator(channelCount: 1, sampleRate: 16_000, previewEnabled: true, levelObserver: { _ in })
        let input = wave(0.02, 208_000)
        let buffer = pcm(input)
        accumulator.append(buffer)
        let preview = accumulator.previewSnapshot()!
        require(preview.totalSampleCount == 208_000 && preview.sourceOffset == 16_000,
                "held preview must report its untruncated source count")
        require(preview.samples == Array(input.suffix(192_000)), "held preview must use the bounded mailbox")
        require(accumulator.drain() == input, "snapshot reads must leave every final held sample intact")
        let disabled = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        disabled.append(pcm([0.1, 0.2]))
        require(disabled.previewSnapshot() == nil && disabled.drain() == [0.1, 0.2],
                "disabled preview must preserve capture without a mailbox")
    }

    private static func normalizationPreservesTails() throws {
        for rate in [44_100.0, 48_000] {
            let input = wave(0.02, Int(rate) - 4_800) + Array(repeating: Float(0.5), count: 4_800)
            let preview = DictationPreviewAudioBuffer(sampleRate: rate)
            preview.append(input)
            let raw = preview.snapshot()
            let normalized = try AVAudioEngineCaptureService.normalize(samples: raw.samples, from: rate)
            require(raw.totalSampleCount == Int(rate) && raw.sourceOffset == 0,
                    "preview counters must retain their source-rate timeline")
            require(normalized.sampleRate == 16_000 && normalized.samples.count == 16_000,
                    "44.1 and 48 kHz conversion must retain the full one second output")
            require(normalized.samples.suffix(160).allSatisfy { $0 > 0.4 },
                    "conversion must preserve the final 10 ms of audio")
        }
    }

    private static func pcm(_ samples: [Float]) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        for (index, sample) in samples.enumerated() { buffer.floatChannelData![0][index] = sample }
        return buffer
    }

    private static func heldCapturePreservesFaintSignal() async throws {
        for amplitude: Float in [0, 0.00001, 0.0001, 0.0004] {
            let input = wave(amplitude, 16_000)
            let system = AudioExperienceSystem(initialEngineSuppliesAudio: true, startupAudio: input)
            let capture = system.capture()
            try await capture.startCapture()
            let audio = try await capture.stopCapture()
            require(audio.samples == input, "held capture must preserve faint samples without amplification")
            require(audio.speechEvidence == (amplitude == 0 ? .silence : .uncertain),
                    "only digital silence may bypass held recognition")
            require(DictationAudioPolicy().shouldTranscribe(audio) == (amplitude != 0),
                    "faint nonzero held input must reach recognition")
        }
    }

    private static func engineSelectionAndRecovery() async throws {
        let system = AudioExperienceSystem()
        let capture = system.capture()
        try await capture.configure(.init(input: .deviceUID("studio"), previewEnabled: true))
        await capture.prepareForCaptureIfAuthorized()
        require(system.engines[0].events == ["select:studio", "format", "tap", "prepare"],
                "prewarm must select the requested microphone before format, tap, and prepare")
        try await capture.startCapture()
        require(system.engines.count == 2, "silent prepared engine must rebuild once")
        require(system.engines[1].events.prefix(5) == ["select:studio", "format", "tap", "prepare", "start"],
                "recovery must select the same frozen UID before touching the replacement engine")
        let device = await capture.currentInputDevice
        require(device == .init(id: "studio", name: "Studio microphone"), "service must expose the actual selected input")
        let snapshot = await capture.captureSnapshot()
        require(snapshot?.totalSampleCount == 3_200 && snapshot?.sourceOffset == 0,
                "active held preview must contain the real first callback")
        do {
            try await capture.configure(.init())
            require(false, "active capture must reject configuration changes")
        } catch AVAudioEngineCaptureError.alreadyCapturing {}
        _ = try await capture.promoteCaptureToContinuous(pauseDuration: 0.9)
        require(system.engines[1].events.filter { $0.hasPrefix("select:") } == ["select:studio"],
                "held promotion must keep its existing pinned input")
        let promotedSnapshot = await capture.captureSnapshot()
        require(promotedSnapshot == nil, "continuous capture must not expose held preview data")
        await capture.cancelCapture()
        try await capture.configure(.init(input: .deviceUID("headset")))
        _ = try await capture.startContinuousCapture(pauseDuration: 0.9)
        require(system.engines.last!.events.prefix(4) == ["select:headset", "format", "tap", "prepare"],
                "direct continuous capture must select its requested UID first")
        await capture.cancelCapture()
    }

    private static func protocolConfigurationReachesCapture() async throws {
        let system = AudioExperienceSystem(initialEngineSuppliesAudio: true)
        let concrete = system.capture()
        let capture: any DictationAudioCapturing = concrete
        try await capture.configure(.init(input: .deviceUID("headset"), previewEnabled: true))
        try await capture.startCapture()
        require(system.engines[0].events.prefix(4) == ["select:headset", "format", "tap", "prepare"],
                "protocol configuration must select the requested UID before capture")
        let inputDevice = await concrete.currentInputDevice
        require(inputDevice?.id == "headset", "protocol configuration must expose the selected input")
        let snapshot = await capture.captureSnapshot()
        require(snapshot?.audio.samples == Array(repeating: Float(0.02), count: 3_200),
                "protocol configuration and snapshot dispatch must preserve enabled preview audio")
        await capture.cancelCapture()
        try await capture.configure(.init(input: .deviceUID("studio"), previewEnabled: false))
        try await capture.startCapture()
        let disabledSnapshot = await capture.captureSnapshot()
        require(disabledSnapshot == nil, "protocol reconfiguration must disable preview")
        await capture.cancelCapture()
    }

    private static func protocolConfigurationControlsAdaptation() async throws {
        let input = wave(0, 3_200) + wave(0.002, 3_200) + wave(0, 14_400)
        for adaptiveSpeech in [false, true] {
            let system = AudioExperienceSystem(initialEngineSuppliesAudio: true, startupAudio: input)
            let capture: any DictationAudioCapturing = system.capture()
            try await capture.configure(.init(input: .deviceUID("studio"), adaptiveSpeech: adaptiveSpeech))
            let stream = try await capture.startContinuousCapture(pauseDuration: 0.9)
            try await capture.stopContinuousCapture()
            var output: [[Float]] = []
            for try await audio in stream { output.append(audio.samples) }
            require(output == (adaptiveSpeech ? [input] : []),
                    "protocol configuration must apply the requested adaptive speech policy")
        }
    }

    private static func selectionFailureAndDeviceLoss() async throws {
        let system = AudioExperienceSystem()
        let capture = system.capture()
        try await capture.configure(.init(input: .deviceUID("missing")))
        do {
            try await capture.startCapture()
            require(false, "a missing explicit UID must fail")
        } catch DictationInputDeviceError.unavailable {}
        require(system.engines[0].events == ["select:missing"], "selection failure must occur before input format or tap access")
        try await capture.configure(.init(input: .deviceUID("studio")))
        try await capture.startCapture()
        let active = system.engines.last!
        await capture.handleConfigurationChange(engineID: active.identity)
        require(!active.isRunning && active.events.suffix(2) == ["remove", "stop"],
                "device configuration change must retire an active held engine")
        do {
            _ = try await capture.stopCapture()
            require(false, "stop after input loss must preserve the clear terminal failure")
        } catch AVAudioEngineCaptureError.inputConfigurationChanged {}
        try await capture.startCapture()
        require(system.engines.last!.events.first == "select:studio", "retry must resolve the same selection on a fresh engine")
        await capture.cancelCapture()
    }
    private static func hotplugRetiresPreparedAndContinuousCapture() async throws {
        let system = AudioExperienceSystem(initialEngineSuppliesAudio: true)
        let capture = system.capture()
        try await capture.configure(.init(input: .deviceUID("studio")))
        await capture.prepareForCaptureIfAuthorized()
        system.engines[0].available = false
        await capture.handleInputDevicesChanged()
        require(system.engines[0].events.suffix(2) == ["remove", "stop"],
                "disconnect must invalidate the prepared engine")
        try await capture.startCapture()
        require(system.engines.count == 2 && system.engines[1].events.first == "select:studio",
                "a start after prepared input loss must select the UID on a new engine")
        await capture.cancelCapture()
        let stream = try await capture.startContinuousCapture(pauseDuration: 0.9)
        let active = system.engines.last!
        active.available = false
        await capture.handleInputDevicesChanged()
        var iterator = stream.makeAsyncIterator()
        do {
            _ = try await iterator.next()
            require(false, "continuous stream must fail when its pinned input disappears")
        } catch DictationInputDeviceError.unavailable {}
        require(!active.isRunning, "continuous device loss must stop the engine")
        do {
            try await capture.stopContinuousCapture()
            require(false, "continuous stop must preserve the device loss failure")
        } catch DictationInputDeviceError.unavailable {}
    }

    private static func hotplugInterruptsStartupAndDiagnostic() async throws {
        let system = AudioExperienceSystem()
        let gate = AudioExperienceReadinessGate()
        let capture = system.capture(readinessSleep: { await gate.wait() })
        try await capture.configure(.init(input: .deviceUID("studio")))
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival()
        system.engines[0].available = false
        await capture.handleInputDevicesChanged()
        await gate.release()
        do {
            try await start.value
            require(false, "device loss during first-buffer startup must remain a device error")
        } catch DictationInputDeviceError.unavailable {}
        require(!system.engines[0].isRunning, "startup loss must stop the held engine")

        let diagnosticSystem = AudioExperienceSystem()
        let diagnosticGate = AudioExperienceReadinessGate()
        let diagnosticCapture = diagnosticSystem.capture(readinessSleep: { await diagnosticGate.wait() })
        let diagnostic = Task { try await diagnosticCapture.runMicrophoneDiagnostic() }
        await diagnosticGate.waitForArrival()
        diagnosticSystem.engines[0].available = false
        await diagnosticCapture.handleInputDevicesChanged()
        await diagnosticGate.release()
        do {
            try await diagnostic.value
            require(false, "diagnostic must report the lost selected microphone")
        } catch DictationInputDeviceError.unavailable {}
        try await diagnosticCapture.configure(.init(input: .deviceUID("headset")))
        try await diagnosticCapture.startCapture()
        require(diagnosticSystem.engines[1].events.first == "select:headset",
                "failed diagnostic must release ownership for another selected input")
        await diagnosticCapture.cancelCapture()
    }

}

private final class AudioExperienceSystem: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AudioExperienceEngine] = []
    private let initialEngineSuppliesAudio: Bool
    private let startupAudio: [Float]
    init(initialEngineSuppliesAudio: Bool = false, startupAudio: [Float] = Array(repeating: 0.02, count: 3_200)) {
        self.initialEngineSuppliesAudio = initialEngineSuppliesAudio
        self.startupAudio = startupAudio
    }
    var engines: [AudioExperienceEngine] { lock.withLock { storage } }

    func capture(
        readinessSleep: @escaping @Sendable () async throws -> Void = {}
    ) -> AVAudioEngineCaptureService {
        AVAudioEngineCaptureService(
            authorizationStatus: { .authorized }, requestAuthorization: { .authorized },
            captureEngineFactory: { self.makeEngine() }, readinessPollLimit: 1,
            readinessSleep: readinessSleep
        )
    }

    private func makeEngine() -> AudioExperienceEngine {
        lock.withLock {
            let engine = AudioExperienceEngine(
                suppliesAudio: initialEngineSuppliesAudio || !storage.isEmpty,
                startupAudio: startupAudio
            )
            storage.append(engine)
            return engine
        }
    }
}

private final class AudioExperienceEngine: DictationCaptureEngine, @unchecked Sendable {
    private let lock = NSLock()
    private let suppliesAudio: Bool
    private let startupAudio: [Float]
    private var receiver: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var running = false
    private var inputAvailable = true
    private var recordedEvents: [String] = []
    var available: Bool {
        get { lock.withLock { inputAvailable } }
        set { lock.withLock { inputAvailable = newValue } }
    }
    var isInputAvailable: Bool { available }
    func matchesInputSelection(_ selection: DictationInputSelection) -> Bool { available }
    var events: [String] { lock.withLock { recordedEvents } }
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var isRunning: Bool { lock.withLock { running } }
    var inputFormat: AVAudioFormat {
        lock.withLock { recordedEvents.append("format") }
        return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    init(suppliesAudio: Bool, startupAudio: [Float]) {
        self.suppliesAudio = suppliesAudio
        self.startupAudio = startupAudio
    }
    func selectInput(_ selection: DictationInputSelection) throws -> DictationInputDevice? {
        let uid: String
        switch selection { case .systemDefault: uid = "default"; case .deviceUID(let value): uid = value }
        lock.withLock { recordedEvents.append("select:\(uid)") }
        guard uid != "missing" else { throw DictationInputDeviceError.unavailable }
        return .init(id: uid, name: "Studio microphone")
    }
    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.withLock { recordedEvents.append("tap"); receiver = receive }
    }
    func removeTap() { lock.withLock { recordedEvents.append("remove"); receiver = nil } }
    func prepare() { lock.withLock { recordedEvents.append("prepare") } }
    func start() throws {
        let callback = lock.withLock { running = true; recordedEvents.append("start"); return receiver }
        if suppliesAudio {
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(startupAudio.count))!
            buffer.frameLength = buffer.frameCapacity
            for (index, sample) in startupAudio.enumerated() { buffer.floatChannelData![0][index] = sample }
            callback?(buffer)
        }
    }
    func stop() { lock.withLock { running = false; recordedEvents.append("stop") } }
}

private actor AudioExperienceReadinessGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var arrived = false
    func wait() async {
        arrived = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitForArrival() async {
        while !arrived { await Task.yield() }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
