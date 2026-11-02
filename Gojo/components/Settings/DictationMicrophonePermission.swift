import AVFoundation
import Combine

@MainActor
final class DictationMicrophonePermission: ObservableObject {
    static let shared = DictationMicrophonePermission(isEnabled: DictationEnablementPreferences.isEnabled())

    @Published private(set) var status: AVAuthorizationStatus
    @Published private(set) var isRequesting = false

    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool
    private var isEnabled: Bool
    private var admissionGeneration: UInt = 0
    private var requestTask: Task<AVAuthorizationStatus, Never>?

    init(
        authorizationStatus: @escaping () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        requestAccess: @escaping () async -> Bool = {
            await AVCaptureDevice.requestAccess(for: .audio)
        },
        isEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.authorizationStatus = authorizationStatus
        self.requestAccess = requestAccess
        status = authorizationStatus()
    }

    @discardableResult
    func refresh() -> AVAuthorizationStatus {
        status = authorizationStatus()
        return status
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        admissionGeneration &+= 1
        if !enabled { requestTask?.cancel() }
    }

    func requestAuthorization() async -> AVAuthorizationStatus {
        guard isEnabled, !Task.isCancelled else { return refresh() }
        if let requestTask { return await requestTask.value }
        let current = refresh()
        guard current == .notDetermined, !Task.isCancelled else { return current }

        isRequesting = true
        let generation = admissionGeneration
        let task = Task { @MainActor in
            if isEnabled, generation == admissionGeneration, !Task.isCancelled {
                _ = await requestAccess()
            }
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
