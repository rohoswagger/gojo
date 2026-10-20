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
        try await heldStartWaitsForSilentBuffer()
        try await missingBuffersFailAfterOneRecovery()
        try await replacementBufferRecoversContinuousCapture()
        try await revocationPreventsPreparedStartAndRecovery()
        try await cancelledStartupReleasesItsEngine()
        try await configurationFailureDuringStartupIsVisible()
        try await diagnosticReservesAndReleasesTheSameCaptureActor()
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
    func stop() { lock.withLock { running = false; stopCount += 1 } }
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
