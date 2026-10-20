import AppKit
import SwiftUI

private actor ImportGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isWaiting: Bool { continuation != nil }

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ImportFixture: ObservableObject {
    struct Operation {
        let id: UUID
        let task: Task<Void, Never>
    }

    weak var window: NSWindow?
    var entries: [DictationVocabularyEntry] = []
    var report: DictationVocabularyImport.Report?
    var presentation: String?
    var lifetime: UUID?
    var operation: Operation?
    var worker: Task<DictationVocabularyImport.Document, Error>?
    var appearanceCount = 0
    var disappearanceCount = 0
    var closeCount = 0
    var startedCount = 0
    var completedCount = 0
    var cancelledCount = 0
    var successCount = 0
    var committedWhileHidden = false

    func appear() {
        appearanceCount += 1
        lifetime = UUID()
    }

    func disappear() {
        disappearanceCount += 1
        lifetime = nil
        presentation = nil
        cancel()
    }

    func close() {
        closeCount += 1
        presentation = nil
        cancel()
    }

    func begin(_ data: Data) -> ImportGate? {
        guard window?.isVisible == true, operation == nil, let lifetime else { return nil }
        startedCount += 1
        report = nil
        let id = UUID()
        let gate = ImportGate()
        let worker = Task.detached(priority: .userInitiated) {
            await gate.wait()
            return try DictationVocabularyImport.parse(data, format: .wordList)
        }
        self.worker = worker
        let task = Task { @MainActor in
            defer {
                completedCount += 1
                if operation?.id == id { operation = nil }
            }
            do {
                let document = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                guard operation?.id == id, self.lifetime == lifetime else { return }
                let result = document.merging(into: entries)
                entries = result.entries
                report = result.report
                successCount += 1
                committedWhileHidden = window?.isVisible != true
                presentation = nil
            } catch is CancellationError {
                cancelledCount += 1
            } catch {
                fail("Unexpected import failure \(error)")
            }
        }
        operation = Operation(id: id, task: task)
        return gate
    }

    private func cancel() {
        operation?.task.cancel()
        operation = nil
    }
}

private struct ImportFixtureView: View {
    @ObservedObject var fixture: ImportFixture
    let observesClose: Bool

    var body: some View {
        Text("Settings vocabulary import regression")
            .onAppear { fixture.appear() }
            .onDisappear { fixture.disappear() }
            .modifier(SettingsWindowCloseObserver(window: observesClose ? fixture.window : nil) {
                fixture.close()
            })
    }
}

@MainActor
private final class RetainedSettingsHost {
    let fixture = ImportFixture()
    let controller: NSWindowController
    let hostingView: NSHostingView<ImportFixtureView>

    var window: NSWindow { controller.window! }

    init(observesClose: Bool = true) {
        let window = makeWindow()
        fixture.window = window
        hostingView = NSHostingView(rootView: ImportFixtureView(fixture: fixture, observesClose: observesClose))
        window.contentView = hostingView
        controller = NSWindowController(window: window)
    }

    func show() {
        window.orderFront(nil)
    }
}

@MainActor
private func makeWindow() -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: 320, height: 100),
        styleMask: [.titled, .closable], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    return window
}

private func fail(_ message: String) -> Never {
    fputs("FAIL \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fail(message) }
}

@MainActor
private func waitUntil(_ message: String, _ condition: () async -> Bool) async {
    let deadline = Date().addingTimeInterval(20)
    while !(await condition()) {
        if Date() >= deadline { fail("Timed out waiting for \(message)") }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}

@main
private struct SettingsVocabularyImportCloseRegression {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            if CommandLine.arguments.contains("--original-bug") {
                await reproduceOriginalBug()
            } else {
                await verifyCloseLifecycle()
            }
            exit(0)
        }
        app.run()
    }

    @MainActor
    private static func reproduceOriginalBug() async {
        let host = RetainedSettingsHost(observesClose: false)
        host.show()
        await waitUntil("original view appearance") { host.fixture.appearanceCount == 1 }
        let gate = host.fixture.begin(Data(String(repeating: "a\n", count: 524_288).utf8))!
        await waitUntil("original worker gate") { await gate.isWaiting }
        host.controller.close()
        expect(!host.window.isVisible, "Original host must close")
        await gate.release()
        await waitUntil("original import commit") { host.fixture.completedCount == 1 }
        expect(host.fixture.disappearanceCount == 0, "Retained host must reproduce missing onDisappear")
        expect(host.fixture.entries.map(\.spoken) == ["a"], "Original import must reproduce hidden commit")
        expect(host.fixture.committedWhileHidden, "Original import must commit while its window is hidden")
        print("ORIGINAL BUG reproduced entries=1 successReports=1 whileWindowVisible=false onDisappear=0")
        withExtendedLifetime(host) {}
    }

    @MainActor
    private static func verifyCloseLifecycle() async {
        let host = RetainedSettingsHost()
        let fixture = host.fixture
        host.show()
        await waitUntil("view appearance") { fixture.appearanceCount == 1 }
        let initialLifetime = fixture.lifetime

        let unrelatedGate = fixture.begin(Data("Survives\n".utf8))!
        await waitUntil("unrelated close worker gate") { await unrelatedGate.isWaiting }
        let unrelatedController = NSWindowController(window: makeWindow())
        unrelatedController.window?.orderFront(nil)
        unrelatedController.close()
        expect(fixture.closeCount == 0 && fixture.operation != nil, "Unrelated window close must preserve the pending import")
        expect(fixture.worker?.isCancelled == false, "Unrelated window close must preserve its worker")
        await unrelatedGate.release()
        await waitUntil("unrelated close import") { fixture.completedCount == 1 }
        expect(fixture.entries.map(\.spoken) == ["Survives"], "An unrelated window close must allow the actual vocabulary merge")
        expect(fixture.report == .init(added: 1, duplicates: 0, invalid: 0, overLimit: 0), "A valid import must report one added word")
        print("PASS unrelated window close keeps valid import entries=1 successReports=1")

        fixture.presentation = "file"
        let closeGate = fixture.begin(Data(String(repeating: "a\n", count: 524_288).utf8))!
        await waitUntil("host close worker gate") { await closeGate.isWaiting }
        host.controller.close()
        expect(!host.window.isVisible, "The settings host must close")
        expect(fixture.closeCount == 1 && fixture.operation == nil, "Host close must cancel the pending import before releasing its worker")
        expect(fixture.worker?.isCancelled == true, "Host close must cancel the detached parser worker")
        expect(fixture.presentation == nil, "Host close must dismiss import presentation state")
        expect(fixture.lifetime == initialLifetime && fixture.disappearanceCount == 0, "Host close must preserve the retained view lifetime")
        expect(host.window.contentView === host.hostingView, "Host close must retain the original hosting view")
        await closeGate.release()
        await waitUntil("host close cancellation") { fixture.completedCount == 2 }
        expect(fixture.entries.map(\.spoken) == ["Survives"] && fixture.report == nil, "A cancelled import must neither merge nor report success")
        expect(fixture.cancelledCount == 1 && fixture.successCount == 1, "The closed import must finish as cancellation")
        expect(fixture.begin(Data("Late picker result\n".utf8)) == nil && fixture.startedCount == 2, "A late file picker result must not start an import while the host is hidden")
        print("PASS host close cancels before worker release entries=1 successReports=1 lateBegins=0")

        host.show()
        await waitUntil("same host reopen") { host.window.isVisible }
        expect(fixture.appearanceCount == 1 && fixture.lifetime == initialLifetime, "Reopen must use the same view without depending on another onAppear")
        let reopenGate = fixture.begin(Data("Reopened\n".utf8))!
        await waitUntil("reopened worker gate") { await reopenGate.isWaiting }
        await reopenGate.release()
        await waitUntil("reopened import") { fixture.completedCount == 3 }
        expect(fixture.entries.map(\.spoken) == ["Survives", "Reopened"], "The reopened retained view must accept a fresh import")
        expect(fixture.report == .init(added: 1, duplicates: 0, invalid: 0, overLimit: 0) && fixture.successCount == 2, "The fresh reopened import must report one added word")
        print("PASS same host reopen imports entries=2 successReports=2 onAppear=1")

        fixture.presentation = "paste"
        let repeatedGate = fixture.begin(Data("Must stay cancelled\n".utf8))!
        await waitUntil("repeated close worker gate") { await repeatedGate.isWaiting }
        host.controller.close()
        expect(fixture.closeCount == 2 && fixture.operation == nil && fixture.worker?.isCancelled == true, "Repeated close must cancel the new worker")
        expect(fixture.presentation == nil, "Repeated close must dismiss the paste presentation")
        await repeatedGate.release()
        await waitUntil("repeated close cancellation") { fixture.completedCount == 4 }
        expect(fixture.entries.map(\.spoken) == ["Survives", "Reopened"] && fixture.report == nil, "Repeated close must leave entries and success feedback unchanged")
        expect(fixture.cancelledCount == 2 && fixture.successCount == 2, "Both host closes must cancel exactly their pending imports")
        print("PASS repeated host close cancels entries=2 successReports=2 cancellations=2")
        print("Settings vocabulary import close regressions passed")
        withExtendedLifetime((host, unrelatedController)) {}
    }
}
