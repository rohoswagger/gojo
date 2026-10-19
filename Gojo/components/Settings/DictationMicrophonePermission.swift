import AVFoundation
import Combine

@MainActor
final class DictationMicrophonePermission: ObservableObject {
    static let shared = DictationMicrophonePermission()

    @Published private(set) var status: AVAuthorizationStatus
    @Published private(set) var isRequesting = false

    private let authorizationStatus: () -> AVAuthorizationStatus
    private let requestAccess: () async -> Bool

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

    func refresh() {
        status = authorizationStatus()
    }

    func requestIfNeeded() async {
        refresh()
        guard status == .notDetermined, !isRequesting, !Task.isCancelled else { return }

        isRequesting = true
        _ = await requestAccess()
        refresh()
        isRequesting = false
    }
}
