import AVFoundation
import Combine

@MainActor
final class DictationMicrophonePermission: ObservableObject {
    static let shared = DictationMicrophonePermission()

    @Published private(set) var status: AVAuthorizationStatus
    @Published private(set) var isRequesting = false

    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool
    private var requestTask: Task<AVAuthorizationStatus, Never>?

    init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestAccess: @escaping () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .audio)
        }
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        status = authorizationStatus()
    }

    @discardableResult
    func refresh() -> AVAuthorizationStatus {
        status = authorizationStatus()
        return status
    }

    func requestAuthorization() async -> AVAuthorizationStatus {
        if let requestTask { return await requestTask.value }
        let current = refresh()
        guard current == .notDetermined, !Task.isCancelled else { return current }

        isRequesting = true
        let task = Task { @MainActor in
            _ = await requestAccess()
            let result = refresh()
            isRequesting = false
            requestTask = nil
            return result
        }
        requestTask = task
        return await task.value
    }

    func requestIfNeeded() async {
        _ = await requestAuthorization()
    }
}
