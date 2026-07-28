import Foundation

func assertCondition(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

actor EventLog {
    private var values: [String] = []

    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

actor FakeTargetProvider: DictationTargetCapturing {
    typealias Target = String

    let log: EventLog
    private(set) var captures = 0

    init(log: EventLog) { self.log = log }

    func captureTarget() async throws -> String {
        captures += 1
        await log.append("target")
        return "focused-field"
    }
}

actor FakeAudioCapture: DictationAudioCapturing {
    let log: EventLog
    var permission = true
    var audio = DictationAudio(samples: Array(repeating: 0.25, count: 3_200))
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancellations = 0
    private var cancellationDelay: Duration = .zero

    init(log: EventLog) { self.log = log }

    func requestPermission() async -> Bool {
        await log.append("permission")
        return permission
    }

    func startCapture() async throws {
        starts += 1
        await log.append("start")
    }

    func stopCapture() async throws -> DictationAudio {
        stops += 1
        await log.append("stop")
        return audio
    }

    func cancelCapture() async {
        cancellations += 1
        await log.append("cancel-audio")
        try? await Task.sleep(for: cancellationDelay)
    }

    func setAudio(_ audio: DictationAudio) { self.audio = audio }
    func setCancellationDelay(_ delay: Duration) { cancellationDelay = delay }
}

actor FakeTranscriber: LocalDictationTranscribing {
    let log: EventLog
    private(set) var calls = 0

    init(log: EventLog) { self.log = log }

    func transcribe(_ audio: DictationAudio) async throws -> String {
        calls += 1
        await log.append("transcribe")
        return "  locally transcribed  "
    }
}

actor TeardownAwareTranscriber: LocalDictationTranscribing {
    private var calls = 0
    private var activeInferences = 0
    private var maximumConcurrentInferences = 0

    func transcribe(_ audio: DictationAudio) async throws -> String {
        calls += 1
        let call = calls
        activeInferences += 1
        maximumConcurrentInferences = max(maximumConcurrentInferences, activeInferences)
        defer { activeInferences -= 1 }

        if call == 1 {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                // Simulate Core ML work that needs time to unwind after its
                // Swift task receives cancellation.
                await Task.detached {
                    try? await Task.sleep(for: .milliseconds(60))
                }.value
                throw CancellationError()
            }
        }
        return "replacement transcript"
    }

    func cancelTranscription() async {
        while activeInferences > 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func activeCount() -> Int { activeInferences }
    func maximumConcurrentCount() -> Int { maximumConcurrentInferences }
}

actor FakeInserter: DictationTextInserting {
    typealias Target = String

    let log: EventLog
    private(set) var insertions: [(String, String)] = []

    init(log: EventLog) { self.log = log }

    func insert(_ text: String, into target: String) async throws {
        insertions.append((text, target))
        await log.append("insert")
    }

    func insertionCount() -> Int { insertions.count }
}

private struct FriendlyTargetError: LocalizedError {
    var errorDescription: String? { "Enable the required permission in System Settings." }
}

actor FailingTargetProvider: DictationTargetCapturing {
    typealias Target = String

    func captureTarget() async throws -> String {
        throw FriendlyTargetError()
    }
}

actor GatedTargetProvider: DictationTargetCapturing {
    typealias Target = String

    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func captureTarget() async throws -> String {
        if !released {
            await withCheckedContinuation { continuation = $0 }
        }
        return "focused-before-hud"
    }

    func isWaiting() -> Bool { continuation != nil }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

final class StateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [DictationState] = []

    func record(_ state: DictationState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    func snapshot() -> [DictationState] {
        lock.lock()
        defer { lock.unlock() }
        return states
    }
}

func waitForState<T, A, R, I>(
    _ expected: DictationState,
    controller: DictationController<T, A, R, I>,
    message: String
) async where T: DictationTargetCapturing,
              A: DictationAudioCapturing,
              R: LocalDictationTranscribing,
              I: DictationTextInserting,
              T.Target == I.Target {
    for _ in 0..<200 {
        if await controller.state == expected { return }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    let actual = await controller.state
    fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
    exit(1)
}

@main
struct DictationRegressionRunner {
    static func main() async {
        testReducerPolicy()
        testModelDownloadPolicy()
        testModelStorageRemoval()
        testWhisperModelCatalog()
        testModifierOnlyShortcutPolicy()
        testAudioNormalization()
        testAudioLevelMeter()
        await testShortcutEventOrdering()
        await testTargetCapturedBeforeHUDStatePublication()
        await testSuccessfulControllerFlow()
        await testShortAudioAndCancellation()
        await testRapidCancelThenRestart()
        await testTranscriptionTeardownBeforeRestart()
        await testWatchdogAndLocalizedErrors()
        print("dictation-regression-pass")
    }

    static func testModelDownloadPolicy() {
        assertCondition(
            DictationModelRequest.settingsDownload.allowsDownload,
            "the settings button should be allowed to download the speech model"
        )
        assertCondition(
            !DictationModelRequest.transcription.allowsDownload,
            "starting dictation must never download a speech model"
        )
    }

    static func testModelStorageRemoval() {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let repositoryRoot = temporaryRoot.appendingPathComponent("repository", isDirectory: true)
        let metadataRoot = repositoryRoot
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)

        do {
            try fileManager.createDirectory(at: metadataRoot, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: temporaryRoot) }

            let modelDirectory = repositoryRoot.appendingPathComponent("model", isDirectory: true)
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try "weights".write(
                to: modelDirectory.appendingPathComponent("weights.bin"),
                atomically: true,
                encoding: .utf8
            )
            let modelMetadata = metadataRoot.appendingPathComponent("model", isDirectory: true)
            try fileManager.createDirectory(at: modelMetadata, withIntermediateDirectories: true)
            try "metadata".write(
                to: modelMetadata.appendingPathComponent("download.json"),
                atomically: true,
                encoding: .utf8
            )
            let sentinel = repositoryRoot.appendingPathComponent("keep.txt")
            let metadataSentinel = metadataRoot.appendingPathComponent("keep.txt")
            try "keep".write(to: sentinel, atomically: true, encoding: .utf8)
            try "keep metadata".write(to: metadataSentinel, atomically: true, encoding: .utf8)

            try DictationModelStorage.removeAllowlistedItems(
                from: repositoryRoot,
                topLevelItems: ["model"]
            )

            assertCondition(
                !fileManager.fileExists(atPath: modelDirectory.path),
                "model removal should delete the allowlisted repository item"
            )
            assertCondition(
                !fileManager.fileExists(atPath: modelMetadata.path),
                "model removal should delete matching download metadata"
            )
            assertCondition(
                fileManager.fileExists(atPath: sentinel.path),
                "model removal should preserve unrelated repository files"
            )
            assertCondition(
                fileManager.fileExists(atPath: metadataSentinel.path),
                "model removal should preserve unrelated download metadata"
            )

            let outsideSentinel = temporaryRoot.appendingPathComponent("outside-sentinel.txt")
            try "still here".write(to: outsideSentinel, atomically: true, encoding: .utf8)
            for unsafeName in ["", ".", "..", "../outside-sentinel.txt", "nested/item", "volume:item"] {
                do {
                    try DictationModelStorage.removeAllowlistedItems(
                        from: repositoryRoot,
                        topLevelItems: [unsafeName]
                    )
                    assertCondition(false, "model removal should reject unsafe item name \(unsafeName)")
                } catch DictationModelStorageError.unsafeRemovalTarget {
                    assertCondition(
                        fileManager.fileExists(atPath: outsideSentinel.path),
                        "rejecting an unsafe item should not escape the repository root"
                    )
                } catch {
                    assertCondition(false, "unsafe item rejection returned the wrong error: \(error)")
                }
            }

            let safeVictim = repositoryRoot.appendingPathComponent("safe-victim.txt")
            try "preserve me".write(to: safeVictim, atomically: true, encoding: .utf8)
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: repositoryRoot,
                    topLevelItems: ["safe-victim.txt", "../outside-sentinel.txt"]
                )
                assertCondition(false, "model removal should reject a list containing an unsafe item")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: safeVictim.path),
                    "model removal should validate the full allowlist before deleting anything"
                )
                assertCondition(
                    fileManager.fileExists(atPath: outsideSentinel.path),
                    "mixed safe and unsafe names should preserve files outside the repository"
                )
            } catch {
                assertCondition(false, "mixed item rejection returned the wrong error: \(error)")
            }

            let externalTarget = temporaryRoot.appendingPathComponent("external-model.bin")
            let modelLink = repositoryRoot.appendingPathComponent("model-link")
            try "external weights".write(to: externalTarget, atomically: true, encoding: .utf8)
            try fileManager.createSymbolicLink(
                atPath: modelLink.path,
                withDestinationPath: externalTarget.path
            )

            try DictationModelStorage.removeAllowlistedItems(
                from: repositoryRoot,
                topLevelItems: ["model-link"]
            )

            assertCondition(
                (try? fileManager.destinationOfSymbolicLink(atPath: modelLink.path)) == nil,
                "model removal should unlink an allowlisted symbolic link"
            )
            assertCondition(
                fileManager.fileExists(atPath: externalTarget.path),
                "unlinking a model layout should not delete its target"
            )
            assertEqual(
                try String(contentsOf: externalTarget, encoding: .utf8),
                "external weights",
                "unlinking a model layout should preserve target contents"
            )

            let externalMetadata = temporaryRoot.appendingPathComponent(
                "external-download-metadata",
                isDirectory: true
            )
            try fileManager.createDirectory(at: externalMetadata, withIntermediateDirectories: true)
            let externalMetadataModel = externalMetadata.appendingPathComponent(
                "model",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: externalMetadataModel,
                withIntermediateDirectories: true
            )
            let externalMetadataSentinel = externalMetadataModel.appendingPathComponent("keep.json")
            try "external metadata".write(
                to: externalMetadataSentinel,
                atomically: true,
                encoding: .utf8
            )
            try fileManager.removeItem(at: metadataRoot)
            try fileManager.createSymbolicLink(
                atPath: metadataRoot.path,
                withDestinationPath: externalMetadata.path
            )
            let modelBeforeUnsafeMetadata = repositoryRoot.appendingPathComponent(
                "model-before-unsafe-metadata",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: modelBeforeUnsafeMetadata,
                withIntermediateDirectories: true
            )
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: repositoryRoot,
                    topLevelItems: ["model-before-unsafe-metadata"]
                )
                assertCondition(false, "model removal should reject a symlinked metadata directory")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: modelBeforeUnsafeMetadata.path),
                    "metadata validation should happen before deleting the model"
                )
                assertCondition(
                    fileManager.fileExists(atPath: externalMetadataSentinel.path),
                    "rejecting symlinked metadata should preserve external files"
                )
            } catch {
                assertCondition(false, "symlinked metadata rejection returned the wrong error: \(error)")
            }

            let symlinkedRepository = temporaryRoot.appendingPathComponent("linked-repository")
            try fileManager.createSymbolicLink(
                atPath: symlinkedRepository.path,
                withDestinationPath: repositoryRoot.path
            )
            do {
                try DictationModelStorage.removeAllowlistedItems(
                    from: symlinkedRepository,
                    topLevelItems: ["keep.txt"]
                )
                assertCondition(false, "model removal should reject a symlinked repository root")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: sentinel.path),
                    "rejecting a symlinked repository should preserve its target files"
                )
            } catch {
                assertCondition(false, "symlinked repository rejection returned the wrong error: \(error)")
            }

            do {
                try DictationModelStorage.removeAllowlistedTopLevelItems(
                    from: symlinkedRepository,
                    topLevelItems: ["keep.txt"]
                )
                assertCondition(false, "layout removal should reject a symlinked root")
            } catch DictationModelStorageError.unsafeRemovalTarget {
                assertCondition(
                    fileManager.fileExists(atPath: sentinel.path),
                    "rejecting a symlinked layout root should preserve its target files"
                )
            } catch {
                assertCondition(false, "symlinked layout rejection returned the wrong error: \(error)")
            }
        } catch {
            fputs("Assertion failed: model storage removal threw \(error)\n", stderr)
            exit(1)
        }
    }

    static func testWhisperModelCatalog() {
        let models = DictationModelDescriptor.all
        assertEqual(models.count, 4, "the local catalog should contain Whisper and Parakeet choices")
        assertEqual(
            models.first?.id,
            .parakeetUnifiedEnglish,
            "the recommended speech model should appear first"
        )
        assertEqual(
            Set(models.map(\.id)).count,
            models.count,
            "every speech model should have a unique persisted identifier"
        )
        assertEqual(
            DictationModelID.resolveSelection(nil),
            .whisperSmallEnglish,
            "a new install should keep the lightweight model selected"
        )
        assertEqual(
            DictationModelID.resolveSelection("not-a-model"),
            .whisperSmallEnglish,
            "an obsolete saved model should fall back safely"
        )
        assertEqual(
            DictationModelID.resolveSelection(WhisperDictationModel.largeV3.rawValue),
            .whisperLargeV3,
            "a legacy Large v3 selection should migrate without a download"
        )
        assertEqual(
            DictationModelDescriptor.descriptor(for: .parakeetUnifiedEnglish).downloadSizeLabel,
            "614 MB",
            "settings should show the verified Parakeet download size"
        )
        assertCondition(
            DictationModelDescriptor.descriptor(for: .parakeetUnifiedEnglish).isRecommended,
            "Parakeet Unified should be presented as the English quality option"
        )
        assertEqual(
            DictationModelDescriptor.descriptor(for: .parakeetV3Multilingual).downloadSizeLabel,
            "483 MB",
            "Parakeet v3 should disclose its verified INT8 download size"
        )
    }

    static func testReducerPolicy() {
        var machine = DictationSessionStateMachine()
        assertEqual(machine.handle(.hotKeyUp), .none, "an unmatched key-up should be ignored")
        assertEqual(machine.state, .idle, "an unmatched key-up should preserve idle")

        assertEqual(machine.handle(.hotKeyDown), .beginRequest, "the first key-down should begin a request")
        assertEqual(machine.state, .requestingPermission, "the request state should be observable")
        assertEqual(machine.handle(.hotKeyDown), .none, "repeated key-down should be ignored")
        assertEqual(machine.handle(.captureStarted), .none, "capture startup should not emit another command")
        assertEqual(machine.state, .listening, "successful capture startup should enter listening")
        assertEqual(machine.handle(.hotKeyUp), .finishCapture, "key-up should finish the active capture")
        assertEqual(machine.state, .transcribing, "key-up should enter transcribing")
        assertEqual(machine.handle(.transcriptionCompleted("hello")), .insert("hello"), "transcription should request insertion")
        assertEqual(machine.state, .inserting, "completed transcription should enter inserting")
        assertEqual(machine.handle(.insertionCompleted("hello")), .none, "insertion completion needs no follow-up action")
        assertEqual(machine.state, .succeeded("hello"), "successful insertion should retain the transcript")

        let policy = DictationAudioPolicy(minimumDuration: 0.10)
        assertCondition(!policy.shouldTranscribe(DictationAudio(samples: [])), "zero audio should be ignored")
        assertCondition(
            !policy.shouldTranscribe(DictationAudio(samples: Array(repeating: 0, count: 1_599))),
            "sub-threshold audio should be ignored"
        )
        assertCondition(
            policy.shouldTranscribe(DictationAudio(samples: Array(repeating: 0, count: 1_600))),
            "threshold-length audio should be transcribed"
        )
        assertEqual(
            DictationTranscriptPolicy.normalize("  Go-jo   local dictation  "),
            "Gojo local dictation",
            "transcript policy should collapse whitespace and correct the product name"
        )
    }

    static func testAudioNormalization() {
        let sourceSampleRate = 48_000.0
        let source = (0..<48_000).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sourceSampleRate))
        }
        do {
            let normalized = try AVAudioEngineCaptureService.normalize(
                samples: source,
                from: sourceSampleRate
            )
            assertEqual(
                normalized.sampleRate,
                DictationAudio.transcriptionSampleRate,
                "capture output should use the transcription sample rate"
            )
            assertCondition(
                abs(normalized.samples.count - 16_000) <= 32,
                "one second of 48 kHz input should normalize to about 16,000 samples"
            )
            assertCondition(
                abs(normalized.duration - 1) < 0.003,
                "sample-rate conversion should preserve duration"
            )
        } catch {
            fputs("Assertion failed: audio normalization threw \(error)\n", stderr)
            exit(1)
        }
    }

    static func testAudioLevelMeter() {
        var silentMeter = DictationAudioLevelMeter()
        let silent = silentMeter.consume(
            sumOfSquares: 0,
            peak: 0,
            sampleCount: 2_048,
            timestamp: 1
        )
        assertEqual(silent, 0, "silence should produce a zero audio level")

        var speechMeter = DictationAudioLevelMeter()
        let speech = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 1
        )
        assertCondition((speech ?? 0) > 0.4, "speech energy should produce a visible audio level")
        assertCondition((speech ?? 2) <= 1, "the audio level should remain normalized")

        let throttled = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 20_000_000
        )
        assertEqual(throttled, nil, "the meter should publish no faster than 25 Hz")
        let next = speechMeter.consume(
            sumOfSquares: 2_048 * 0.04,
            peak: 0.45,
            sampleCount: 2_048,
            timestamp: 40_000_001
        )
        assertCondition(next != nil, "the meter should publish again after 40 milliseconds")

        speechMeter.reset()
        let reset = speechMeter.consume(
            sumOfSquares: 0,
            peak: 0,
            sampleCount: 2_048,
            timestamp: 40_000_002
        )
        assertEqual(reset, 0, "reset should clear smoothing and throttling state")
    }

    static func testModifierOnlyShortcutPolicy() {
        // Activation mode regression coverage begins here.
        func flags(
            exact: Bool,
            anyTriggerDown: Bool,
            disallowed: Bool = false
        ) -> DictationModifierShortcutStateMachine.Event {
            .flagsChanged(
                isExactChord: exact,
                anyTriggerModifierDown: anyTriggerDown,
                hasDisallowedModifiers: disallowed
            )
        }

        var shortcut = DictationModifierShortcutStateMachine(mode: .holdToTalk)

        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "pressing only one trigger modifier should not arm dictation"
        )
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .scheduleActivation,
            "Control-Option should arm modifier-only dictation"
        )
        assertEqual(
            shortcut.handle(.keyDown),
            .cancelScheduledActivation,
            "a normal key should disqualify a Control-Option window shortcut"
        )
        assertEqual(shortcut.state, .blocked, "the chord should stay blocked until both modifiers are released")
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "a blocked chord must not re-arm while the modifiers remain held"
        )
        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: false)),
            .none,
            "releasing both modifiers should reset the chord"
        )

        var quickRelease = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = quickRelease.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            quickRelease.handle(flags(exact: false, anyTriggerDown: false)),
            .cancelScheduledActivation,
            "releasing the chord before the delay should cancel activation"
        )
        assertEqual(
            quickRelease.handle(.activationDelayElapsed),
            .none,
            "a canceled activation timer must not start dictation later"
        )
        assertEqual(quickRelease.state, .idle, "a quick release should return to idle")

        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .scheduleActivation,
            "a fresh Control-Option hold should arm"
        )
        assertEqual(
            shortcut.handle(.activationDelayElapsed),
            .beginDictation,
            "holding the chord through the activation delay should start dictation"
        )
        assertEqual(
            shortcut.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "repeated modifier events must not restart an active session"
        )
        assertEqual(
            shortcut.handle(flags(exact: false, anyTriggerDown: true)),
            .finishDictation,
            "releasing either trigger modifier should finish dictation"
        )
        assertEqual(shortcut.state, .blocked, "a partial release should prevent accidental immediate restart")
        _ = shortcut.handle(flags(exact: false, anyTriggerDown: false))

        _ = shortcut.handle(flags(exact: true, anyTriggerDown: true))
        _ = shortcut.handle(.activationDelayElapsed)
        assertEqual(
            shortcut.handle(.keyDown),
            .cancelDictation,
            "typing another key while dictating should cancel instead of colliding with an existing shortcut"
        )

        var disallowedHold = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        assertEqual(
            disallowedHold.handle(flags(exact: false, anyTriggerDown: true, disallowed: true)),
            .none,
            "an extra modifier should block a hold gesture"
        )
        assertEqual(disallowedHold.state, .blocked, "a disallowed modifier should block until every modifier is up")
        _ = disallowedHold.handle(flags(exact: false, anyTriggerDown: false))

        var armingReset = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = armingReset.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            armingReset.reset(),
            .cancelScheduledActivation,
            "resetting a disabled event tap should cancel a pending activation"
        )
        assertEqual(armingReset.state, .idle, "a reset pending chord should return to idle")

        var activeReset = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = activeReset.handle(flags(exact: true, anyTriggerDown: true))
        _ = activeReset.handle(.activationDelayElapsed)
        assertEqual(
            activeReset.reset(),
            .cancelDictation,
            "resetting a disabled event tap should cancel an active dictation session"
        )
        assertEqual(activeReset.state, .idle, "a reset active chord should return to idle")

        var tap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "tap mode should wait for a complete press and release cycle"
        )
        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "duplicate flags must not start tap mode twice"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "releasing the first modifier should not start tap mode"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: false)),
            .beginDictation,
            "releasing both modifiers should start tap mode"
        )
        assertEqual(tap.state, .active, "tap mode should stay active after the first clean tap")

        assertEqual(
            tap.handle(flags(exact: true, anyTriggerDown: true)),
            .none,
            "the second tap should wait for release before stopping"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: true)),
            .none,
            "a partial release should not stop tap mode"
        )
        assertEqual(
            tap.handle(flags(exact: false, anyTriggerDown: false)),
            .finishDictation,
            "a second clean tap should stop dictation"
        )
        assertEqual(tap.state, .idle, "a completed stop tap should return to idle")

        var dirtyTap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = dirtyTap.handle(flags(exact: true, anyTriggerDown: true))
        assertEqual(
            dirtyTap.handle(.keyDown),
            .none,
            "a normal key should disqualify a pending tap without starting dictation"
        )
        assertEqual(dirtyTap.state, .blocked, "a dirty tap should stay blocked through release")
        _ = dirtyTap.handle(flags(exact: false, anyTriggerDown: false))

        var activeTap = DictationModifierShortcutStateMachine(mode: .tapToTalk)
        _ = activeTap.handle(flags(exact: true, anyTriggerDown: true))
        _ = activeTap.handle(flags(exact: false, anyTriggerDown: false))
        assertEqual(
            activeTap.handle(flags(exact: false, anyTriggerDown: false, disallowed: true)),
            .cancelDictation,
            "an extra modifier should cancel an active tap session"
        )
        assertEqual(activeTap.state, .blocked, "a canceled tap session should remain blocked until modifiers clear")

        var modeChange = DictationModifierShortcutStateMachine(mode: .holdToTalk)
        _ = modeChange.handle(flags(exact: true, anyTriggerDown: true))
        _ = modeChange.handle(.activationDelayElapsed)
        assertEqual(
            modeChange.setMode(.tapToTalk),
            .cancelDictation,
            "changing modes should cancel an active session exactly once"
        )
        assertEqual(
            modeChange.setMode(.tapToTalk),
            .none,
            "setting the same mode again should be idempotent"
        )
        assertEqual(modeChange.state, .idle, "mode changes should reset shortcut state")

        let suiteName = "DictationActivationModeRegression.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fputs("Assertion failed: could not create activation mode test defaults\n", stderr)
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        assertEqual(
            DictationActivationMode.saved(in: defaults),
            .holdToTalk,
            "hold to talk should be the default activation mode"
        )
        DictationActivationMode.tapToTalk.save(in: defaults)
        assertEqual(
            DictationActivationMode.saved(in: defaults),
            .tapToTalk,
            "the selected activation mode should persist"
        )
        // Activation mode regression coverage ends here.
    }

    static func testSuccessfulControllerFlow() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            inserter: inserter,
            audioPolicy: DictationAudioPolicy(minimumDuration: 0.10)
        )

        await controller.hotKeyUp()
        assertEqual(await controller.state, .idle, "controller should ignore unmatched key-up")

        await controller.hotKeyDown()
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "controller should begin listening")
        assertEqual(await target.captures, 1, "repeated key-down must not recapture a target")
        assertEqual(await audio.starts, 1, "repeated key-down must not restart audio")
        assertEqual(
            Array((await log.snapshot()).prefix(3)),
            ["target", "permission", "start"],
            "the text target must be captured before permission and audio startup"
        )

        await controller.hotKeyUp()
        await waitForState(
            .succeeded("locally transcribed"),
            controller: controller,
            message: "the full local pipeline should succeed"
        )
        assertEqual(await transcriber.calls, 1, "normal audio should be transcribed once")
        assertEqual(await inserter.insertionCount(), 1, "the transcript should be inserted once")
    }

    static func testShortcutEventOrdering() async {
        let log = EventLog()
        let queue = DictationShortcutEventQueue { event in
            if case .keyDown = event {
                try? await Task.sleep(for: .milliseconds(20))
                await log.append("down")
            } else if case .keyUp = event {
                await log.append("up")
            }
        }
        queue.send(.keyDown)
        queue.send(.keyUp)
        await queue.drain()
        assertEqual(
            await log.snapshot(),
            ["down", "up"],
            "the production shortcut adapter must preserve a rapid down/up sequence"
        )
    }

    static func testTargetCapturedBeforeHUDStatePublication() async {
        let log = EventLog()
        let target = GatedTargetProvider()
        let recorder = StateRecorder()
        let controller = DictationController(
            targetProvider: target,
            audioCapture: FakeAudioCapture(log: log),
            transcriber: FakeTranscriber(log: log),
            inserter: FakeInserter(log: log),
            stateObserver: { recorder.record($0) }
        )

        await controller.hotKeyDown()
        for _ in 0..<100 where !(await target.isWaiting()) {
            try? await Task.sleep(for: .milliseconds(2))
        }
        let targetIsWaiting = await target.isWaiting()
        assertCondition(targetIsWaiting, "target capture should be in flight")
        assertEqual(
            await controller.state,
            .requestingPermission,
            "the reducer should track the pending request internally"
        )
        assertCondition(
            recorder.snapshot().isEmpty,
            "the HUD observer must not run before the focused destination is captured"
        )

        await target.release()
        await waitForState(.listening, controller: controller, message: "capture should continue after target resolution")
        assertEqual(
            recorder.snapshot().first,
            .requestingPermission,
            "the checking-permissions HUD may appear once the target is safe"
        )
        await controller.cancel()
    }

    static func testShortAudioAndCancellation() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            inserter: inserter,
            audioPolicy: DictationAudioPolicy(minimumDuration: 0.10)
        )

        await audio.setAudio(DictationAudio(samples: Array(repeating: 0, count: 800)))
        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "short-audio session should listen")
        await controller.hotKeyUp()
        await waitForState(.idle, controller: controller, message: "short audio should return to idle")
        assertEqual(await transcriber.calls, 0, "short audio must not invoke the model")
        assertEqual(await inserter.insertionCount(), 0, "short audio must not insert text")

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "second session should listen")
        await controller.terminate()
        await waitForState(.idle, controller: controller, message: "termination should return to idle")
        for _ in 0..<100 where await audio.cancellations == 0 {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        let cancellationCount = await audio.cancellations
        assertCondition(cancellationCount > 0, "termination should cancel active audio")
    }

    static func testRapidCancelThenRestart() async {
        let log = EventLog()
        let target = FakeTargetProvider(log: log)
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        await audio.setCancellationDelay(.milliseconds(60))
        let controller = DictationController(
            targetProvider: target,
            audioCapture: audio,
            transcriber: transcriber,
            inserter: inserter
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "first rapid-restart session should listen")
        await controller.cancel()
        await controller.hotKeyDown()
        try? await Task.sleep(for: .milliseconds(15))
        assertEqual(await audio.starts, 1, "a replacement session must wait for prior teardown")
        assertEqual(await controller.state, .requestingPermission, "replacement should remain queued during teardown")
        await waitForState(.listening, controller: controller, message: "replacement should start after teardown")
        assertEqual(await audio.starts, 2, "replacement capture should start exactly once")
        await controller.cancel()
    }

    static func testTranscriptionTeardownBeforeRestart() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = TeardownAwareTranscriber()
        let controller = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            inserter: FakeInserter(log: log)
        )

        await controller.hotKeyDown()
        await waitForState(.listening, controller: controller, message: "first teardown session should listen")
        await controller.hotKeyUp()
        for _ in 0..<100 where await transcriber.activeCount() == 0 {
            try? await Task.sleep(for: .milliseconds(2))
        }
        assertEqual(await transcriber.activeCount(), 1, "first inference should be active before cancellation")

        await controller.cancel()
        await controller.hotKeyDown()
        try? await Task.sleep(for: .milliseconds(20))
        assertEqual(await audio.starts, 1, "replacement capture must wait for inference teardown")
        await waitForState(.listening, controller: controller, message: "replacement should start after inference exits")
        await controller.hotKeyUp()
        await waitForState(
            .succeeded("replacement transcript"),
            controller: controller,
            message: "replacement should transcribe after teardown"
        )
        assertEqual(
            await transcriber.maximumConcurrentCount(),
            1,
            "cancel and immediate restart must never overlap inference"
        )
    }

    static func testWatchdogAndLocalizedErrors() async {
        let log = EventLog()
        let audio = FakeAudioCapture(log: log)
        let transcriber = FakeTranscriber(log: log)
        let inserter = FakeInserter(log: log)
        let watchdogController = DictationController(
            targetProvider: FakeTargetProvider(log: log),
            audioCapture: audio,
            transcriber: transcriber,
            inserter: inserter,
            maximumCaptureDuration: .milliseconds(25)
        )
        await watchdogController.hotKeyDown()
        await waitForState(.listening, controller: watchdogController, message: "watchdog session should listen")
        await waitForState(.idle, controller: watchdogController, message: "watchdog should stop a lost-key-up session")
        for _ in 0..<100 where await audio.cancellations == 0 {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let watchdogCancellations = await audio.cancellations
        assertCondition(watchdogCancellations > 0, "watchdog expiry should tear down microphone capture")

        let failingController = DictationController(
            targetProvider: FailingTargetProvider(),
            audioCapture: FakeAudioCapture(log: EventLog()),
            transcriber: FakeTranscriber(log: EventLog()),
            inserter: FakeInserter(log: EventLog())
        )
        await failingController.hotKeyDown()
        await waitForState(
            .error(.targetUnavailable("Enable the required permission in System Settings.")),
            controller: failingController,
            message: "localized target errors should reach the HUD verbatim"
        )
    }
}
