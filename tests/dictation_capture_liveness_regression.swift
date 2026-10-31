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
    static func main() async throws {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            fputs("Capture liveness regression timed out\n", stderr)
            exit(1)
        }
        defer { timeout.cancel() }
        try defaultInputKeepsTheEngineManagedDevice()
        try explicitInputIsBoundAndFailuresRemainVisible()
        try await delayedConfigurationNotificationDoesNotStopHealthyCapture()
        try await heldStartWaitsForSilentBuffer()
        try await missingBuffersFailAfterOneRecovery()
        try await replacementBufferRecoversContinuousCapture()
        try await revocationPreventsPreparedStartAndRecovery()
        try await cancelledStartupReleasesItsEngine()
        try await configurationFailureDuringStartupIsVisible()
        try await diagnosticReservesAndReleasesTheSameCaptureActor()
        try await continuousOverflowPreservesAllAcceptedPhrases()
        try await stoppedHeldEnginePreservesAcceptedAudio()
        try await stoppedContinuousEnginePreservesAcceptedAudio()
        try await sameInputRecoveryPreservesAcceptedIntervals()
        try await cancelDuringRecoveryCannotRestartMicrophone()
        try await recoveryStopFailureBlocksReplacement()
        try await unresolvedStopBlocksNewAdmission()
        try stoppedTapCannotAppendAfterSealing()
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

private final class CaptureEngineStub: DictationCaptureEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var receiver: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var oldReceiver: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var running = false
    private var startCount = 0
    private var stopCount = 0
    var refusesStop = false
    var isInputAvailable = true
    var inputFormat: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)! }
    var identity: ObjectIdentifier { ObjectIdentifier(self) }
    var isRunning: Bool { lock.withLock { running } }
    var starts: Int { lock.withLock { startCount } }
    var stops: Int { lock.withLock { stopCount } }

    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.withLock { receiver = receive }
    }
    func removeTap() {
        lock.withLock { oldReceiver = receiver; receiver = nil }
    }
    func prepare() {}
    func start() throws { lock.withLock { running = true; startCount += 1 } }
    func stop() { lock.withLock { if !refusesStop { running = false }; stopCount += 1 } }
    func emit(stale: Bool = false, amplitude: Float = 0) {
        let callback = lock.withLock { stale ? oldReceiver : receiver }
        let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 320)!
        buffer.frameLength = 320
        buffer.floatChannelData![0].initialize(repeating: amplitude, count: 320)
        callback?(buffer)
    }
}

private final class CaptureSystemStub: @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: AVAuthorizationStatus = .authorized
    private var engines: [CaptureEngineStub] = []
    var status: AVAuthorizationStatus {
        get { lock.withLock { currentStatus } }
        set { lock.withLock { currentStatus = newValue } }
    }
    var count: Int { lock.withLock { engines.count } }
    func engine(_ index: Int) -> CaptureEngineStub { lock.withLock { engines[index] } }
    func makeEngine() -> any DictationCaptureEngine {
        lock.withLock {
            let engine = CaptureEngineStub()
            engines.append(engine)
            return engine
        }
    }
    func capture(gate: CaptureReadinessGate, polls: Int = 1) -> AVAudioEngineCaptureService {
        AVAudioEngineCaptureService(
            authorizationStatus: { self.status }, requestAuthorization: { self.status },
            captureEngineFactory: { self.makeEngine() }, readinessPollLimit: polls,
            readinessSleep: { try await gate.sleep() }
        )
    }
}

private actor CaptureReadinessGate {
    private var waiter: (UUID, CheckedContinuation<Void, Error>)?
    private var arrivals = 0

    func sleep() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                arrivals += 1
                waiter = (id, continuation)
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }
    private func cancel(id: UUID) {
        guard waiter?.0 == id else { return }
        let continuation = waiter?.1
        waiter = nil
        continuation?.resume(throwing: CancellationError())
    }
    func advance() {
        let continuation = waiter?.1
        waiter = nil
        continuation?.resume()
    }
    func waitForArrival(_ count: Int) async {
        while arrivals < count { await Task.yield() }
    }
}

private actor CaptureCompletion {
    var finished = false
    func finish() { finished = true }
}

extension DictationCaptureLivenessRegression {
    private static func defaultInputKeepsTheEngineManagedDevice() throws {
        var boundDevices: [UInt32] = []
        let selected = DictationInputDevices.ResolvedInput(
            deviceID: 42, device: .init(id: "default-mic", name: "Default microphone")
        )
        let engine = SystemDictationCaptureEngine(
            AVAudioEngine(), resolveInput: { _ in selected },
            bindInput: { boundDevices.append($0) }
        )
        let device = try engine.selectInput(.systemDefault)
        require(device == selected.device, "default selection must expose the actual microphone")
        require(engine.matchesInputSelection(.systemDefault), "default selection must retain input identity")
        require(boundDevices.isEmpty, "system default must preserve the engine-managed device without rebinding hardware")
    }

    private static func explicitInputIsBoundAndFailuresRemainVisible() throws {
        var boundDevices: [UInt32] = []
        let selected = DictationInputDevices.ResolvedInput(
            deviceID: 42, device: .init(id: "studio", name: "Studio microphone")
        )
        let engine = SystemDictationCaptureEngine(
            AVAudioEngine(), resolveInput: { _ in selected },
            bindInput: { boundDevices.append($0) }
        )
        let device = try engine.selectInput(.deviceUID("studio"))
        require(device == selected.device,
                "explicit selection must expose the bound microphone")
        require(boundDevices == [42], "explicit selection must still bind the requested device")
        let failing = SystemDictationCaptureEngine(
            AVAudioEngine(), resolveInput: { _ in selected },
            bindInput: { _ in throw DictationInputDeviceError.selectionFailed(-1) }
        )
        do {
            _ = try failing.selectInput(.deviceUID("studio"))
            require(false, "explicit selection failure must remain visible")
        } catch DictationInputDeviceError.selectionFailed(-1) {}
    }

    private static func delayedConfigurationNotificationDoesNotStopHealthyCapture() async throws {
        for continuous in [false, true] {
            let system = CaptureSystemStub()
            let gate = CaptureReadinessGate()
            let capture = system.capture(gate: gate)
            let start = Task { () -> AsyncThrowingStream<DictationAudio, Error>? in
                if continuous { return try await capture.startContinuousCapture(pauseDuration: 0.9) }
                try await capture.startCapture()
                return nil
            }
            await gate.waitForArrival(1)
            let engine = system.engine(0)
            await capture.handleConfigurationChange(engineID: engine.identity)
            require(engine.isRunning, "a delayed setup notification must not stop a running microphone during startup")
            engine.emit(amplitude: 0.1)
            await gate.advance()
            let stream = try await start.value
            await capture.handleConfigurationChange(engineID: engine.identity)
            require(engine.isRunning, "a redundant configuration notification must preserve a healthy recording")
            require(system.count == 1 && engine.starts == 1, "a healthy notification must not rebuild or restart capture")
            for _ in 0..<10 { engine.emit(amplitude: 0.1) }
            if continuous {
                try await capture.stopContinuousCapture()
                var received = false
                for try await audio in stream! { received = received || !audio.samples.isEmpty }
                require(received, "continuous audio must survive benign configuration notifications")
            } else {
                let audio = try await capture.stopCapture()
                require(!audio.samples.isEmpty, "held audio must survive benign configuration notifications")
            }
            await capture.cancelCapture()
        }
    }

    private static func heldStartWaitsForSilentBuffer() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let completion = CaptureCompletion()
        let start = Task {
            try await capture.startCapture()
            await completion.finish()
        }
        while system.count == 0 { await Task.yield() }
        while system.engine(0).starts == 0 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        let prematurelyFinished = await completion.finished
        require(!prematurelyFinished, "engine.start without a delivered buffer must not report listening")
        await gate.waitForArrival(1)
        system.engine(0).emit()
        await gate.advance()
        try await start.value
        await capture.cancelCapture()
        require(system.engine(0).stops > 0, "canceling a proven capture must stop its engine")
    }

    private static func missingBuffersFailAfterOneRecovery() async throws {
        for continuous in [false, true] {
            let system = CaptureSystemStub()
            let gate = CaptureReadinessGate()
            let capture = system.capture(gate: gate)
            let start = Task {
                if continuous { _ = try await capture.startContinuousCapture(pauseDuration: 0.9) }
                else { try await capture.startCapture() }
            }
            await gate.waitForArrival(1)
            await gate.advance()
            await gate.waitForArrival(2)
            require(system.count == 2, "missing buffers must make exactly one fresh-engine recovery")
            system.engine(0).emit(stale: true)
            await gate.advance()
            do {
                try await start.value
                require(false, "an old engine's late buffer must not make the replacement ready")
            } catch let error as AVAudioEngineCaptureError {
                require(error == .noInputBuffers, "two silent deadlines must produce a visible no-buffer failure")
            }
            require(system.count == 2, "failure cleanup must not create a third engine")
            require(!system.engine(0).isRunning && !system.engine(1).isRunning, "no-buffer failure must stop both engines")
        }
    }

    private static func replacementBufferRecoversContinuousCapture() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startContinuousCapture(pauseDuration: 0.9) }
        await gate.waitForArrival(1)
        await gate.advance()
        await gate.waitForArrival(2)
        system.engine(1).emit()
        await gate.advance()
        let stream = try await start.value
        require(system.engine(1).isRunning, "a real silent buffer must permit the one replacement to listen")
        await capture.cancelCapture()
        for try await _ in stream {}
    }

    private static func revocationPreventsPreparedStartAndRecovery() async throws {
        let preparedSystem = CaptureSystemStub()
        let preparedGate = CaptureReadinessGate()
        let prepared = preparedSystem.capture(gate: preparedGate)
        await prepared.prepareForCaptureIfAuthorized()
        preparedSystem.status = .restricted
        do {
            try await prepared.startCapture()
            require(false, "revoking a prewarmed microphone must block capture")
        } catch let error as DictationMicrophoneAuthorizationFailure {
            require(error == .restricted, "prewarm revocation must retain the actual authorization reason")
        }
        require(preparedSystem.count == 1 && preparedSystem.engine(0).starts == 0,
                "revoked prepared audio must not start or construct a replacement")

        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        system.status = .denied
        await gate.advance()
        do {
            try await start.value
            require(false, "revocation before liveness recovery must fail")
        } catch let error as DictationMicrophoneAuthorizationFailure {
            require(error == .denied, "liveness recovery must retain denial")
        }
        require(system.count == 1 && !system.engine(0).isRunning,
                "revocation must stop audio and prevent a liveness rebuild")
    }

    private static func cancelledStartupReleasesItsEngine() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        start.cancel()
        do {
            try await start.value
            require(false, "canceled first-buffer confirmation must not report success")
        } catch is CancellationError {}
        require(!system.engine(0).isRunning, "canceled first-buffer confirmation must stop the engine")
        require(system.count == 1, "canceled startup must not prewarm a competing engine")
    }

    private static func configurationFailureDuringStartupIsVisible() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startContinuousCapture(pauseDuration: 0.9) }
        await gate.waitForArrival(1)
        system.engine(0).stop()
        await capture.handleConfigurationChange(engineID: system.engine(0).identity)
        await gate.advance()
        do {
            _ = try await start.value
            require(false, "a stopped input engine cannot finish startup")
        } catch let error as AVAudioEngineCaptureError {
            require(error == .inputConfigurationChanged,
                    "a configuration failure during preparation must remain visible instead of becoming cancellation")
        }
        require(system.count == 1, "a stopped input engine must not be rebuilt as healthy")
    }

    private static func diagnosticReservesAndReleasesTheSameCaptureActor() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let diagnostic = Task { try await capture.runMicrophoneDiagnostic() }
        await gate.waitForArrival(1)
        do {
            try await capture.startCapture()
            require(false, "dictation must not start a competing engine during a diagnostic")
        } catch let error as AVAudioEngineCaptureError {
            require(error == .alreadyCapturing, "diagnostic ownership must explain microphone occupancy")
        }
        diagnostic.cancel()
        do { try await diagnostic.value } catch is CancellationError {}
        require(system.count == 1 && !system.engine(0).isRunning,
                "canceling the diagnostic must discard audio and release the only engine")
    }
}

extension DictationCaptureLivenessRegression {
    private static func stoppedHeldEnginePreservesAcceptedAudio() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        let engine = system.engine(0)
        for _ in 0..<10 { engine.emit(amplitude: 0.1) }
        await gate.advance()
        try await start.value
        engine.stop()
        let audio = try await capture.stopCapture()
        require(audio.samples == Array(repeating: Float(0.1), count: 3_200),
                "an unexpected stopped engine must still return every accepted held sample")
    }

    private static func stoppedContinuousEnginePreservesAcceptedAudio() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startContinuousCapture(pauseDuration: 0.9) }
        await gate.waitForArrival(1)
        let engine = system.engine(0)
        for _ in 0..<10 { engine.emit(amplitude: 0.1) }
        await gate.advance()
        let stream = try await start.value
        engine.stop()
        engine.isInputAvailable = false
        await capture.handleInputDevicesChanged()
        await capture.handleConfigurationChange(engineID: engine.identity)
        var samples: [Float] = []
        do {
            for try await audio in stream { samples += audio.samples }
        } catch {}
        require(samples == Array(repeating: Float(0.1), count: 3_200),
                "an input failure must seal and yield accepted continuous speech before its error")
    }

    private static func unresolvedStopBlocksNewAdmission() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        let engine = system.engine(0)
        engine.emit()
        await gate.advance()
        try await start.value
        engine.refusesStop = true
        await capture.cancelCapture()
        let second = Task { try await capture.startCapture() }
        for _ in 0..<100 { await Task.yield() }
        require(system.count == 1, "an unacknowledged engine stop must block creation of a second engine")
        second.cancel()
        _ = try? await second.value
        engine.refusesStop = false
        await capture.cancelCapture()
    }

    private static func stoppedTapCannotAppendAfterSealing() throws {
        let held = LockedMonoSampleAccumulator(channelCount: 1, levelObserver: { _ in })
        held.append(buffer(0.1))
        let first = held.drain()
        held.append(buffer(0.2))
        require(first == Array(repeating: Float(0.1), count: 3_200) && held.drain().isEmpty,
                "sealing held capture must retire its tap before a stale callback can append")
    }
}

extension DictationCaptureLivenessRegression {
    private static func sameInputRecoveryPreservesAcceptedIntervals() async throws {
        for continuous in [false, true] {
            let system = CaptureSystemStub()
            let gate = CaptureReadinessGate()
            let capture = system.capture(gate: gate)
            let start = Task { () -> AsyncThrowingStream<DictationAudio, Error>? in
                if continuous { return try await capture.startContinuousCapture(pauseDuration: 0.9) }
                try await capture.startCapture()
                return nil
            }
            await gate.waitForArrival(1)
            let old = system.engine(0)
            for _ in 0..<10 { old.emit(amplitude: 0.1) }
            await gate.advance()
            let stream = try await start.value
            old.stop()
            let recovery = Task { await capture.handleConfigurationChange(engineID: old.identity) }
            await gate.waitForArrival(2)
            require(system.count == 1 && !old.isRunning,
                    "same-input recovery must stop the old engine before backoff and replacement")
            old.emit(stale: true, amplitude: 0.9)
            await gate.advance()
            await gate.waitForArrival(3)
            let fresh = system.engine(1)
            for _ in 0..<10 { fresh.emit(amplitude: 0.2) }
            await gate.advance()
            await recovery.value
            old.emit(stale: true, amplitude: 0.9)
            var received: [Float] = []
            if continuous {
                try await capture.stopContinuousCapture()
                for try await audio in stream! { received += audio.samples }
            } else {
                received = try await capture.stopCapture().samples
            }
            require(received == Array(repeating: Float(0.1), count: 3_200) + Array(repeating: Float(0.2), count: 3_200),
                    "sequential epochs must retain accepted old/new speech once and reject stale tap callbacks")
            await capture.cancelCapture()
        }
    }

    private static func cancelDuringRecoveryCannotRestartMicrophone() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        let old = system.engine(0)
        old.emit()
        await gate.advance()
        try await start.value
        old.stop()
        let recovery = Task { await capture.handleConfigurationChange(engineID: old.identity) }
        await gate.waitForArrival(2)
        await capture.cancelCapture()
        await gate.advance()
        await recovery.value
        require(system.count == 1 && !old.isRunning, "Cancel during recovery backoff must revoke restart intent")
    }

    private static func recoveryStopFailureBlocksReplacement() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startCapture() }
        await gate.waitForArrival(1)
        let old = system.engine(0)
        old.emit()
        await gate.advance()
        try await start.value
        old.refusesStop = true
        await capture.cancelCapture()
        let stopBlocked = await capture.captureIsQuiescent()
        require(!stopBlocked, "a canceled engine that still runs must report nonquiescent cleanup")
        do {
            try await capture.startCapture()
            require(false, "a still-running retired engine must deny admission")
        } catch AVAudioEngineCaptureError.cleanupBlocked {}
        require(system.count == 1, "epoch fencing must not stand in for physical stop acknowledgement")
        old.refusesStop = false
        await capture.cancelCapture()
        let stopped = await capture.captureIsQuiescent()
        require(stopped, "positive physical stop acknowledgement must release the quiescence barrier")
    }
}

extension DictationCaptureLivenessRegression {
    private static func continuousOverflowPreservesAllAcceptedPhrases() async throws {
        let system = CaptureSystemStub()
        let gate = CaptureReadinessGate()
        let capture = system.capture(gate: gate)
        let start = Task { try await capture.startContinuousCapture(pauseDuration: 0.9) }
        await gate.waitForArrival(1)
        let engine = system.engine(0)
        engine.emit()
        await gate.advance()
        let stream = try await start.value
        for _ in 0..<4 {
            for _ in 0..<10 { engine.emit(amplitude: 0.1) }
            for _ in 0..<45 { engine.emit() }
        }
        while engine.isRunning { await Task.yield() }
        var speechSamples = 0
        do {
            for try await audio in stream {
                speechSamples += audio.samples.filter { $0 == 0.1 }.count
            }
            require(false, "capture high water must report its pause reason")
        } catch DictationContinuousCaptureError.bufferOverflow {}
        require(speechSamples == 12_800,
                "mailbox high water must preserve all four accepted phrases through the bounded stream")
        require(!engine.isRunning, "high water must stop physical capture before returning retained speech")
    }
}
