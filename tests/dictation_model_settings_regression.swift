import AppKit
import SwiftUI
import Vision

private struct ExpectedAction {
    let model: DictationModelID
    let title: String
    let disabled: Bool
    var removal = false
}

@MainActor
private final class FixtureDictation: ObservableObject {
    var selectedModel = DictationModelID.parakeetUnifiedEnglish
    var preparingModel: DictationModelID?
    var modelDownload: DictationModelDownload?
    var switchingModel: DictationModelID?
    var removingModel: DictationModelID?
    var canChangeModel = true
    var modelErrors: [DictationModelID: String] = [:]
    var activePracticeFieldID: UUID?
    var state = DictationState.idle
    var selectedIntent = DictationSessionIntent.standard
    var spokenCommandMode = DictationSpokenCommandMode.off
    var commandLanguage = DictationCommandLanguage.english
    var currentModelCapabilities: DictationModelCapabilities? = DictationModelDescriptor.descriptor(for: .parakeetUnifiedEnglish).capabilities
    var recognitionLanguage = DictationLanguageSelection.fixed("en")
    var translatesToEnglish = false
    var previewEnabled = false
    var cuesEnabled = false
    var residencyPolicy = DictationResidencyPolicy.keepWarm
    var inputDevices = [DictationInputDevice(id: "test-microphone", name: "Built-in microphone")]
    var selectedInput = DictationInputSelection.systemDefault
    var currentInputName: String?
    var adaptiveSpeech = true

    func setIntent(_ value: DictationSessionIntent) { fatalError("Render must not change intent") }
    func setSpokenCommandMode(_ value: DictationSpokenCommandMode) { fatalError("Render must not change commands") }
    func setCommandLanguage(_ value: DictationCommandLanguage) { fatalError("Render must not change language") }
    func setRecognitionLanguage(_ value: DictationLanguageSelection) { fatalError("Render must not change recognition") }
    func setTranslatesToEnglish(_ value: Bool) { fatalError("Render must not change translation") }
    func setPreviewEnabled(_ value: Bool) { fatalError("Render must not change preview") }
    func setCuesEnabled(_ value: Bool) { fatalError("Render must not change cues") }
    func setResidencyPolicy(_ value: DictationResidencyPolicy) { fatalError("Render must not change residency") }
    func setInput(_ value: DictationInputSelection) { fatalError("Render must not change input") }
    func setAdaptiveSpeech(_ value: Bool) { fatalError("Render must not change speech gate") }
    func beginPractice(fieldID: UUID) { fatalError("Render must not start recording") }
    func cancelPractice(fieldID: UUID) {}
    func finishVoiceMode() { fatalError("Render must not finish recording") }
    func refreshInputDevices() {}

    func isModelInstalled(_ model: DictationModelID) -> Bool {
        [.parakeetUnifiedEnglish, .whisperSmallEnglish].contains(model)
    }

    func selectModel(_ model: DictationModelID) { fatalError("Render test must not select a model") }
    func downloadModel(_ model: DictationModelID) { fatalError("Render test must not download a model") }
}

@MainActor
private struct ExperienceSectionsFixture: View {
    @ObservedObject var dictation: FixtureDictation
    @State private var practiceFieldID = UUID()
    let scheme: ColorScheme

    var body: some View {
        Form {
            practiceSection
            experienceSection
            inputSection
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 1500)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(Color(nsColor: .controlAccentColor))
        .preferredColorScheme(scheme)
    }

    /* PRODUCTION_EXPERIENCE_SECTIONS */
}

@MainActor
private struct ModelSectionFixture: View {
    @ObservedObject var dictation: FixtureDictation
    @State private var modelToRemove: DictationModelID?
    let scheme: ColorScheme

    var body: some View {
        Form {
            /* PRODUCTION_MODEL_SECTION */
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 700)
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
        case "enabled", "failure":
            if name == "failure" {
                service.modelErrors[.parakeetV3Multilingual] = "Could not download this model. Check your connection and try again."
            }
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: false, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Download", disabled: false),
                .init(model: .underdogBark3CleanEnglish, title: "Download", disabled: false),
                .init(model: .underdogBark3English, title: "Download", disabled: false),
                .init(model: .whisperSmallEnglish, title: "Use", disabled: false),
                .init(model: .whisperSmallEnglish, title: "Remove", disabled: false, removal: true),
                .init(model: .whisperLargeV3, title: "Download", disabled: false),
            ])
        case "preparing", "downloading", "verifying":
            service.canChangeModel = false
            service.preparingModel = .parakeetV3Multilingual
            let phase: DictationModelDownload.Phase
            switch name {
            case "downloading": phase = .downloading(0.42)
            case "verifying": phase = .verifying
            default: phase = .preparing
            }
            service.modelDownload = DictationModelDownload(id: UUID(), model: .parakeetV3Multilingual, phase: phase)
            return (service, [
                .init(model: .parakeetUnifiedEnglish, title: "Selected", disabled: true),
                .init(model: .parakeetUnifiedEnglish, title: "Remove", disabled: true, removal: true),
                .init(model: .parakeetV3Multilingual, title: "Downloading…", disabled: true),
                .init(model: .underdogBark3CleanEnglish, title: "Download", disabled: true),
                .init(model: .underdogBark3English, title: "Download", disabled: true),
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
                .init(model: .underdogBark3CleanEnglish, title: "Download", disabled: true),
                .init(model: .underdogBark3English, title: "Download", disabled: true),
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
                .init(model: .underdogBark3CleanEnglish, title: "Download", disabled: true),
                .init(model: .underdogBark3English, title: "Download", disabled: true),
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
                .init(model: .underdogBark3CleanEnglish, title: "Download", disabled: true),
                .init(model: .underdogBark3English, title: "Download", disabled: true),
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

    private static func pixels(_ box: CGRect, bitmap: NSBitmapImageRep, dark: Bool, scale: Int) -> ActionPixels {
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
        let background = dark ? values.first! : values.last!
        let coreCount = min(values.count, 3 * scale * scale)
        let core = dark ? Array(values.suffix(coreCount)) : Array(values.prefix(coreCount))
        let foreground = core.reduce(0, +) / Double(core.count)
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
            for scale in [1, 2] {
                for state in ["enabled", "disabled", "preparing", "downloading", "verifying", "failure", "switching", "removing"] {
                    let name = "\(dark ? "dark" : "light")-\(scale)x-\(state)"
                    let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
                    NSApp.appearance = NSAppearance(named: appearance)
                    let (dictation, expected) = scenario(state)
                    let fixture = ModelSectionFixture(dictation: dictation, scheme: dark ? .dark : .light)
                    failures += fixture.verifyHelpers(expected).map { "\(name): \($0)" }
                    let host = NSHostingView(rootView: fixture)
                    host.appearance = NSAppearance(named: appearance)
                    host.frame = CGRect(x: 0, y: 0, width: 500, height: 700)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                    host.layoutSubtreeIfNeeded()
                    guard let bitmap = NSBitmapImageRep(
                        bitmapDataPlanes: nil, pixelsWide: 500 * scale, pixelsHigh: 700 * scale,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                    ) else {
                        fatalError("Could not allocate the local view snapshot")
                    }
                    bitmap.size = host.bounds.size
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let image = bitmap.cgImage,
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        fatalError("Could not encode the local view snapshot")
                    }
                    try png.write(to: output.appendingPathComponent("\(name).png"))
                    let recognition = VNRecognizeTextRequest()
                    recognition.recognitionLevel = .accurate
                    recognition.usesLanguageCorrection = true
                    try VNImageRequestHandler(cgImage: image).perform([recognition])
                    let observations = recognition.results ?? []
                    let rendered = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    for text in ["Speech models", "Parakeet Unified", "Parakeet v3", "Underdog Bark 3.0 Clean", "Underdog Bark 3.0", "Whisper Small", "Whisper Large v3"] {
                        if !rendered.localizedCaseInsensitiveContains(text) { failures.append("\(name): missing rendered text \(text)") }
                    }
                    let progressLabels = ["Preparing download", "File download progress", "Verifying"]
                    let expectedProgress: String?
                    switch state {
                    case "preparing": expectedProgress = progressLabels[0]
                    case "downloading": expectedProgress = progressLabels[1]
                    case "verifying": expectedProgress = progressLabels[2]
                    default: expectedProgress = nil
                    }
                    for label in progressLabels {
                        let count = rendered.components(separatedBy: label).count - 1
                        let expectedCount = label == expectedProgress ? 1 : 0
                        if count != expectedCount { failures.append("\(name): expected \(expectedCount) progress label \(label), found \(count)") }
                    }
                    if state == "downloading", !rendered.contains("42%") { failures.append("\(name): partial download percentage is missing") }
                    if state == "failure", !rendered.contains("Check your connection") { failures.append("\(name): retryable download error is missing") }
                    let titles = Set(expected.map { normalized($0.title) })
                    var actions: [(title: String, boundingBox: CGRect)] = []
                    for observation in observations {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        let line = candidate.string
                        for word in line.split(whereSeparator: \.isWhitespace) {
                            let title = String(word)
                            guard titles.contains(normalized(title)),
                                  let rectangle = try candidate.boundingBox(for: word.startIndex..<word.endIndex),
                                  rectangle.boundingBox.minX > 0.6 else { continue }
                            actions.append((title, rectangle.boundingBox))
                        }
                    }
                    actions.sort {
                        abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.04
                            ? $0.boundingBox.midY > $1.boundingBox.midY
                            : $0.boundingBox.minX < $1.boundingBox.minX
                    }
                    if actions.count != expected.count { failures.append("\(name): expected \(expected.count) rendered action labels, found \(actions.count)") }
                    var measurements: [String] = []
                    for (action, expectation) in zip(actions, expected) {
                        let title = action.title
                        if normalized(title) != normalized(expectation.title) {
                            failures.append("\(name): expected rendered \(expectation.title), found \(title)")
                        }
                        let measurement = pixels(action.boundingBox, bitmap: bitmap, dark: dark, scale: scale)
                        let minimum = expectation.disabled ? 2.0 : 4.5
                        if measurement.contrast < minimum {
                            failures.append("\(name): \(title) contrast \(String(format: "%.2f", measurement.contrast)):1 is below \(minimum):1")
                        }
                        measurements.append("\(title): \(String(format: "%.2f", measurement.contrast)):1; disabled=\(expectation.disabled); glyph luminance=\(String(format: "%.3f", measurement.foreground))")
                    }
                    try ("\(rendered)\n\nAction text pixels:\n\(measurements.joined(separator: "\n"))\n").write(
                        to: output.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8
                    )
                    evidence.append("- \(name): production titles, expected availability, and \(scale)x rendered text checked.\n  \(measurements.joined(separator: "; "))")
                }
            }
        }
        for dark in [false, true] {
            for state in ["unified", "whisper", "v3", "english", "literal", "cloud"] {
                let service = FixtureDictation()
                var required = ["Try dictation", "Dictation behavior", "Audio input", "Intent", "Quiet sound feedback", "Local model memory", "Microphone", "Adapt to quiet speech"]
                var absent: [String] = []
                switch state {
                case "whisper":
                    service.currentModelCapabilities = DictationModelDescriptor.descriptor(for: .whisperLargeV3).capabilities
                    service.recognitionLanguage = .automatic
                    service.spokenCommandMode = .punctuationAndCode
                    required += ["Automatic detection", "Translate to English", "Command language"]
                    absent += ["Draft preview"]
                case "v3":
                    service.currentModelCapabilities = DictationModelDescriptor.descriptor(for: .parakeetV3Multilingual).capabilities
                    service.recognitionLanguage = .automatic
                    required += ["Automatic detection"]
                    absent += ["Translate to English", "Draft preview"]
                case "english":
                    service.currentModelCapabilities = DictationModelDescriptor.descriptor(for: .whisperSmallEnglish).capabilities
                    required += ["English"]
                    absent += ["Translate to English", "Draft preview", "Automatic detection"]
                case "literal":
                    service.selectedIntent = .literal
                    service.spokenCommandMode = .punctuation
                    required += ["Literal", "Draft preview"]
                    absent += ["Command language", "Translate to English"]
                case "cloud":
                    service.currentModelCapabilities = nil
                    absent += ["Recognition language", "Translate to English", "Draft preview"]
                default:
                    required += ["Draft preview", "English"]
                    absent += ["Translate to English", "Automatic detection"]
                }
                let name = "experience-\(dark ? "dark" : "light")-\(state)"
                let appearance: NSAppearance.Name = dark ? .darkAqua : .aqua
                NSApp.appearance = NSAppearance(named: appearance)
                let host = NSHostingView(rootView: ExperienceSectionsFixture(dictation: service, scheme: dark ? .dark : .light))
                host.appearance = NSAppearance(named: appearance)
                host.frame = CGRect(x: 0, y: 0, width: 620, height: 1500)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                host.layoutSubtreeIfNeeded()
                guard let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 1240, pixelsHigh: 3000,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { fatalError("Could not allocate experience snapshot") }
                bitmap.size = host.bounds.size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let image = bitmap.cgImage, let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not encode experience snapshot") }
                try png.write(to: output.appendingPathComponent(name + ".png"))
                let regions = [
                    CGRect(x: 0, y: 0, width: 1, height: 1),
                    CGRect(x: 0, y: 0, width: 1, height: 2.0 / 3.0),
                    CGRect(x: 0, y: 1.0 / 3.0, width: 1, height: 2.0 / 3.0)
                ]
                var recognizedRegions: [String] = []
                for region in regions {
                    let recognition = VNRecognizeTextRequest()
                    recognition.recognitionLevel = .accurate
                    recognition.usesLanguageCorrection = false
                    recognition.regionOfInterest = region
                    try VNImageRequestHandler(cgImage: image).perform([recognition])
                    recognizedRegions.append((recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
                }
                let rendered = recognizedRegions.joined(separator: "\n")
                for text in required where !rendered.localizedCaseInsensitiveContains(text) { failures.append("\(name): missing \(text)") }
                let renderedLines = rendered.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                for text in absent where renderedLines.contains(text.lowercased()) { failures.append("\(name): unsupported control \(text) was visible") }
                try rendered.write(to: output.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
                evidence.append("- \(name): production practice, behavior, input, and capability controls rendered and checked.")
            }
        }
        let report = """
        # Speech models render regression

        The test extracts the production Speech models section and its title/disabled helpers from SettingsView.swift. It compiles them with the real descriptors and renders an offscreen 500-by-700-point grouped Form in light and dark appearances at explicit 1x and 2x scales. Fixtures cover selected, available, blocked, preparing, partial download, verification, retryable failure, switching, and removing actions. Each active download has one progress label under its model. Partial download renders 42% file progress. Preparation and verification render native indeterminate bars. Each primary action has an explicit expected title and disabled result. An additional preparation probe leaves canChangeModel true to independently check that an active preparation disables the model helpers. Extraction checks both production disabled bindings, semantic primary/secondary label styling, and the action tint.

        \(evidence.joined(separator: "\n"))

        Vision verifies the six action labels in each capture. Contrast compares the button background with the mean of the three most opaque glyph pixels per square point inside each recognized label. Sampling glyph cores avoids treating antialiasing coverage or OCR box area as the foreground color. Enabled action text must reach 4.5:1; disabled text retains a 2.0:1 readability guard. The production disabled predicates and semantic secondary styling preserve disabled affordances. No fixed dimming percentage is imposed because AppKit can increase inactive text contrast for accessibility.

        Action closures compile and render but are never invoked; fake select/download methods trap if called. Disabled-state assertions call the extracted production helpers; Remove's predicate is checked structurally. No live interaction or AX enabled-state assertion is claimed. Native enabled/disabled treatments are saved as PNGs.

        Twelve additional light and dark captures extract the production practice, behavior, and audio input sections at an explicit 2x scale. They cover Unified draft preview, Whisper language selection and translation, v3 automatic detection, fixed English, Literal command restrictions, and cloud capabilities. OCR reads the full image and two overlapping regions, then checks required labels and the absence of unsupported control labels. These captures use the real empty NSTextView practice field. No mocked transcript or recording operation runs.

        The host is never shown. Aqua/Dark Aqua are applied locally. The current system Increase Contrast preference is \(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast); this test honors it without changing it. Assigning an accessibility-high-contrast NSAppearance did not change SwiftUI's contrast environment, so no separate Increase Contrast coverage is claimed. No system appearance, Night Shift, TCC, app data, microphone, network, inference, or model operation is changed. Live navigation, real button activation, display calibration, and Night Shift's hardware transform are not tested.

        Result: \(failures.isEmpty ? "PASS" : "FAIL")
        \(failures.joined(separator: "\n"))
        """
        try report.write(to: output.appendingPathComponent("render-report.md"), atomically: true, encoding: .utf8)
        if !failures.isEmpty {
            failures.forEach { print($0) }
            exit(1)
        }
        print("Production Settings render regression passed in 32 model states and 12 experience states. Artifacts: \(output.path)")
    }
}
