import Foundation

@MainActor enum Defaults {
    enum Key { case hudReplacement }
    static var enabled = true
    static subscript(_ key: Key) -> Bool {
        get { enabled }
        set { enabled = newValue }
    }
}

struct PermissionStatus { let accessibilityAuthorized: Bool }
enum TransportFailure: Error { case timedOut, interrupted }

@MainActor final class XPCHelperClient {
    static let shared = XPCHelperClient()
    var result: Result<PermissionStatus, TransportFailure> = .failure(.timedOut)
    func helperPermissionStatus() async throws -> PermissionStatus { try result.get() }
    func isAccessibilityAuthorized() async -> Bool {
        (try? await helperPermissionStatus().accessibilityAuthorized) ?? false
    }
}

@MainActor final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()
    var starts = 0
    func start(promptIfNeeded: Bool) async {
        precondition(!promptIfNeeded, "Startup must not request permission")
        starts += 1
    }
}

@main struct HUDPermissionRegression {
    @MainActor static func startup() async {
        /* PRODUCTION_STARTUP */
    }

    @MainActor static func main() async {
        for failure in [TransportFailure.timedOut, .interrupted] {
            Defaults.enabled = true
            XPCHelperClient.shared.result = .failure(failure)
            await startup()
            precondition(Defaults.enabled, "A helper failure must preserve the saved HUD preference")
            precondition(MediaKeyInterceptor.shared.starts == 0, "A helper failure must not start interception")
        }
        XPCHelperClient.shared.result = .success(PermissionStatus(accessibilityAuthorized: false))
        await startup()
        precondition(!Defaults.enabled, "An actual negative authorization reply clears HUD replacement")
        Defaults.enabled = true
        XPCHelperClient.shared.result = .success(PermissionStatus(accessibilityAuthorized: true))
        await startup()
        precondition(Defaults.enabled && MediaKeyInterceptor.shared.starts == 1, "An authorized saved preference starts interception")
        Defaults.enabled = false
        await startup()
        precondition(MediaKeyInterceptor.shared.starts == 1, "A disabled preference must remain inactive")
        print("HUD authorization transport regression passed")
    }
}
