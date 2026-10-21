import AppKit
import Combine
import SwiftUI

// Test doubles for the production collaborators of DictationPanelController.
// The controller itself is compiled unmodified; only these seams are faked.
@MainActor
final class GojoDictationService: ObservableObject {
    static let shared = GojoDictationService()
    @Published var state: DictationState = .idle
    @Published var audioLevel: Float = 0
    @Published var recoveryText = ""
    @Published var recoveryMessage: String?
    @Published var targetApplicationName: String?
    @Published var provisionalPreview: DictationProvisionalPreview?
    @Published var activeIntent: DictationSessionIntent?
    @Published var lastCompletion: DictationCompletion?
    @Published var completionAttentionID: UUID?
    @Published var sessionDisplayID: CGDirectDisplayID?
    var clearedRecoveryTexts: [String] = []
    var autoClear = true
    var cancelCount = 0
    var pendingCancelCompletions: [@MainActor @Sendable () -> Void] = []

    func cancel(completion: @escaping @MainActor @Sendable () -> Void) {
        cancelCount += 1
        pendingCancelCompletions.append(completion)
    }
    func startVoiceMode() {}
    func pauseVoiceMode() {}
    func resumeVoiceMode() {}
    func finishVoiceMode() {}
    func clearRecoveryText(matching text: String) {
        clearedRecoveryTexts.append(text)
        guard autoClear, !text.isEmpty, recoveryText == text else { return }
        recoveryText = ""
        recoveryMessage = nil
    }
}

// The live display lookups are replaced by DictationPanelDisplays in every test;
// these only satisfy the production defaults at compile time.
extension NSScreen {
    static var screenWithMouse: NSScreen? { nil }
    var directDisplayID: CGDirectDisplayID? { nil }
    var displayUUID: String? { nil }
}

@MainActor
final class DictationModifierHotKeyMonitor {
    static let shared = DictationModifierHotKeyMonitor()
    var activationMode: DictationActivationMode = .holdToTalk
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    func showWindow(tab: String) {}
}

@MainActor
final class ManualClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private var now: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private(set) var requested: [Duration] = []
    var pending: Int { sleepers.count }

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                requested.append(duration)
                sleepers[id] = Sleeper(deadline: now + duration, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }

    func advance(_ duration: Duration) {
        now += duration
        let due = sleepers.filter { $0.value.deadline <= now }.sorted { $0.value.deadline < $1.value.deadline }
        for (id, sleeper) in due {
            sleepers.removeValue(forKey: id)
            sleeper.continuation.resume()
        }
    }
}

@MainActor
final class FadeGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var started = 0
    var outstanding: Int { continuations.count }

    func fade(_ panel: NSPanel) async {
        started += 1
        panel.alphaValue = 0.4
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        let waiting = continuations
        continuations = []
        waiting.forEach { $0.resume() }
    }
}

@MainActor
final class DisplayState {
    var screens: [DictationPanelScreen]
    var pointer: String?
    var session: String?
    init(screens: [DictationPanelScreen], pointer: String? = nil, session: String? = nil) {
        self.screens = screens
        self.pointer = pointer
        self.session = session
    }
}

@MainActor
final class Fixture {
    nonisolated static let menuBarScreen = DictationPanelScreen(id: "primary", visibleFrame: CGRect(x: -20000, y: -20000, width: 1440, height: 805))
    let service = GojoDictationService()
    let clock = ManualClock()
    let fades = FadeGate()
    let displays: DisplayState
    let center = NotificationCenter()
    let workspace = NotificationCenter()
    let suite = "gojo.dictation-panel-controller-regression." + UUID().uuidString
    let defaults: UserDefaults
    let controller: DictationPanelController

    init(screens: [DictationPanelScreen] = [Fixture.menuBarScreen], pointer: String? = "primary", session: String? = "primary") {
        defaults = UserDefaults(suiteName: suite)!
        let displayState = DisplayState(screens: screens, pointer: pointer, session: session)
        displays = displayState
        let clock = clock
        let fades = fades
        controller = DictationPanelController(
            service: service,
            defaults: defaults,
            notificationCenter: center,
            workspaceNotificationCenter: workspace,
            displays: DictationPanelDisplays(
                screens: { displayState.screens },
                pointerDisplayID: { displayState.pointer },
                sessionDisplayID: { displayState.session }
            ),
            sleeper: { try await clock.sleep($0) },
            fade: { await fades.fade($0) }
        )
    }

    var panel: NSPanel? { controller.debugPanel }
    var model: DictationPanelModel { controller.debugModel }
    var isVisible: Bool { panel?.isVisible == true }

    func start() async {
        controller.startObserving()
        await Harness.flush()
    }

    func advance(_ duration: Duration) async {
        clock.advance(duration)
        await Harness.flush()
    }

    func teardown() {
        controller.debugPanel?.orderOut(nil)
        defaults.removePersistentDomain(forName: suite)
    }
}

enum Harness {
    @MainActor
    static func flush() async {
        for _ in 0..<4 {
            await withCheckedContinuation { continuation in
                RunLoop.main.perform { continuation.resume() }
            }
            await Task.yield()
            await Task.yield()
        }
    }

    @MainActor
    static func waitUntil(_ message: String, timeout: TimeInterval = 3, _ condition: @MainActor () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while !condition() {
            if Date() > deadline { fail("Timed out waiting for: \(message)") }
            await flush()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    static func near(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 1 && abs(lhs.minY - rhs.minY) <= 1
            && abs(lhs.width - rhs.width) <= 1 && abs(lhs.height - rhs.height) <= 1
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fail(message) }
    }

    static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct DictationPanelControllerRegression {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await run()
            print("Dictation panel controller regressions passed")
            exit(0)
        }
        app.run()
    }

    @MainActor
    static func run() async {
        await savedTranscriptExpiresAndIsForgotten()
        await hoverPausesAndRestartsGrace()
        await duplicateAndMessageOnlyPublicationsStayHidden()
        await explicitCloseDiscardsTranscript()
        await copyDiscardAndStaleSnapshots()
        await activeSessionsNeverAutoHide()
        await terminalNoticesExpire()
        await staleFadeCannotHideNewPresentation()
        await explicitDismissKeepsCancellationSemantics()
        await reassertsOnlyVisiblePanel()
        await replacementClampsAndPreservesPosition()
        await manualReadyIsUntimed()
        await reviewedLifecycleEdges()
    }

    private static let saved = "saved words that could not be inserted"

    @MainActor
    private static func publishRecovery(_ fixture: Fixture, _ text: String = saved, _ message: String? = "No selected field") async {
        fixture.service.recoveryText = text
        fixture.service.recoveryMessage = message
        await Harness.flush()
    }

    @MainActor
    private static func expectNoKeyFocus(_ fixture: Fixture, _ context: String) {
        Harness.expect(fixture.panel?.isKeyWindow == false && NSApp.keyWindow == nil && !NSApp.isActive,
                       "\(context) must not take key focus or activate Gojo")
    }

    @MainActor
    private static func expiringRecoveryPanel(_ fixture: Fixture) async {
        await fixture.start()
        await publishRecovery(fixture)
        Harness.expect(fixture.isVisible && fixture.panel?.alphaValue == 1, "Saved text must present the panel")
        Harness.expect(fixture.model.recoveryText == saved, "The panel must show the saved text")
        Harness.expect(fixture.clock.pending == 1 && fixture.clock.requested == [.seconds(10)],
                       "Terminal saved text must register exactly one ten-second expiry, got \(fixture.clock.requested)")
    }

    @MainActor
    private static func savedTranscriptExpiresAndIsForgotten() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        await expiringRecoveryPanel(fixture)
        expectNoKeyFocus(fixture, "Presenting saved text")
        await fixture.advance(.milliseconds(9900))
        Harness.expect(fixture.isVisible && fixture.fades.started == 0, "Saved text must stay through its grace period")
        await fixture.advance(.milliseconds(100))
        Harness.expect(fixture.fades.started == 1, "Saved text must start fading after ten seconds")
        fixture.fades.release()
        await Harness.flush()
        Harness.expect(!fixture.isVisible, "The faded saved-text panel must be hidden")
        Harness.expect(fixture.service.clearedRecoveryTexts == [saved] && fixture.service.recoveryText.isEmpty,
                       "Expiry must forget the text in the service with the shown snapshot")
        Harness.expect(fixture.model.recoveryText.isEmpty && fixture.model.recoveryMessage == nil,
                       "Expiry must forget the text in the panel model")
        Harness.expect(fixture.clock.pending == 0, "No timer may survive the hide")

        fixture.controller.show()
        await Harness.flush()
        Harness.expect(fixture.isVisible && fixture.panel?.alphaValue == 1, "Manual show presents Ready at full alpha")
        Harness.expect(fixture.model.recoveryText.isEmpty && !fixture.model.showsDetails,
                       "Manual show must not resurrect expired text")
        Harness.expect(fixture.clock.pending == 0, "Ready stays untimed")
        expectNoKeyFocus(fixture, "Manual show")

        await publishRecovery(fixture, saved + " plus more", "Updated")
        Harness.expect(fixture.isVisible && fixture.model.recoveryText == saved + " plus more", "New text shows")
        Harness.expect(fixture.clock.pending == 1, "New text arms its own deadline")
        await fixture.advance(.seconds(10))
        fixture.fades.release()
        await Harness.flush()
        Harness.expect(!fixture.isVisible && fixture.service.recoveryText.isEmpty, "New text expires too")

        // Voice mode must not exempt saved text.
        let voice = Fixture()
        defer { voice.teardown() }
        DictationModifierHotKeyMonitor.shared.activationMode = .voiceMode
        defer { DictationModifierHotKeyMonitor.shared.activationMode = .holdToTalk }
        await voice.start()
        voice.service.state = .listening
        await Harness.flush()
        voice.service.state = .idle
        await Harness.flush()
        Harness.expect(voice.isVisible && voice.model.isHandsFree, "Voice mode keeps the Ready controls after a session")
        await publishRecovery(voice)
        Harness.expect(voice.clock.requested.last == .seconds(10), "Saved text expires even in voice mode")
        await voice.advance(.seconds(10))
        voice.fades.release()
        await Harness.flush()
        Harness.expect(!voice.isVisible && voice.model.recoveryText.isEmpty && voice.service.recoveryText.isEmpty,
                       "Voice-mode saved text is forgotten and hidden")
    }

    @MainActor
    private static func hoverPausesAndRestartsGrace() async {
        for target in ["capsule", "details"] {
            let fixture = Fixture()
            defer { fixture.teardown() }
            await expiringRecoveryPanel(fixture)
            await fixture.advance(.seconds(5))
            if target == "capsule" { fixture.model.capsuleHovered = true } else { fixture.model.detailsHovered = true }
            await Harness.flush()
            Harness.expect(fixture.clock.pending == 0, "Hovering the \(target) must pause the deadline")
            await fixture.advance(.seconds(60))
            Harness.expect(fixture.isVisible && fixture.fades.started == 0, "A hovered \(target) must never expire")
            if target == "capsule" {
                // Pointer moves capsule -> details popover without a gap in hover.
                fixture.model.detailsHovered = true
                fixture.model.capsuleHovered = false
                await Harness.flush()
                Harness.expect(fixture.clock.pending == 0, "Capsule-to-details handoff must stay paused")
                fixture.model.detailsHovered = false
            } else {
                fixture.model.detailsHovered = false
            }
            await Harness.flush()
            Harness.expect(fixture.clock.pending == 1 && fixture.clock.requested.last == .seconds(10),
                           "Leaving must restart the full grace")
            await fixture.advance(.milliseconds(9900))
            Harness.expect(fixture.fades.started == 0, "Hover-out must restart, not resume, the deadline")
            await fixture.advance(.milliseconds(100))
            Harness.expect(fixture.fades.started == 1, "The restarted deadline must expire")
            fixture.fades.release()
            await Harness.flush()
            Harness.expect(!fixture.isVisible, "The panel hides after the restarted grace")
        }
    }

    @MainActor
    private static func duplicateAndMessageOnlyPublicationsStayHidden() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        fixture.service.autoClear = false
        await expiringRecoveryPanel(fixture)
        await publishRecovery(fixture, saved, "A different message")
        await publishRecovery(fixture, saved, "Yet another message")
        Harness.expect(fixture.clock.requested == [.seconds(10)] && fixture.clock.pending == 1,
                       "Message-only publications must not restart the deadline")
        await fixture.advance(.seconds(10))
        fixture.fades.release()
        await Harness.flush()
        Harness.expect(!fixture.isVisible && fixture.model.recoveryText.isEmpty, "Precondition: expired and hidden")
        await publishRecovery(fixture, saved, "Late message-only republish")
        Harness.expect(!fixture.isVisible && fixture.model.recoveryText.isEmpty,
                       "A delayed publication of the expired text must not resurrect it")
        fixture.service.recoveryText = saved
        await Harness.flush()
        Harness.expect(!fixture.isVisible, "A duplicate text publication must not resurrect an expired panel")
        await publishRecovery(fixture, "", nil)
        Harness.expect(!fixture.isVisible, "The authoritative clear leaves the panel hidden")
        await publishRecovery(fixture, "entirely new words", "Fresh")
        Harness.expect(fixture.isVisible && fixture.model.recoveryText == "entirely new words", "New text must show")
        Harness.expect(fixture.clock.pending == 1, "New text arms a fresh deadline")
    }

    @MainActor
    private static func explicitCloseDiscardsTranscript() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        fixture.service.autoClear = false
        await expiringRecoveryPanel(fixture)
        fixture.controller.dismiss()
        await Harness.flush()
        Harness.expect(!fixture.isVisible && fixture.clock.pending == 0, "X hides immediately and cancels the timer")
        Harness.expect(fixture.service.clearedRecoveryTexts == [saved] && fixture.model.recoveryText.isEmpty,
                       "X discards the shown transcript with its snapshot")
        await publishRecovery(fixture, saved, "Message only")
        Harness.expect(!fixture.isVisible, "Late publications must not reopen an explicitly closed panel")
        fixture.controller.show()
        await Harness.flush()
        Harness.expect(fixture.isVisible && fixture.model.recoveryText.isEmpty, "Manual show cannot resurrect the discarded text")

        let active = Fixture()
        defer { active.teardown() }
        await active.start()
        active.service.state = .listening
        await Harness.flush()
        await publishRecovery(active)
        active.controller.dismiss()
        await Harness.flush()
        Harness.expect(!active.isVisible && active.service.cancelCount == 1 && active.service.clearedRecoveryTexts == [saved],
                       "X during a session still cancels it and discards the transcript")
    }

    @MainActor
    private static func copyDiscardAndStaleSnapshots() async {
        for action in ["copy", "discard"] {
            let fixture = Fixture()
            defer { fixture.teardown() }
            fixture.service.autoClear = false
            await expiringRecoveryPanel(fixture)
            if action == "copy" {
                Harness.expect(fixture.model.copyRecoveryText(write: { $0 == saved }), "Copy writes the shown snapshot")
            }
            fixture.controller.debugPerform(.clearRecovery(saved))
            await Harness.flush()
            Harness.expect(!fixture.isVisible && fixture.clock.pending == 0, "\(action) must close the panel immediately")
            Harness.expect(fixture.service.clearedRecoveryTexts == [saved], "\(action) must consume exactly the shown snapshot")
            await publishRecovery(fixture, saved, "Late message-only republish")
            Harness.expect(!fixture.isVisible && fixture.model.recoveryText.isEmpty,
                           "A delayed publication of the consumed text must not resurrect it after \(action)")
            fixture.service.recoveryText = ""
            fixture.service.recoveryMessage = nil
            await Harness.flush()
            Harness.expect(!fixture.isVisible, "The authoritative clear leaves the panel hidden")
            fixture.service.state = .listening
            await Harness.flush()
            Harness.expect(fixture.isVisible && fixture.panel?.alphaValue == 1, "Normal dictation must present after \(action)")
            await publishRecovery(fixture, saved)
            Harness.expect(fixture.model.recoveryText == saved, "The same text can be saved again after the service cleared it")
        }

        let stale = Fixture()
        defer { stale.teardown() }
        await stale.start()
        await publishRecovery(stale, "old text")
        await publishRecovery(stale, "newer text")
        stale.controller.debugPerform(.clearRecovery("old text"))
        await Harness.flush()
        Harness.expect(stale.isVisible && stale.model.recoveryText == "newer text", "A stale discard must keep the newer transcript")
        Harness.expect(stale.service.clearedRecoveryTexts == ["old text"], "The service still receives the snapshot for its own stale guard")
        await publishRecovery(stale, "newer text", "Another message")
        Harness.expect(stale.model.recoveryText == "newer text", "A stale discard must not consume the newer text")

        let active = Fixture()
        defer { active.teardown() }
        await active.start()
        active.service.state = .listening
        await Harness.flush()
        await publishRecovery(active)
        active.model.showsDetails = true
        await Harness.flush()
        active.controller.debugPerform(.clearRecovery(saved))
        await Harness.flush()
        Harness.expect(active.isVisible && !active.model.showsDetails && active.model.recoveryText.isEmpty,
                       "Copy or discard during a session keeps the controls and closes the details")
        await Harness.flush()
        Harness.expect(active.clock.pending == 0, "No details timer survives a discard")
    }

    @MainActor
    private static func activeSessionsNeverAutoHide() async {
        let states: [DictationState] = [.requestingPermission, .listening, .pausing, .paused, .transcribing, .inserting]
        for state in states {
            let fixture = Fixture()
            defer { fixture.teardown() }
            await fixture.start()
            fixture.service.state = state
            await Harness.flush()
            Harness.expect(fixture.isVisible, "\(state) must present")
            await fixture.advance(.seconds(120))
            Harness.expect(fixture.isVisible && fixture.fades.started == 0 && fixture.clock.requested.isEmpty,
                           "\(state) must never auto-hide or arm an expiry")
        }

        let fixture = Fixture()
        defer { fixture.teardown() }
        await fixture.start()
        fixture.service.state = .listening
        await Harness.flush()
        await publishRecovery(fixture)
        fixture.model.showsDetails = true
        await Harness.flush()
        Harness.expect(fixture.clock.pending == 1 && fixture.clock.requested == [.seconds(10)],
                       "Recovery in an active session expires after ten seconds")
        await fixture.advance(.seconds(10))
        Harness.expect(!fixture.model.showsDetails && fixture.isVisible && fixture.fades.started == 0,
                       "Only the popup closes; the session controls stay")
        Harness.expect(fixture.model.recoveryText.isEmpty && fixture.service.recoveryText.isEmpty
                       && fixture.service.clearedRecoveryTexts == [saved], "The expired recovery is forgotten")
        Harness.expect(fixture.service.cancelCount == 0 && fixture.model.state == .listening,
                       "Recovery expiry must not cancel the session")

        // A stale deadline cannot clear newer recovery.
        await publishRecovery(fixture, "first recovery")
        await fixture.advance(.seconds(9))
        await publishRecovery(fixture, "second recovery")
        await fixture.advance(.seconds(2))
        Harness.expect(fixture.model.recoveryText == "second recovery" && fixture.service.recoveryText == "second recovery",
                       "The first deadline must not clear newer recovery")
        await fixture.advance(.seconds(8))
        Harness.expect(fixture.model.recoveryText.isEmpty && fixture.isVisible, "The newer recovery has its own deadline")
        fixture.model.capsuleHovered = true
        await publishRecovery(fixture, "third recovery")
        await Harness.flush()
        Harness.expect(fixture.clock.pending == 0, "Hover pauses the active recovery deadline")
        fixture.model.capsuleHovered = false
        await Harness.flush()
        Harness.expect(fixture.clock.pending == 1, "Hover-out restarts the active recovery deadline")
        fixture.service.state = .paused
        await Harness.flush()
        await fixture.advance(.seconds(30))
        Harness.expect(fixture.isVisible && fixture.fades.started == 0, "State changes within a session never hide it")
    }

    @MainActor
    private static func terminalNoticesExpire() async {
        // Errors: two seconds, even with the details open.
        let error = Fixture()
        defer { error.teardown() }
        await error.start()
        error.service.state = .error(.captureFailed("Microphone unavailable"))
        await Harness.flush()
        error.model.showsDetails = true
        await Harness.flush()
        Harness.expect(error.isVisible && error.clock.requested.last == .seconds(2), "Errors expire after two seconds")
        await error.advance(.milliseconds(1900))
        Harness.expect(error.fades.started == 0, "Errors stay for the full grace")
        await error.advance(.milliseconds(100))
        Harness.expect(error.fades.started == 1, "Open details must not block error expiry")
        error.fades.release()
        await Harness.flush()
        Harness.expect(!error.isVisible, "Errors hide after fading")

        // Errors that carry saved text use the longer grace.
        let errorWithText = Fixture()
        defer { errorWithText.teardown() }
        await errorWithText.start()
        errorWithText.service.state = .error(.insertionFailed("No field"))
        await Harness.flush()
        await publishRecovery(errorWithText)
        Harness.expect(errorWithText.clock.requested.last == .seconds(10) && errorWithText.clock.pending == 1,
                       "Saved text on an error replaces the short error grace")

        // Empty completions in hold-to-talk mode.
        let empty = Fixture()
        defer { empty.teardown() }
        await empty.start()
        empty.service.lastCompletion = .empty(reason: .noSpeech)
        empty.service.completionAttentionID = UUID()
        await Harness.flush()
        Harness.expect(empty.isVisible && empty.model.emptyCompletion == .noSpeech, "Empty completions are announced")
        Harness.expect(empty.clock.requested == [.seconds(2)], "Empty completions expire after two seconds")
        empty.model.showsDetails = true
        await empty.advance(.seconds(2))
        Harness.expect(empty.model.emptyCompletion == nil && empty.fades.started == 1,
                       "Empty completions clear and fade even with details open")
        empty.fades.release()
        await Harness.flush()
        Harness.expect(!empty.isVisible, "Empty completions hide")
        let completionID = empty.service.completionAttentionID
        empty.service.lastCompletion = .empty(reason: .noSpeech)
        empty.service.completionAttentionID = completionID
        await Harness.flush()
        Harness.expect(!empty.isVisible, "Re-publishing a handled empty completion must not resurrect it")

        // Normal completion: hold-to-talk fades quickly, voice mode keeps Ready.
        let done = Fixture()
        defer { done.teardown() }
        await done.start()
        done.service.state = .listening
        await Harness.flush()
        done.service.state = .succeeded("inserted")
        await Harness.flush()
        Harness.expect(done.clock.requested.last == .milliseconds(120), "Push-to-talk completion has a short grace")
        await done.advance(.milliseconds(120))
        done.fades.release()
        await Harness.flush()
        Harness.expect(!done.isVisible && done.model.state == .idle, "Completion hides and settles to idle")

        let held = Fixture()
        defer { held.teardown() }
        await held.start()
        held.service.state = .listening
        await Harness.flush()
        held.service.state = .idle
        await Harness.flush()
        Harness.expect(held.fades.started == 1 && held.clock.requested.isEmpty, "A cancelled hold fades immediately")
        held.fades.release()
        await Harness.flush()
        Harness.expect(!held.isVisible && held.model.state == .idle, "The cancelled hold hides")

        DictationModifierHotKeyMonitor.shared.activationMode = .voiceMode
        defer { DictationModifierHotKeyMonitor.shared.activationMode = .holdToTalk }
        let voice = Fixture()
        defer { voice.teardown() }
        await voice.start()
        voice.service.state = .listening
        await Harness.flush()
        voice.service.state = .succeeded("inserted")
        await Harness.flush()
        Harness.expect(voice.clock.requested.last == .milliseconds(900), "Voice-mode completion lingers briefly")
        await voice.advance(.milliseconds(900))
        Harness.expect(voice.isVisible && voice.model.state == .idle && voice.fades.started == 0,
                       "Voice mode keeps its Ready controls after normal completion")
        await voice.advance(.seconds(60))
        Harness.expect(voice.isVisible, "Ready controls are untimed")
    }

    @MainActor
    private static func staleFadeCannotHideNewPresentation() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        await expiringRecoveryPanel(fixture)
        await fixture.advance(.seconds(10))
        Harness.expect(fixture.fades.outstanding == 1 && fixture.panel?.alphaValue == 0.4, "Precondition: mid-fade")
        fixture.service.state = .listening
        await Harness.flush()
        Harness.expect(fixture.isVisible && fixture.panel?.alphaValue == 1, "A new session must restore full alpha")
        fixture.fades.release()
        await Harness.flush()
        Harness.expect(fixture.isVisible && fixture.panel?.alphaValue == 1 && fixture.model.state == .listening,
                       "A stale fade completion must not hide or dim the new session")
        await fixture.advance(.seconds(60))
        Harness.expect(fixture.isVisible, "The new session stays visible after the stale fade")

        let next = Fixture()
        defer { next.teardown() }
        await expiringRecoveryPanel(next)
        await next.advance(.seconds(10))
        await publishRecovery(next, "recovery during fade")
        next.fades.release()
        await Harness.flush()
        Harness.expect(next.isVisible && next.panel?.alphaValue == 1 && next.model.recoveryText == "recovery during fade",
                       "New recovery during an expiry fade must survive its stale completion")
        Harness.expect(next.service.recoveryText == "recovery during fade", "The stale expiry must not clear newer recovery")

        // Manual show during a fade, then stale completion.
        let manual = Fixture()
        defer { manual.teardown() }
        await expiringRecoveryPanel(manual)
        await manual.advance(.seconds(10))
        manual.controller.show()
        await Harness.flush()
        manual.fades.release()
        await Harness.flush()
        Harness.expect(manual.isVisible && manual.panel?.alphaValue == 1, "Manual show beats a stale fade")

        // Immediate hide during a fade stays hidden after completion.
        let hidden = Fixture()
        defer { hidden.teardown() }
        await expiringRecoveryPanel(hidden)
        await hidden.advance(.seconds(10))
        hidden.controller.debugPerform(.clearRecovery(saved))
        await Harness.flush()
        hidden.fades.release()
        await Harness.flush()
        Harness.expect(!hidden.isVisible, "Discard during a fade leaves the panel hidden")
    }

    @MainActor
    private static func explicitDismissKeepsCancellationSemantics() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        await fixture.start()
        fixture.service.state = .listening
        await Harness.flush()
        fixture.controller.dismiss()
        await Harness.flush()
        Harness.expect(!fixture.isVisible && fixture.service.cancelCount == 1, "Dismissing a session cancels it")
        fixture.service.state = .transcribing
        await Harness.flush()
        Harness.expect(!fixture.isVisible, "The cancelled session must stay hidden until it becomes inactive")
        fixture.service.state = .idle
        await Harness.flush()
        fixture.service.pendingCancelCompletions.forEach { $0() }
        fixture.service.state = .listening
        await Harness.flush()
        Harness.expect(fixture.isVisible, "A new session presents after cancellation completes")
    }

    @MainActor
    private static func reassertsOnlyVisiblePanel() async {
        for notification in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            let fixture = Fixture()
            defer { fixture.teardown() }
            await fixture.start()
            fixture.service.state = .listening
            await Harness.flush()
            guard let panel = fixture.panel else { Harness.fail("Panel expected") }
            Harness.expect(panel.level == .statusBar, "The panel must float at status-bar level")
            Harness.expect(panel.collectionBehavior.contains(.canJoinAllApplications)
                           && panel.collectionBehavior.contains(.canJoinAllSpaces)
                           && panel.collectionBehavior.contains(.fullScreenAuxiliary),
                           "The panel must join every application's Spaces")
            Harness.expect(panel.styleMask.contains(.nonactivatingPanel) && !panel.canBecomeKey, "The panel must stay non-activating")

            panel.orderOut(nil)
            panel.level = .floating
            fixture.workspace.post(name: notification, object: nil)
            await Harness.flush()
            Harness.expect(panel.isVisible && panel.level == .statusBar && panel.alphaValue == 1,
                           "\(notification.rawValue) must reassert an intentionally visible panel")
            expectNoKeyFocus(fixture, notification.rawValue)

            fixture.controller.dismiss()

            await Harness.flush()
            fixture.workspace.post(name: notification, object: nil)
            await Harness.flush()
            Harness.expect(!panel.isVisible, "A manually dismissed panel must not be reasserted")

            let recovery = Fixture()
            defer { recovery.teardown() }
            await expiringRecoveryPanel(recovery)
            await recovery.advance(.seconds(10))
            recovery.fades.release()
            await Harness.flush()
            recovery.workspace.post(name: notification, object: nil)
            await Harness.flush()
            Harness.expect(recovery.panel?.isVisible == false, "A timer-hidden panel must not be reasserted")
            Harness.expect(recovery.fades.outstanding == 0 && recovery.clock.pending == 0, "Reassertion must not arm timers while hidden")

            let fading = Fixture()
            defer { fading.teardown() }
            await expiringRecoveryPanel(fading)
            await fading.advance(.seconds(10))
            fading.workspace.post(name: notification, object: nil)
            await Harness.flush()
            Harness.expect(fading.panel?.alphaValue == 0.4, "Reassertion must not undo an in-flight fade")
            fading.fades.release()
            await Harness.flush()
            Harness.expect(fading.panel?.isVisible == false, "The in-flight fade still completes")
        }
    }

    @MainActor
    private static func replacementClampsAndPreservesPosition() async {
        let full = DictationPanelScreen(id: "primary", visibleFrame: CGRect(x: -20000, y: -20070, width: 1440, height: 875))
        let size = DictationPanelPlacement.defaultSize

        // Default (never dragged) position follows a changed visible frame.
        let fixture = Fixture()
        defer { fixture.teardown() }
        fixture.controller.show()
        await Harness.flush()
        let menuFrame = fixture.panel!.frame
        Harness.expect(menuFrame == DictationPanelPlacement.restore(
            size: size, screens: [Fixture.menuBarScreen], pointerDisplayID: "primary",
            preferredDisplayID: nil, fallbackDisplayID: "primary", positions: [:])!.frame,
            "Initial placement uses the visible frame with the menu bar")
        fixture.displays.screens = [full]
        fixture.workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await Harness.flush()
        Harness.expect(fixture.panel!.frame == DictationPanelPlacement.restore(
            size: size, screens: [full], pointerDisplayID: "primary",
            preferredDisplayID: nil, fallbackDisplayID: "primary", positions: [:])!.frame,
            "A full-screen Space re-clamps the default placement to the new visible frame")
        Harness.expect(fixture.panel!.frame.minY < menuFrame.minY, "The panel moved into the reclaimed menu-bar and Dock area")

        // A user-dragged position is preserved proportionally on the same display.
        let dragged = Fixture()
        defer { dragged.teardown() }
        dragged.controller.show()
        await Harness.flush()
        dragged.panel!.setFrameOrigin(CGPoint(x: -19700, y: -19670))
        dragged.controller.debugCompleteDrag()
        let savedPosition = DictationPanelPlacement.savedPosition(for: dragged.panel!.frame, on: Fixture.menuBarScreen)!
        Harness.expect(dragged.defaults.data(forKey: "gojo.dictation.panel.placement.v1") != nil,
                       "Drag persistence must use the injected defaults")
        dragged.displays.screens = [full]
        dragged.workspace.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        await Harness.flush()
        Harness.expect(Harness.near(dragged.panel!.frame, DictationPanelPlacement.restore(
            size: size, screens: [full], pointerDisplayID: nil, preferredDisplayID: "primary",
            fallbackDisplayID: "primary", positions: ["primary": savedPosition])!.frame),
            "A dragged position is preserved on the same display after a visible-frame change")

        // Pointer-first placement and disconnect fallback stay intact.
        let left = DictationPanelScreen(id: "left", visibleFrame: CGRect(x: -21920, y: -20310, width: 1920, height: 1080))
        let multi = Fixture(screens: [Fixture.menuBarScreen, left], pointer: "left", session: "primary")
        defer { multi.teardown() }
        multi.controller.show()
        await Harness.flush()
        Harness.expect(left.visibleFrame.contains(multi.panel!.frame), "A manual show lands on the pointer display")
        multi.displays.pointer = "primary"
        multi.workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        await Harness.flush()
        Harness.expect(Fixture.menuBarScreen.visibleFrame.contains(multi.panel!.frame), "Reassertion follows the pointer display")
        multi.displays.session = "left"
        multi.service.sessionDisplayID = 2
        await Harness.flush()
        Harness.expect(left.visibleFrame.contains(multi.panel!.frame),
                       "A same-app session target change follows its display even if the pointer is elsewhere")
        multi.displays.screens = [Fixture.menuBarScreen]
        multi.center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await Harness.flush()
        Harness.expect(Fixture.menuBarScreen.visibleFrame.contains(multi.panel!.frame),
                       "A disconnected display falls back to the session display")
    }

    @MainActor
    private static func manualReadyIsUntimed() async {
        let fixture = Fixture()
        defer { fixture.teardown() }
        fixture.controller.show()
        await Harness.flush()
        Harness.expect(fixture.isVisible && fixture.model.state == .idle, "Manual show presents Ready")
        await fixture.advance(.seconds(300))
        Harness.expect(fixture.isVisible && fixture.clock.requested.isEmpty && fixture.fades.started == 0,
                       "The initial empty publications must not close or time out a manually opened Ready")
        expectNoKeyFocus(fixture, "Manual Ready")
    }
    @MainActor
    private static func reviewedLifecycleEdges() async {
        for terminal in [DictationState.succeeded("inserted"), .error(.captureFailed("test error"))] {
            let fixture = Fixture()
            defer { fixture.teardown() }
            await fixture.start()
            fixture.service.state = terminal
            await Harness.flush()
            fixture.controller.show()
            await Harness.flush()
            await fixture.advance(.seconds(30))
            Harness.expect(fixture.isVisible && fixture.model.state == .idle && fixture.fades.started == 0,
                           "Manual Ready must not inherit an old terminal deadline")
            fixture.service.state = terminal
            await Harness.flush()
            if case .error = terminal {
                Harness.expect(fixture.model.state == terminal && fixture.isVisible,
                               "A repeated failed start must show its error after manual Ready")
                await fixture.advance(.seconds(2))
                fixture.fades.release()
                await Harness.flush()
                Harness.expect(!fixture.isVisible, "The repeated error must expire")
                fixture.service.state = terminal
                await Harness.flush()
                Harness.expect(fixture.isVisible && fixture.model.state == terminal,
                               "The same error on a later failed attempt must show again")
            } else {
                Harness.expect(fixture.model.state == .idle, "Duplicate success must not replace manual Ready")
            }
        }
        let repeated = Fixture()
        defer { repeated.teardown() }
        await expiringRecoveryPanel(repeated)
        repeated.service.autoClear = false
        await repeated.advance(.seconds(10))
        repeated.fades.release()
        await Harness.flush()
        repeated.service.state = .listening
        await Harness.flush()
        await publishRecovery(repeated)
        Harness.expect(repeated.model.recoveryText == saved && repeated.isVisible,
                       "A new session can show identical text even when the old empty acknowledgement was skipped")

        for mode in [DictationActivationMode.holdToTalk, .voiceMode] {
            DictationModifierHotKeyMonitor.shared.activationMode = mode
            let deferred = Fixture()
            await deferred.start()
            deferred.service.state = .error(.captureFailed("deferred clear"))
            await Harness.flush()
            await publishRecovery(deferred)
            deferred.service.autoClear = false
            await deferred.advance(.seconds(10))
            Harness.expect(deferred.fades.outstanding == 1, "Expiry starts a fade before async clear acknowledgement")
            deferred.service.recoveryText = ""
            deferred.service.recoveryMessage = nil
            deferred.service.state = .idle
            await Harness.flush()
            deferred.service.state = .idle
            await Harness.flush()
            deferred.service.state = .listening
            await Harness.flush()
            deferred.fades.release()
            await Harness.flush()
            Harness.expect(deferred.isVisible && deferred.panel?.alphaValue == 1 && deferred.model.state == .listening,
                           "Delayed terminal clear and old fade cannot hide a new session")
            deferred.teardown()
        }
        DictationModifierHotKeyMonitor.shared.activationMode = .holdToTalk
    }

}
