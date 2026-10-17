import Foundation

@MainActor
final class GojoDictationService {
    static let shared = GojoDictationService()

    private(set) var commands: [String] = []
    private(set) var hasPendingWork = false

    static func sendShortcutEvent(_ event: DictationShortcutEvent) {
        shared.commands.append(String(describing: event))
        switch event {
        case .keyDown, .startVoiceMode:
            shared.hasPendingWork = true
        case .cancel:
            shared.hasPendingWork = false
        default:
            break
        }
    }

    func beginShortcut() {
        Self.sendShortcutEvent(.keyDown)
    }

    func startVoiceMode() {
        Self.sendShortcutEvent(.startVoiceMode)
    }

    func clearCommands() {
        commands.removeAll()
    }
}

@MainActor
final class XPCHelperClient {
    static let shared = XPCHelperClient()

    private(set) var authorizationChecks = 0

    func isAccessibilityAuthorized() async -> Bool {
        authorizationChecks += 1
        return false
    }

    func ensureAccessibilityAuthorization(promptIfNeeded: Bool) async -> Bool {
        fatalError("The cancellation regression must not request Accessibility authorization")
    }
}

@main
struct DictationShortcutCancellationRegression {
    @MainActor
    static func main() async {
        let monitor = DictationModifierHotKeyMonitor.shared
        let service = GojoDictationService.shared
        var failures: [String] = []

        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        func expectCommands(_ commands: [String], _ message: String) {
            expect(service.commands == commands, "\(message). Expected \(commands), received \(service.commands)")
        }

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        expect(service.hasPendingWork, "Finish leaves downstream work pending in the stub")
        monitor.cancelCurrentSession()
        expectCommands(["cancel"], "Idle recognizer cancels downstream work after Finish")
        expect(!service.hasPendingWork, "Explicit cancellation reaches downstream work")

        service.clearCommands()
        monitor.cancelCurrentSession()
        monitor.cancelCurrentSession()
        expectCommands(["cancel", "cancel"], "Repeated idle cancellation sends one command per invocation")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        expect(monitor.activationMode == .voiceMode, "Adopted voice session locks the recognizer")
        monitor.cancelCurrentSession()
        expectCommands(["cancel"], "Locked cancellation sends exactly one command")
        expect(monitor.activationMode == .holdToTalk, "Cancellation clears the voice lock")

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        monitor.stop()
        expectCommands(["cancel"], "Stopping an idle recognizer cancels downstream work")
        expect(!service.hasPendingWork, "Stop reaches downstream work")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        monitor.stop()
        expectCommands(["cancel"], "Stopping a locked recognizer sends exactly one command")
        expect(monitor.activationMode == .holdToTalk, "Stop clears the voice lock")

        service.beginShortcut()
        GojoDictationService.sendShortcutEvent(.keyUp)
        service.clearCommands()
        monitor.accessibilityAuthorizationWasRevoked()
        expectCommands(["cancel"], "Authorization revocation cancels downstream work")

        monitor.adoptVoiceModeSession()
        service.startVoiceMode()
        service.clearCommands()
        await monitor.recoverIfNeeded()
        expectCommands([], "Event-tap recovery preserves a locked voice session")
        expect(monitor.activationMode == .voiceMode, "Recovery retains the voice lock")
        expect(service.hasPendingWork, "Recovery retains downstream voice work")
        expect(XPCHelperClient.shared.authorizationChecks == 1, "Recovery uses the nonprompting authorization stub")
        expect(!monitor.isMonitoring, "The regression never starts an event tap")
        monitor.cancelCurrentSession()

        guard failures.isEmpty else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("Dictation shortcut cancellation regressions passed")
    }
}
