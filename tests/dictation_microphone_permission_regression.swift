import AVFoundation
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@MainActor
private final class MicrophoneAuthorizationStub {
    var status: AVAuthorizationStatus
    private(set) var requestCount = 0
    private var pendingRequest: CheckedContinuation<Bool, Never>?
    private var requestStarted: CheckedContinuation<Void, Never>?

    init(status: AVAuthorizationStatus) {
        self.status = status
    }

    func makePermission() -> DictationMicrophonePermission {
        DictationMicrophonePermission(
            authorizationStatus: { self.status },
            requestAccess: {
                self.requestCount += 1
                return await withCheckedContinuation { continuation in
                    self.pendingRequest = continuation
                    self.requestStarted?.resume()
                    self.requestStarted = nil
                }
            }
        )
    }

    func waitForRequest() async {
        if pendingRequest != nil { return }
        await withCheckedContinuation { requestStarted = $0 }
    }

    func resolve(with status: AVAuthorizationStatus) {
        self.status = status
        let request = pendingRequest
        pendingRequest = nil
        request?.resume(returning: status == .authorized)
    }
}

@main
struct DictationMicrophonePermissionRegression {
    @MainActor
    static func main() async {
        let timeout = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            fputs("Microphone permission regression timed out waiting for a request to finish\n", stderr)
            exit(1)
        }
        defer { timeout.cancel() }

        await settingsAndCaptureShareOneDecision()
        await captureCancellationDoesNotCancelTheSharedDecision()
        await concurrentWaitersRemainPending()
        await firstEntryRequestsAndCompletionUpdatesStatus()
        await grantedPermissionSkipsThePrompt()
        await refusedPermissionsRemainAvailableForSettingsRecovery()
        await leavingTheTabKeepsOneRequestUntilCompletion()
        await cancelledEntryDoesNotStartAPrompt()
        activationRefreshReadsSystemSettingsChanges()
        print("Dictation microphone permission regression passed")
    }

    @MainActor
    private static func settingsAndCaptureShareOneDecision() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let capture = AVAudioEngineCaptureService(
            authorizationStatus: { .notDetermined },
            requestAuthorization: { await permission.requestAuthorization() }
        )
        let settings = Task { await permission.requestAuthorization() }
        await system.waitForRequest()
        var captureFinished = false
        let dictation = Task { () -> DictationMicrophoneAuthorizationFailure? in
            defer { captureFinished = true }
            do { _ = try await capture.requestPermission(); return nil }
            catch { return error as? DictationMicrophoneAuthorizationFailure }
        }
        for _ in 0..<10 { await Task.yield() }
        require(!captureFinished, "capture must share Settings' unresolved OS decision")
        require(system.requestCount == 1, "Settings and capture must request access exactly once")
        system.resolve(with: .restricted)
        let settingsStatus = await settings.value
        let captureFailure = await dictation.value
        require(settingsStatus == .restricted && captureFailure == .restricted,
                "Settings and capture must both retain the actual restricted result")
    }

    @MainActor
    private static func captureCancellationDoesNotCancelTheSharedDecision() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let capture = AVAudioEngineCaptureService(
            authorizationStatus: { .notDetermined },
            requestAuthorization: { await permission.requestAuthorization() }
        )
        var cancellationReturned = false
        let dictation = Task {
            defer { cancellationReturned = true }
            return try await capture.requestPermission()
        }
        await system.waitForRequest()
        dictation.cancel()
        for _ in 0..<100 { await Task.yield() }
        require(cancellationReturned, "canceled capture must finish without waiting for the OS prompt")
        let settings = Task { await permission.requestAuthorization() }
        system.resolve(with: .authorized)
        do {
            _ = try await dictation.value
            require(false, "a canceled capture must reject a late microphone grant")
        } catch is CancellationError {} catch {
            require(false, "capture cancellation must remain cancellation")
        }
        let status = await settings.value
        require(status == .authorized && permission.status == .authorized,
                "the shared owner must still publish a grant after capture cancellation")
        require(system.requestCount == 1 && !permission.isRequesting,
                "cancellation must neither duplicate the prompt nor leave it pending")
    }

    @MainActor
    private static func concurrentWaitersRemainPending() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let first = Task { await permission.requestIfNeeded() }
        await system.waitForRequest()
        var secondFinished = false
        let second = Task {
            await permission.requestIfNeeded()
            secondFinished = true
        }
        for _ in 0..<10 { await Task.yield() }
        require(!secondFinished, "a second caller must await the actual OS decision")
        system.resolve(with: .restricted)
        await first.value
        await second.value
    }

    @MainActor
    private static func firstEntryRequestsAndCompletionUpdatesStatus() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let entry = Task { await permission.requestIfNeeded() }
        await system.waitForRequest()

        require(permission.status == .notDetermined, "an unanswered prompt must not claim microphone access")
        require(permission.isRequesting, "the request button must be disabled while the system prompt is pending")
        let manual = Task { await permission.requestIfNeeded() }
        await Task.yield()
        require(system.requestCount == 1, "automatic entry and a manual request must share one pending prompt")

        system.resolve(with: .authorized)
        await entry.value
        await manual.value
        require(permission.status == .authorized, "granting the prompt must immediately show microphone access")
        require(!permission.isRequesting, "completing the prompt must clear the pending state")

        await permission.requestIfNeeded()
        require(system.requestCount == 1, "reentering the tab after granting must keep the original decision")
    }

    @MainActor
    private static func grantedPermissionSkipsThePrompt() async {
        let system = MicrophoneAuthorizationStub(status: .authorized)
        let permission = system.makePermission()
        await permission.requestIfNeeded()

        require(permission.status == .authorized, "an existing grant must show Allowed on entry")
        require(!permission.isRequesting, "an existing grant must leave the permission controls idle")
        require(system.requestCount == 0, "an existing grant must not invoke the system request")
    }

    @MainActor
    private static func refusedPermissionsRemainAvailableForSettingsRecovery() async {
        for status: AVAuthorizationStatus in [.denied, .restricted] {
            let system = MicrophoneAuthorizationStub(status: status)
            let permission = system.makePermission()
            await permission.requestIfNeeded()

            require(permission.status == status, "denied and restricted decisions must remain distinct for recovery guidance")
            require(!permission.isRequesting, "System Settings recovery must remain usable without a pending prompt")
            require(system.requestCount == 0, "macOS cannot show a second prompt for denied or restricted access")
        }
    }

    @MainActor
    private static func leavingTheTabKeepsOneRequestUntilCompletion() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let firstEntry = Task { await permission.requestIfNeeded() }
        await system.waitForRequest()
        firstEntry.cancel()

        let returningEntry = Task { await permission.requestIfNeeded() }
        await Task.yield()
        require(permission.isRequesting, "leaving and returning must retain the pending system prompt")
        require(system.requestCount == 1, "view task cancellation must not allow a duplicate request")

        system.resolve(with: .denied)
        await firstEntry.value
        await returningEntry.value
        require(permission.status == .denied, "a cancelled view task must still publish the user's microphone decision")
        require(!permission.isRequesting, "a decision after leaving the tab must release the request guard")

        await permission.requestIfNeeded()
        require(system.requestCount == 1, "returning after denial must use Settings recovery instead of prompting")
    }

    @MainActor
    private static func cancelledEntryDoesNotStartAPrompt() async {
        let system = MicrophoneAuthorizationStub(status: .notDetermined)
        let permission = system.makePermission()
        let entry = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await permission.requestIfNeeded()
        }
        await entry.value

        require(permission.status == .notDetermined, "leaving before entry must preserve the undecided state")
        require(!permission.isRequesting, "a cancelled entry must leave the manual request available")
        require(system.requestCount == 0, "a cancelled entry must not open a prompt after the tab disappears")

        let manualRequest = Task { await permission.requestIfNeeded() }
        await system.waitForRequest()
        system.resolve(with: .authorized)
        await manualRequest.value
        require(permission.status == .authorized, "the manual button must still request access after an entry was cancelled")
        require(system.requestCount == 1, "the manual button must start exactly one request")
    }

    @MainActor
    private static func activationRefreshReadsSystemSettingsChanges() {
        let system = MicrophoneAuthorizationStub(status: .denied)
        let permission = system.makePermission()
        system.status = .authorized
        permission.refresh()
        require(permission.status == .authorized, "returning from System Settings must reflect a new grant")

        system.status = .denied
        permission.refresh()
        require(permission.status == .denied, "returning from System Settings must also reflect revoked access")
        require(!permission.isRequesting, "activation refresh must leave recovery controls idle")
        require(system.requestCount == 0, "activation refresh must only read permission without reopening a prompt")
    }
}
