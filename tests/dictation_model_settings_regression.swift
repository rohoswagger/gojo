import AppKit
import SwiftUI
import Vision

private struct ExpectedAction {
    let model: DictationModelID
    let title: String
    let disabled: Bool
    var removal = false

    var key: String { "\(model.rawValue)-\(removal ? "remove" : "select")" }
}

@MainActor
private final class FixtureDictation: ObservableObject {
    var selectedModel = DictationModelID.parakeetUnifiedEnglish
    var preparingModel: DictationModelID?
    var switchingModel: DictationModelID?
    var removingModel: DictationModelID?
    var canChangeModel = true
    var observedContrast: ColorSchemeContrast?
    var modelErrors: [DictationModelID: String] = [:]

    func isModelInstalled(_ model: DictationModelID) -> Bool {
        [.parakeetUnifiedEnglish, .whisperSmallEnglish].contains(model)
    }

    func selectModel(_ model: DictationModelID) { fatalError("Render test must not select a model") }
    func downloadModel(_ model: DictationModelID) { fatalError("Render test must not download a model") }
}

@MainActor
private struct ModelSectionFixture: View {
    @ObservedObject var dictation: FixtureDictation
    @State private var modelToRemove: DictationModelID?
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let scheme: ColorScheme

    var body: some View {
        let _ = dictation.observedContrast = colorSchemeContrast
        Form {
            /* PRODUCTION_MODEL_SECTION */
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 440)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(Color(nsColor: .controlAccentColor))
        .preferredColorScheme(scheme)
    }

    func verifyHelpers(_ expected: [ExpectedAction]) -> [String] {
        var failures: [String] = []
        for action in expected where !action.removal {
            if modelButtonTitle(for: action.model) != action.title {
                failures.append("\(action.model): expected title \(action.title)")
            }
            if modelButtonDisabled(for: action.model) != action.disabled {
                failures.append("\(action.model): expected disabled=\(action.disabled)")
            }
        }
        return failures
    }

    /* PRODUCTION_MODEL_HELPERS */
}

private struct ActionPixels {
    let contrast: Double
    let foreground: Double
}

@main
private struct DictationModelSettingsRegression {
    @MainActor
    private static func scenario(_ name: String) -> (FixtureDictation, [ExpectedAction]) {
        let service = FixtureDictation()
        switch name {
        case "enabled":
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: false, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Download", disabled: false),
                .init(model: .whisperSmallEnglish, title: "Use", disabled: false),
                .init(model: .whisperSmallEnglish, title: "Remove", disabled: false, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: false),
            ])
        case "preparing":
            service.canChangeModel = false
            service.preparingModel = .parakeetV3Multilingual
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Downloading…", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Use", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: true),
            ])
        case "switching":
            service.canChangeModel = false
            service.switchingModel = .whisperSmallEnglish
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Download", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Switching…", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: true),
            ])
        case "removing":
            service.canChangeModel = false
            service.removingModel = .whisperSmallEnglish
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Download", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Use", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Removing…", disabled: true, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: true),
            ])
        default:
            service.canChangeModel = false
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Download", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Use", disabled: true),
                .init(model: .whisperSmallEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: true),
            ])
        }
    }

    private static func luminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB)!
        let linear = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent].map {
            $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    private static func pixels(_ observation: VNRecognizedTextObservation, bitmap: NSBitmapImageRep, dark: Bool) -> ActionPixels {
        let box = observation.boundingBox
        let x0 = max(0, Int(box.minX * Double(bitmap.pixelsWide)))
        let x1 = min(bitmap.pixelsWide, Int(ceil(box.maxX * Double(bitmap.pixelsWide))))
        let y0 = max(0, Int((1 - box.maxY) * Double(bitmap.pixelsHigh)))
        let y1 = min(bitmap.pixelsHigh, Int(ceil((1 - box.minY) * Double(bitmap.pixelsHigh))))
        var values: [Double] = []
        for y in y0..<y1 {
            for x in x0..<x1 {
                values.append(luminance(bitmap.colorAt(x: x, y: y)!))
            }
        }
        values.sort()
        let background = values[Int(Double(values.count - 1) * (dark ? 0.1 : 0.9))]
        let foreground = values[Int(Double(values.count - 1) * (dark ? 0.95 : 0.05))]
        return ActionPixels(
            contrast: (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05),
            foreground: foreground
        )
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .punctuationCharacters)
    }

    @MainActor
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var failures: [String] = []
        var evidence: [String] = []
        let (preparationProbe, preparationExpectations) = scenario("preparing")
        preparationProbe.canChangeModel = true
        failures += ModelSectionFixture(dictation: preparationProbe, scheme: .dark)
            .verifyHelpers(preparationExpectations).map { "preparation guard: \($0)" }
        for dark in [false, true] {
            for increased in [false, true] {
                var enabledPixels: [String: ActionPixels] = [:]
                for state in ["enabled", "disabled", "preparing", "switching", "removing"] {
                    let name = "\(dark ? "dark" : "light")-\(increased ? "increased" : "standard")-\(state)"
                    let appearance: NSAppearance.Name = dark
                        ? (increased ? .accessibilityHighContrastDarkAqua : .darkAqua)
                        : (increased ? .accessibilityHighContrastAqua : .aqua)
                    NSApp.appearance = NSAppearance(named: appearance)
                    let (dictation, expected) = scenario(state)
                    let fixture = ModelSectionFixture(dictation: dictation, scheme: dark ? .dark : .light)
                    failures += fixture.verifyHelpers(expected).map { "\(name): \($0)" }
                    let host = NSHostingView(rootView: fixture)
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = CGRect(x: 0, y: 0, width: 500, height: 440)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                        fatalError("Could not allocate the local view snapshot")
                    }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let image = bitmap.cgImage,
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        fatalError("Could not encode the local view snapshot")
                    }
                    try png.write(to: output.appendingPathComponent("\(name).png"))
                    let recognition = VNRecognizeTextRequest()
                    recognition.recognitionLevel = .accurate
                    recognition.usesLanguageCorrection = false
                    try VNImageRequestHandler(cgImage: image).perform([recognition])
                    let observations = recognition.results ?? []
                    let rendered = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    for text in ["Speech models", "Parakeet Unified", "Parakeet v3", "Whisper Small", "Whisper Large v3"] {
                        if !rendered.localizedCaseInsensitiveContains(text) { failures.append("\(name): missing rendered text \(text)") }
                    }
                    let titles = Set(expected.map { normalized($0.title) })
                    let actions = observations.filter {
                        guard let text = $0.topCandidates(1).first?.string else { return false }
                        return titles.contains(normalized(text))
                    }.sorted {
                        abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.04
                            ? $0.boundingBox.midY > $1.boundingBox.midY
                            : $0.boundingBox.minX < $1.boundingBox.minX
                    }
                    if actions.count != expected.count { failures.append("\(name): expected six rendered action labels, found \(actions.count)") }
                    var measurements: [String] = []
                    var currentPixels: [String: ActionPixels] = [:]
                    for (action, expectation) in zip(actions, expected) {
                        let title = action.topCandidates(1).first!.string
                        if normalized(title) != normalized(expectation.title) {
                            failures.append("\(name): expected rendered \(expectation.title), found \(title)")
                        }
                        let measurement = pixels(action, bitmap: bitmap, dark: dark)
                        currentPixels[expectation.key] = measurement
                        let minimum = expectation.disabled ? 2.0 : 4.5
                        if measurement.contrast < minimum {
                            failures.append("\(name): \(title) contrast \(String(format: "%.2f", measurement.contrast)):1 is below \(minimum):1")
                        }
                        if expectation.disabled {
                            let counterpart = enabledPixels[expectation.key]
                                ?? enabledPixels["\(DictationModelID.whisperSmallEnglish.rawValue)-select"]
                                ?? currentPixels["\(DictationModelID.whisperSmallEnglish.rawValue)-select"]
                            if let counterpart, measurement.contrast >= counterpart.contrast * 0.85 {
                                failures.append("\(name): disabled \(title) must be visibly muted relative to enabled action text")
                            }
                        }
                        measurements.append("\(title): \(String(format: "%.2f", measurement.contrast)):1; disabled=\(expectation.disabled); glyph luminance=\(String(format: "%.3f", measurement.foreground))")
                    }
                    let selectedKey = "\(DictationModelID.parakeetUnifiedEnglish.rawValue)-select"
                    let useKey = "\(DictationModelID.whisperSmallEnglish.rawValue)-select"
                    if state == "enabled" {
                        if let selected = currentPixels[selectedKey], let use = currentPixels[useKey], selected.contrast >= use.contrast * 0.85 {
                            failures.append("\(name): disabled Selected must be visibly muted relative to enabled Use in the same capture")
                        }
                        enabledPixels = currentPixels.filter { key, _ in expected.contains { $0.key == key && !$0.disabled } }
                    }
                    try ("\(rendered)\n\nAction text pixels:\n\(measurements.joined(separator: "\n"))\n").write(
                        to: output.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8
                    )
                    evidence.append("- \(name): production titles and explicit expected helper outcomes checked; SwiftUI contrast environment \(String(describing: dictation.observedContrast)).\n  \(measurements.joined(separator: "; "))")
                }
            }
        }
        let report = """
        # Speech models render regression

        The test extracts the production Speech models section and its title/disabled helpers from SettingsView.swift. It compiles them with the real descriptors and renders an offscreen 500-point grouped Form. Fixtures cover selected, available, blocked, preparing, switching, and removing actions. Each primary action has an explicit expected title and disabled result. An additional preparation probe leaves canChangeModel true to independently check that an active preparation disables the model helpers. The extraction asserts that Remove retains its inline .disabled(!dictation.canChangeModel) predicate.

        \(evidence.joined(separator: "\n"))

        Pixel contrast uses the 5th/95th-percentile glyph luminance and 10th/90th-percentile background luminance within Vision-recognized text boxes. Enabled action text must reach 4.5:1. Disabled text has a 2.0:1 readability guard, not a WCAG requirement. Selected must have at least 15% lower contrast than enabled Use in the same image; other blocked actions must have at least 15% lower contrast than their enabled counterparts. These comparisons preserve visible disabled affordances instead of requiring full-bright inactive labels.

        Action closures compile and render but are never invoked; fake select/download methods trap if called. Disabled-state assertions call the extracted production helpers; Remove's predicate is checked structurally. No live interaction or AX enabled-state assertion is claimed. Native enabled/disabled treatments are saved as PNGs.

        The host is never shown. Aqua/Dark Aqua and accessibility-high-contrast NSAppearance are applied locally; the recorded SwiftUI contrast environment may remain standard. This does not exercise the system Increase Contrast preference. No system appearance, Night Shift, TCC, app data, microphone, network, inference, or model operation is accessed. Live navigation, real button activation, display calibration, and Night Shift's hardware transform are not tested.

        Result: \(failures.isEmpty ? "PASS" : "FAIL")
        \(failures.joined(separator: "\n"))
        """
        try report.write(to: output.appendingPathComponent("render-report.md"), atomically: true, encoding: .utf8)
        if !failures.isEmpty {
            failures.forEach { print($0) }
            exit(1)
        }
        print("Speech models production render regression passed in 20 states. Artifacts: \(output.path)")
    }
}
