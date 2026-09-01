import Foundation
import os

#if DEBUG
private let dictationControllerLatencyLogger = Logger(
    subsystem: "rohoswagger.gojo.dictation",
    category: "latency"
)
#endif

actor DictationController<TargetProvider, AudioCapture, Transcriber, Polisher, Inserter>
where TargetProvider: DictationTargetCapturing,
      AudioCapture: DictationAudioCapturing,
      Transcriber: LocalDictationTranscribing,
      Polisher: DictationTextPolishing,
      Inserter: DictationTextInserting,
      TargetProvider.Target == Inserter.Target {

    typealias StateObserver = @Sendable (DictationState) -> Void

    private enum PipelineStage {
        case capture
        case transcription
        case insertion
    }

    private let targetProvider: TargetProvider
    private let audioCapture: AudioCapture
    private let transcriber: Transcriber
    private let polisher: Polisher
    private let inserter: Inserter
    private let audioPolicy: DictationAudioPolicy
    private let maximumCaptureDuration: Duration
    private let stateObserver: StateObserver?

    private var machine = DictationSessionStateMachine()
    private var target: TargetProvider.Target?
    private var operation: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var captureWatchdog: Task<Void, Never>?
    private var sessionID = UUID()

    init(
        targetProvider: TargetProvider,
        audioCapture: AudioCapture,
        transcriber: Transcriber,
        polisher: Polisher,
        inserter: Inserter,
        audioPolicy: DictationAudioPolicy = DictationAudioPolicy(),
        maximumCaptureDuration: Duration = .seconds(120),
        stateObserver: StateObserver? = nil
    ) {
        self.targetProvider = targetProvider
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.polisher = polisher
        self.inserter = inserter
        self.audioPolicy = audioPolicy
        self.maximumCaptureDuration = maximumCaptureDuration
        self.stateObserver = stateObserver
    }

    var state: DictationState {
        machine.state
    }

    @discardableResult
    func hotKeyDown() -> Bool {
        guard machine.handle(.hotKeyDown) == .beginRequest else { return false }

        let currentSession = UUID()
        sessionID = currentSession
        target = nil
        let pendingCleanup = cleanupTask
        operation = Task { [weak self] in
            await pendingCleanup?.value
            guard !Task.isCancelled else { return }
            await self?.beginCapture(sessionID: currentSession)
        }
        return true
    }

    func hotKeyUp() {
        let action = machine.handle(.hotKeyUp)
        switch action {
        case .finishCapture:
            publishState()
            captureWatchdog?.cancel()
            captureWatchdog = nil
            let currentSession = sessionID
            operation = Task { [weak self] in
                await self?.finishCapture(sessionID: currentSession)
            }
        case .cancel:
            publishState()
            invalidateSessionAndScheduleCleanup()
        default:
            break
        }
    }

    func cancel() {
        guard machine.handle(.cancel) == .cancel else { return }
        publishState()
        invalidateSessionAndScheduleCleanup()
    }

    func terminate() {
        cancel()
    }

    private func beginCapture(sessionID expectedSession: UUID) async {
        #if DEBUG
        let beginTime = ProcessInfo.processInfo.systemUptime
        #endif
        let capturedTarget: TargetProvider.Target
        do {
            capturedTarget = try await targetProvider.captureTarget()
            #if DEBUG
            let targetMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()
            )
            dictationControllerLatencyLogger.notice(
                "stage=targetCapture ms=\(targetMilliseconds, privacy: .public)"
            )
            #endif
        } catch {
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            transition(.failed(.targetUnavailable(Self.userFacingDetail(for: error))))
            operation = nil
            return
        }

        do {
            // Capture the destination before asking for or starting microphone access.
            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            target = capturedTarget

            // Warm the model now so its first-use load overlaps with the user
            // speaking. Loading it lazily in finishCapture pushed insertion
            // tens of seconds past the utterance, by which point the focus
            // check in the helper rejected the text outright.
            Task { [transcriber] in await transcriber.prepare() }

            // Do not publish a state that presents Gojo's HUD until the
            // destination has been captured. Even a nonactivating panel can
            // momentarily become the system-wide focused AX element in some
            // apps, which would make the helper miss the field the user chose.
            publishState()

            guard await audioCapture.requestPermission() else {
                guard isCurrent(expectedSession, state: .requestingPermission) else { return }
                transition(.permissionDenied)
                operation = nil
                return
            }
            #if DEBUG
            let permissionMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()
            )
            dictationControllerLatencyLogger.notice(
                "stage=permissionReady ms=\(permissionMilliseconds, privacy: .public)"
            )
            #endif

            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            try await audioCapture.startCapture()
            #if DEBUG
            let audioMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()
            )
            dictationControllerLatencyLogger.notice(
                "stage=audioStarted ms=\(audioMilliseconds, privacy: .public)"
            )
            #endif
            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .requestingPermission) else {
                await audioCapture.cancelCapture()
                return
            }

            transition(.captureStarted)
            #if DEBUG
            let listeningMilliseconds = Int(
                ((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()
            )
            dictationControllerLatencyLogger.notice(
                "stage=listeningPublished ms=\(listeningMilliseconds, privacy: .public)"
            )
            #endif
            startCaptureWatchdog(for: expectedSession)
            operation = nil
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            transition(.failed(.captureFailed(Self.userFacingDetail(for: error))))
            operation = nil
        }
    }

    private func finishCapture(sessionID expectedSession: UUID) async {
        var stage = PipelineStage.capture
        do {
            let audio = try await audioCapture.stopCapture()
            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .transcribing) else { return }

            guard audioPolicy.shouldTranscribe(audio) else {
                target = nil
                transition(.audioTooShort)
                operation = nil
                return
            }

            stage = .transcription
            let rawTranscript = try await transcriber.transcribe(audio)
            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .transcribing) else { return }

            let normalizedRawTranscript = DictationTranscriptPolicy.normalize(rawTranscript)
            guard !normalizedRawTranscript.isEmpty else {
                transition(.failed(.emptyTranscript))
                operation = nil
                return
            }

            // Polishing is deliberately best-effort. Dictation must remain
            // useful when the optional model is unavailable, returns no text,
            // or rejects a particular utterance.
            let transcript: String
            do {
                let polishedTranscript = try await polisher.polish(normalizedRawTranscript)
                try Task.checkCancellation()
                guard isCurrent(expectedSession, state: .transcribing) else { return }
                let normalizedPolishedTranscript = DictationTranscriptPolicy.normalize(polishedTranscript)
                transcript = normalizedPolishedTranscript.isEmpty
                    ? normalizedRawTranscript
                    : normalizedPolishedTranscript
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                guard isCurrent(expectedSession, state: .transcribing) else { return }
                transcript = normalizedRawTranscript
            }

            let action = transition(.transcriptionCompleted(transcript))
            guard action == .insert, let target else {
                transition(.failed(.targetUnavailable("The captured text target is no longer available.")))
                operation = nil
                return
            }

            stage = .insertion
            try await inserter.insert(transcript, into: target)
            try Task.checkCancellation()
            guard isCurrent(expectedSession, state: .inserting) else { return }

            self.target = nil
            transition(.insertionCompleted(transcript))
            operation = nil
        } catch is CancellationError {
            return
        } catch {
            guard expectedSession == sessionID else { return }
            let failure: DictationFailure
            switch stage {
            case .capture:
                failure = .captureFailed(Self.userFacingDetail(for: error))
            case .transcription:
                failure = .transcriptionFailed(Self.userFacingDetail(for: error))
            case .insertion:
                failure = .insertionFailed(Self.userFacingDetail(for: error))
            }
            transition(.failed(failure))
            operation = nil
        }
    }

    @discardableResult
    private func transition(_ event: DictationSessionStateMachine.Event) -> DictationSessionStateMachine.Action {
        let action = machine.handle(event)
        publishState()
        return action
    }

    private func publishState() {
        stateObserver?(machine.state)
    }

    private func invalidateSessionAndScheduleCleanup() {
        sessionID = UUID()
        target = nil
        captureWatchdog?.cancel()
        captureWatchdog = nil
        operation?.cancel()
        operation = nil

        let previousCleanup = cleanupTask
        cleanupTask = Task { [audioCapture, transcriber, polisher] in
            await previousCleanup?.value
            async let cancelAudio: Void = audioCapture.cancelCapture()
            async let cancelTranscription: Void = transcriber.cancelTranscription()
            async let cancelPolishing: Void = polisher.cancelPolishing()
            await cancelAudio
            await cancelTranscription
            await cancelPolishing
        }
    }

    private func isCurrent(_ expectedSession: UUID, state expectedState: DictationState) -> Bool {
        expectedSession == sessionID && machine.state == expectedState
    }

    private static func userFacingDetail(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }
        return String(describing: error)
    }

    private func startCaptureWatchdog(for expectedSession: UUID) {
        captureWatchdog?.cancel()
        let duration = maximumCaptureDuration
        captureWatchdog = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            await self?.captureWatchdogExpired(sessionID: expectedSession)
        }
    }

    private func captureWatchdogExpired(sessionID expectedSession: UUID) {
        guard isCurrent(expectedSession, state: .listening),
              machine.handle(.cancel) == .cancel else { return }
        publishState()
        invalidateSessionAndScheduleCleanup()
    }
}
