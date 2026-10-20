import AVFoundation
import Foundation

private func assertEqual(_ actual: Int, _ expected: Int, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

private final class EngineFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    func makeEngine() throws -> AVAudioEngine {
        lock.lock()
        attempts += 1
        lock.unlock()
        throw AVAudioEngineCaptureError.inputUnavailable
    }
}

@main
private struct DictationAudioConfigurationRegression {
    static func main() async {
        await deniedStartDoesNotCreateAudioEngine()
        await configurationChangesDoNotPrepareIdleAudio()
        await unauthorizedPreparationDoesNotCreateAudioEngine()
        print("Dictation audio configuration regression tests passed")
    }

    private static func deniedStartDoesNotCreateAudioEngine() async {
        let factory = EngineFactoryProbe()
        let capture = AVAudioEngineCaptureService(
            authorizationStatus: { .denied },
            makeAudioEngine: { try factory.makeEngine() }
        )
        do { try await capture.startCapture() } catch {}
        assertEqual(factory.count, 0, "Denied capture must not construct an engine")
    }

    private static func configurationChangesDoNotPrepareIdleAudio() async {
        let factory = EngineFactoryProbe()
        let capture = AVAudioEngineCaptureService(
            authorizationStatus: { .authorized },
            makeAudioEngine: { try factory.makeEngine() }
        )
        await capture.prepareForCaptureIfAuthorized()
        assertEqual(factory.count, 1, "Explicit preparation attempts engine creation")

        let unrelatedEngine = NSObject()
        for _ in 0..<8 {
            await capture.handleConfigurationChange(engineID: ObjectIdentifier(unrelatedEngine))
        }
        assertEqual(factory.count, 1, "Repeated unrelated or stale configuration events keep idle audio untouched")

        await capture.prepareForCaptureIfAuthorized()
        assertEqual(factory.count, 2, "Explicit preparation remains available after configuration events")
    }

    private static func unauthorizedPreparationDoesNotCreateAudioEngine() async {
        for status: AVAuthorizationStatus in [.notDetermined, .denied, .restricted] {
            let factory = EngineFactoryProbe()
            let capture = AVAudioEngineCaptureService(
                authorizationStatus: { status },
                makeAudioEngine: { try factory.makeEngine() }
            )
            await capture.prepareForCaptureIfAuthorized()
            assertEqual(factory.count, 0, "Preparation without authorization avoids engine creation")
        }
    }
}
