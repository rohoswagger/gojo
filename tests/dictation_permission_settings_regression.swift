import AppKit
import AVFoundation
import SwiftUI
import Vision

@MainActor
private final class FixtureDictation: ObservableObject {
    @Published var microphoneTestState: DictationMicrophoneDiagnosticState = .idle
    var canTestMicrophone = true
    func testMicrophone() { fatalError("The render test must not start microphone capture") }
    func cancelMicrophoneTest() { fatalError("The render test must not cancel real capture") }
}

@MainActor
private final class FixtureMicrophonePermission: ObservableObject {
    @Published var status: AVAuthorizationStatus = .notDetermined
    var isRequesting = false
    func requestIfNeeded() async { fatalError("The render test must not request microphone permission") }
}

@MainActor
private final class FixtureShortcutMonitor: ObservableObject {
    @Published var helperState: DictationHelperState = .checking
    @Published var accessibilityState: DictationAccessibilityState = .unknown
    @Published var shortcutReadiness: DictationShortcutReadiness = .stopped
    func start(promptIfNeeded: Bool = false) async { fatalError("The render test must not contact the helper or request Accessibility") }
}

@MainActor
private struct PermissionSectionFixture: View {
    @ObservedObject var dictation: FixtureDictation
    @ObservedObject var microphonePermission: FixtureMicrophonePermission
    @ObservedObject var shortcutMonitor: FixtureShortcutMonitor

    var body: some View {
        Form { permissionSection }
            .formStyle(.grouped)
            .frame(width: 500, height: 760)
            .background(Color(NSColor.windowBackgroundColor))
            .preferredColorScheme(.dark)
    }

    /* PRODUCTION_PERMISSION_MEMBERS */
}

private struct AccessibilityRecord {
    let role: String
    let label: String
    let value: String
    let enabled: Bool
}

@main
private struct DictationPermissionSettingsRegression {
    @MainActor private static var failures: [String] = []

    @MainActor
    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message) }
    }

    @MainActor
    private static func accessibilityRecords(_ object: Any, seen: inout Set<ObjectIdentifier>) -> [AccessibilityRecord] {
        guard let element = object as? NSObjectProtocol else { return [] }
        let identity = ObjectIdentifier(element)
        guard seen.insert(identity).inserted else { return [] }
        guard let node = element as? NSAccessibilityProtocol else { return [] }
        var result = [AccessibilityRecord(
            role: node.accessibilityRole()?.rawValue ?? "",
            label: node.accessibilityLabel() ?? "",
            value: node.accessibilityValue().map { String(describing: $0) } ?? "",
            enabled: node.isAccessibilityEnabled()
        )]
        for child in node.accessibilityChildren() ?? [] {
            result += accessibilityRecords(child, seen: &seen)
        }
        return result
    }

    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let dictation = FixtureDictation()
        let microphone = FixtureMicrophonePermission()
        let monitor = FixtureShortcutMonitor()
        let host = NSHostingView(rootView: PermissionSectionFixture(
            dictation: dictation, microphonePermission: microphone, shortcutMonitor: monitor
        ))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 760)
        var evidence: [String] = []
        var exportedButtonCount = 0
        let connected = HelperPermissionStatus(instanceID: UUID(), accessibilityAuthorized: true)
        let cases = ["helper-unavailable", "permission-pending", "microphone-denied", "microphone-restricted", "ready"]
        for name in cases {
            monitor.helperState = name == "helper-unavailable" ? .unavailable(.timedOut) : .available(connected)
            monitor.accessibilityState = name == "helper-unavailable" ? .unknown : name == "permission-pending" ? .requesting : .trusted
            monitor.shortcutReadiness = name == "helper-unavailable" ? .unavailable(.helper(.timedOut)) : name == "permission-pending" ? .awaitingAccessibility : .ready
            microphone.status = name == "microphone-denied" ? .denied : name == "microphone-restricted" ? .restricted : name == "ready" ? .authorized : .notDetermined
            dictation.microphoneTestState = name == "ready" ? .passed : .idle
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Could not allocate the local view snapshot")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]), let image = bitmap.cgImage else {
                fatalError("Could not encode the local view snapshot")
            }
            try png.write(to: output.appendingPathComponent("settings-\(name).png"))
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([recognition])
            let rendered = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            var seen: Set<ObjectIdentifier> = []
            let records = accessibilityRecords(host, seen: &seen)
            exportedButtonCount += records.filter { $0.role == NSAccessibility.Role.button.rawValue }.count
            let exported = records.map { "\($0.role) | \($0.label) | \($0.value) | enabled=\($0.enabled)" }.joined(separator: "\n")
            try ("Rendered OCR:\n\(rendered)\n\nLocal accessibility tree:\n\(exported)\n").write(
                to: output.appendingPathComponent("settings-\(name).txt"), atomically: true, encoding: .utf8
            )
            func contains(_ text: String) -> Bool {
                rendered.localizedCaseInsensitiveContains(text) || records.contains { "\($0.label) \($0.value)".localizedCaseInsensitiveContains(text) }
            }
            expect(contains("Permissions") && contains("Gojo helper") && contains("Microphone test"), "\(name): production section must render its header and status rows")
            switch name {
            case "helper-unavailable":
                expect(contains("Unavailable") && contains("Not checked") && contains("Retry connection"), "Unavailable helper must remain distinct from Accessibility denial and offer a connection retry")
                expect(!contains("Enable Accessibility") && !contains("Denied") && !contains("Required"), "Unavailable helper must not show an Accessibility permission action or denial")
                expect(contains("Request microphone access"), "Unasked microphone permission must offer a request")
            case "permission-pending":
                expect(contains("Connected") && contains("Waiting for permission") && contains("Waiting for Accessibility"), "Pending helper authorization must render its in-progress statuses")
                expect(contains("Request microphone access") && contains("Enable Accessibility") && contains("Open Accessibility Settings"), "Pending permissions must render their recovery controls")
                let enable = records.filter { $0.label == "Enable Accessibility" && $0.role == NSAccessibility.Role.button.rawValue }
                if !enable.isEmpty { expect(enable.allSatisfy { !$0.enabled }, "Accessibility request action must be disabled while requesting") }
            case "microphone-denied":
                expect(contains("Denied") && contains("Allow Gojo in System Settings") && contains("Open Microphone Settings"), "Denied microphone permission must render actionable System Settings guidance")
                expect(!contains("Request microphone access") && !contains("Enable Accessibility"), "Denied microphone permission must not offer a fresh permission request or unrelated Accessibility action")
            case "microphone-restricted":
                expect(contains("Restricted") && contains("Screen Time") && contains("device management") && contains("Open Microphone Settings"), "Restricted microphone permission must explain Screen Time or device management recovery")
                expect(!contains("Request microphone access"), "Restricted microphone permission must not offer a fresh permission request")
            default:
                expect(contains("Connected") && contains("Allowed") && contains("Active") && contains("Audio received") && contains("Test microphone"), "Authorized permissions must render active shortcut and passed audio test")
                expect(!contains("Retry connection") && !contains("Enable Accessibility") && !contains("Open Microphone Settings"), "Ready permissions must omit recovery actions")
            }
            let testButtons = records.filter { $0.label == "Test microphone" && $0.role == NSAccessibility.Role.button.rawValue }
            if !testButtons.isEmpty { expect(testButtons.allSatisfy { $0.enabled == (name == "ready") }, "\(name): microphone test enabled state must follow authorization") }
            evidence.append("- \(name): rendered text checked; \(records.count) local accessibility records; \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) PNG.")
        }
        let report = """
        # Permissions section render regression

        The test extracts the production `permissionSection` and its six computed label and guidance helpers with balanced braces, compiles the real helper and microphone diagnostic state enums, and hosts that code in a 500-point-wide dark grouped Form. The width matches the 700-point settings window minus its 200-point sidebar.

        \(evidence.joined(separator: "\n"))

        Screenshots and text exports use the `settings-` prefix in this directory. Assertions inspect rendered image text with Vision and the local view's exported accessibility records. Positive row and status assertions ensure an empty section fails. Negative checks cover misleading permission actions and helper denial labels.

        No test button is invoked. Permission request, helper connection, and capture fakes fail immediately if invoked. The host is never shown, and the test does not query TCC, connect to the app, inspect another application's accessibility tree, or control desktop input. This is an offscreen component render test. It does not prove live Gojo navigation, real permission dialogs, system Settings links, or microphone capture. Disabled controls are asserted only when the local accessibility tree exports button records. This run exported \(exportedButtonCount) buttons. \(exportedButtonCount == 0 ? "Button enabled-state assertions were unavailable; saved PNGs provide visual evidence only." : "Enabled-state assertions ran for the exported test and Accessibility request controls.")

        Result: \(failures.isEmpty ? "PASS" : "FAIL")
        \(failures.joined(separator: "\n"))
        """
        try report.write(to: output.appendingPathComponent("settings-render-report.md"), atomically: true, encoding: .utf8)
        guard failures.isEmpty else {
            failures.forEach { print($0) }
            exit(1)
        }
        print("Permissions settings production render regressions passed for \(cases.count) states. Artifacts: \(output.path)")
    }
}
