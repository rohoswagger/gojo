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
    typealias TargetObserver = @Sendable (TargetProvider.Target?) -> Void

    private enum PipelineStage {
        case capture
        case transcription
        case insertion
    }

    typealias RecoveryObserver = @Sendable (String, String?) -> Void

    private enum StopIntent {
        case pause
        case finish
    }

    private struct ContinuousJob {
        let audio: DictationAudio
        let leaseID: UUID?
        let unavailableReason: String?
    }

    private struct ContinuousSession {
        enum CapturePhase {
            case starting(StopIntent?)
            case listening
            case stopping(StopIntent, streamFinished: Bool)
            case stopped(StopIntent)
            case paused
        }

        let targetPolicy: DictationTargetPolicy
        let pauseDuration: TimeInterval
        var capturePhase: CapturePhase = .starting(nil)
        var pending: [ContinuousJob] = []
        var lastDestinationID: String?
        var lastInsertedCharacter: Character?
        var lastTranscript: String?
        var terminalFailure: DictationFailure?
    }

    private let targetProvider: TargetProvider
    private let audioCapture: AudioCapture
    private let transcriber: Transcriber
    private let polisher: Polisher
    private let inserter: Inserter
    private let audioPolicy: DictationAudioPolicy
    private let maximumCaptureDuration: Duration
    private let maximumContinuousSessionDuration: Duration?
    private let stateObserver: StateObserver?
    private let recoveryObserver: RecoveryObserver?
    private let targetObserver: TargetObserver?
    private let maximumRecoveryTextBytes: Int

    private var machine = DictationSessionStateMachine()
    private var target: TargetProvider.Target?
    private(set) var targetSnapshot: TargetProvider.Target?
    private var startupOperation: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var continuousReader: Task<Void, Never>?
    private var continuousPipeline: Task<Void, Never>?
    private var continuousStopOperation: Task<Void, Never>?
    private var continuousSession: ContinuousSession?
    private var cleanupTask: Task<Void, Never>?
    private var audioCleanupTask: Task<Void, Never>?
    private var captureWatchdog: Task<Void, Never>?
    private var sessionID = UUID()
    private var pendingVoiceLockPauseDuration: TimeInterval?
    private var startupReleaseSessionID: UUID?
    private var leasedTargets: [UUID: TargetProvider.Target] = [:]
    private(set) var recoveryText = ""
    private(set) var recoveryMessage: String?

    init(
        targetProvider: TargetProvider,
        audioCapture: AudioCapture,
        transcriber: Transcriber,
        polisher: Polisher,
        inserter: Inserter,
        audioPolicy: DictationAudioPolicy = DictationAudioPolicy(),
        maximumCaptureDuration: Duration = .seconds(120),
        maximumContinuousSessionDuration: Duration? = nil,
        maximumRecoveryTextBytes: Int = 32 * 1024,
        stateObserver: StateObserver? = nil,
        recoveryObserver: RecoveryObserver? = nil,
        targetObserver: TargetObserver? = nil
    ) {
        self.targetProvider = targetProvider
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.polisher = polisher
        self.inserter = inserter
        self.audioPolicy = audioPolicy
        self.maximumCaptureDuration = maximumCaptureDuration
        self.maximumContinuousSessionDuration = maximumContinuousSessionDuration
        self.stateObserver = stateObserver
        self.recoveryObserver = recoveryObserver
        self.targetObserver = targetObserver
        self.maximumRecoveryTextBytes = maximumRecoveryTextBytes
    }

    var state: DictationState { machine.state }
    var isVoiceModeActive: Bool {
        continuousSession != nil ||
            (machine.state == .requestingPermission && pendingVoiceLockPauseDuration != nil)
    }
    var recoverySnapshot: (text: String, message: String?) { (recoveryText, recoveryMessage) }

    @discardableResult
    func hotKeyDown(
        mode: DictationCaptureMode = .singleUtterance,
        pauseDuration: TimeInterval = 0.9,
        targetPolicy: DictationTargetPolicy = .fixed
    ) -> Bool {
        if mode == .continuous, isVoiceModeActive { return true }
        guard machine.handle(.hotKeyDown) == .beginRequest else { return false }

        let currentSession = UUID()
        sessionID = currentSession
        startupReleaseSessionID = nil
        pendingVoiceLockPauseDuration = nil
        target = nil
        targetSnapshot = nil
        continuousSession = mode == .continuous
            ? ContinuousSession(targetPolicy: targetPolicy, pauseDuration: pauseDuration) : nil
        let pendingCleanup = audioCleanupTask
        startupOperation = Task { [weak self] in
            await pendingCleanup?.value
            guard !Task.isCancelled else { return }
            await self?.beginCapture(sessionID: currentSession, mode: mode, pauseDuration: pauseDuration)
        }
        return true
    }

    func hotKeyUp() {
        if continuousSession != nil {
            finishVoiceMode()
            return
        }
        if machine.state == .requestingPermission {
            startupReleaseSessionID = sessionID
            return
        }

        switch machine.handle(.hotKeyUp) {
        case .finishCapture:
            publishState()
            cancelCaptureWatchdog()
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

    func lockVoiceMode(pauseDuration: TimeInterval) -> Bool {
        guard continuousSession == nil else { return false }
        if machine.state == .requestingPermission {
            pendingVoiceLockPauseDuration = pauseDuration
            return true
        }
        let expectedSession = sessionID
        guard machine.state == .listening else { return false }
        cancelCaptureWatchdog()
        continuousSession = ContinuousSession(targetPolicy: .followFocus, pauseDuration: pauseDuration)
        startupOperation = Task { [weak self] in
            await self?.promoteCaptureToVoiceMode(sessionID: expectedSession, pauseDuration: pauseDuration)
        }
        return true
    }

    private func promoteCaptureToVoiceMode(sessionID expectedSession: UUID, pauseDuration: TimeInterval) async {
        do {
            try checkSession(expectedSession)
            let stream = try await audioCapture.promoteCaptureToContinuous(pauseDuration: pauseDuration)
            try checkSession(expectedSession)
            releaseInitialTarget()
            guard case .starting(let pendingIntent) = continuousSession?.capturePhase else { return }
            continuousSession?.capturePhase = .listening
            startupOperation = nil
            startContinuousReader(stream, sessionID: expectedSession)
            if let pendingIntent {
                stopContinuousSession(intent: pendingIntent)
            } else if let maximumContinuousSessionDuration {
                startCaptureWatchdog(for: expectedSession, duration: maximumContinuousSessionDuration)
            }
        } catch {
            guard sessionID == expectedSession else { return }
            invalidateSessionAndScheduleCleanup()
            transition(.failed(Self.captureFailure(for: error)))
        }
    }

    private func releaseInitialTarget() {
        guard let initialTarget = target else { return }
        target = nil
        Task { [inserter] in await inserter.releaseTarget(initialTarget) }
    }

    func pauseVoiceMode() {
        stopContinuousSession(intent: .pause)
    }

    func resumeVoiceMode() {
        guard let session = continuousSession, case .paused = session.capturePhase,
              machine.handle(.resumeRequested) == .beginRequest else { return }
        continuousSession?.capturePhase = .starting(nil)
        publishState()
        let currentSession = sessionID
        startupOperation = Task { [weak self] in
            await self?.resumeContinuousCapture(sessionID: currentSession)
        }
    }

    func finishVoiceMode() {
        if continuousSession == nil {
            hotKeyUp()
        } else {
            stopContinuousSession(intent: .finish)
        }
    }

    func clearRecoveryText() {
        recoveryText = ""
        recoveryMessage = nil
        recoveryObserver?(recoveryText, recoveryMessage)
    }

    func cancel() {
        guard machine.handle(.cancel) == .cancel else { return }
        publishState()
        invalidateSessionAndScheduleCleanup()
    }

    func cancelIfTranscribing() -> Bool {
        guard continuousSession == nil,
              machine.state == .transcribing,
              machine.handle(.cancel) == .cancel else { return false }
        publishState()
        invalidateSessionAndScheduleCleanup()
        return true
    }

    private func beginCapture(
        sessionID expectedSession: UUID,
        mode: DictationCaptureMode,
        pauseDuration: TimeInterval
    ) async {
        #if DEBUG
        let beginTime = ProcessInfo.processInfo.systemUptime
        #endif
        let capturedTarget: TargetProvider.Target
        do {
            capturedTarget = try await targetProvider.captureTarget()
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=targetCapture ms=\(Int(((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()), privacy: .public)"
            )
            #endif
        } catch {
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            failCaptureStartup(error as? DictationFailure ?? .targetUnavailable(Self.userFacingDetail(for: error)))
            return
        }

        guard isCurrent(expectedSession, state: .requestingPermission), !Task.isCancelled else {
            if mode == .continuous { await inserter.releaseTarget(capturedTarget) }
            return
        }
        target = capturedTarget
        targetSnapshot = capturedTarget
        targetObserver?(capturedTarget)

        Task { [transcriber] in try? await transcriber.prepare() }
        publishState()

        do {
            let permissionGranted = try await audioCapture.requestPermission()
            try checkSession(expectedSession)
            guard permissionGranted else {
                failCaptureStartup(.microphonePermissionDenied)
                return
            }
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=permissionReady ms=\(Int(((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()), privacy: .public)"
            )
            #endif

            let stream: AsyncThrowingStream<DictationAudio, Error>?
            switch mode {
            case .singleUtterance:
                try await audioCapture.startCapture()
                stream = nil
            case .continuous:
                stream = try await audioCapture.startContinuousCapture(pauseDuration: pauseDuration)
            }
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=audioStarted ms=\(Int(((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            try checkSession(expectedSession)
            guard machine.state == .requestingPermission else { return }

            transition(.captureStarted)
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=listeningPublished ms=\(Int(((ProcessInfo.processInfo.systemUptime - beginTime) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            startupOperation = nil
            if let stream {
                let pendingIntent: StopIntent?
                if case .starting(let intent) = continuousSession?.capturePhase {
                    pendingIntent = intent
                } else {
                    pendingIntent = nil
                }
                continuousSession?.capturePhase = .listening
                startContinuousReader(stream, sessionID: expectedSession)
                if continuousSession?.targetPolicy == .followFocus { releaseInitialTarget() }
                if let pendingIntent {
                    stopContinuousSession(intent: pendingIntent)
                } else if let maximumContinuousSessionDuration {
                    startCaptureWatchdog(for: expectedSession, duration: maximumContinuousSessionDuration)
                }
            } else if consumeStartupRelease(for: expectedSession) {
                pendingVoiceLockPauseDuration = nil
                operation = Task { [weak self] in
                    await self?.finishCapture(sessionID: expectedSession)
                }
            } else if let pauseDuration = pendingVoiceLockPauseDuration {
                pendingVoiceLockPauseDuration = nil
                _ = lockVoiceMode(pauseDuration: pauseDuration)
            } else {
                startCaptureWatchdog(for: expectedSession, duration: maximumCaptureDuration)
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            failCaptureStartup(Self.captureFailure(for: error))
        }
    }

    private func failCaptureStartup(_ failure: DictationFailure) {
        transition(.failed(failure))
        if continuousSession != nil {
            invalidateSessionAndScheduleCleanup()
        } else {
            startupOperation = nil
        }
    }

    private func finishCapture(sessionID expectedSession: UUID) async {
        var stage = PipelineStage.capture
        do {
            let audio = try await audioCapture.stopCapture()
            try checkSession(expectedSession)
            guard machine.state == .transcribing else { return }
            guard audioPolicy.shouldTranscribe(audio) else {
                target = nil
                transition(.audioTooShort)
                operation = nil
                return
            }

            stage = .transcription
            let transcript = try await processedTranscript(for: audio, sessionID: expectedSession)
            let action = transition(.transcriptionCompleted(transcript))
            guard action == .insert, let target else {
                transition(.failed(.targetUnavailable("The captured text target is no longer available.")))
                operation = nil
                return
            }

            stage = .insertion
            #if DEBUG
            let insertionStart = ProcessInfo.processInfo.systemUptime
            #endif
            try await inserter.insert(transcript, into: target)
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=insertion ms=\(Int(((ProcessInfo.processInfo.systemUptime - insertionStart) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            try checkSession(expectedSession)
            guard machine.state == .inserting else { return }
            self.target = nil
            transition(.insertionCompleted(transcript))
            operation = nil
        } catch is CancellationError {
            return
        } catch {
            guard expectedSession == sessionID else { return }
            transition(.failed(failure(for: error, stage: stage)))
            operation = nil
        }
    }

    private func processedTranscript(for audio: DictationAudio, sessionID expectedSession: UUID) async throws -> String {
        if let pendingPipelineCleanup = cleanupTask {
            await pendingPipelineCleanup.value
            try checkSession(expectedSession)
        }
        #if DEBUG
        let transcriptionStart = ProcessInfo.processInfo.systemUptime
        #endif
        let rawTranscript = try await transcriber.transcribe(audio)
        #if DEBUG
        dictationControllerLatencyLogger.notice(
            "stage=transcription ms=\(Int(((ProcessInfo.processInfo.systemUptime - transcriptionStart) * 1_000).rounded()), privacy: .public)"
        )
        #endif
        try checkSession(expectedSession)
        let normalizedRawTranscript = DictationTranscriptPolicy.normalize(rawTranscript)
        guard !normalizedRawTranscript.isEmpty else { throw DictationFailure.transcriptionReturnedNoText }

        do {
            #if DEBUG
            let polishStart = ProcessInfo.processInfo.systemUptime
            #endif
            let polishedTranscript = try await polisher.polish(normalizedRawTranscript)
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=polish ms=\(Int(((ProcessInfo.processInfo.systemUptime - polishStart) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            try checkSession(expectedSession)
            let normalizedPolishedTranscript = DictationTranscriptPolicy.normalize(polishedTranscript)
            return normalizedPolishedTranscript.isEmpty ? normalizedRawTranscript : normalizedPolishedTranscript
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try checkSession(expectedSession)
            return normalizedRawTranscript
        }
    }

    private func startContinuousReader(
        _ stream: AsyncThrowingStream<DictationAudio, Error>,
        sessionID expectedSession: UUID
    ) {
        continuousReader = Task { [weak self] in
            do {
                for try await audio in stream {
                    try Task.checkCancellation()
                    await self?.receiveContinuousAudio(audio, sessionID: expectedSession)
                }
                await self?.continuousStreamFinished(sessionID: expectedSession)
            } catch is CancellationError {
                return
            } catch {
                await self?.continuousCaptureFailed(error, sessionID: expectedSession)
            }
        }
    }

    private func resumeContinuousCapture(sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, let session = continuousSession else { return }
        do {
            let permissionGranted = try await audioCapture.requestPermission()
            try checkSession(expectedSession)
            guard permissionGranted else {
                failContinuousSession(.microphonePermissionDenied)
                return
            }
            let stream = try await audioCapture.startContinuousCapture(pauseDuration: session.pauseDuration)
            try checkSession(expectedSession)
            guard case .starting(let pendingIntent) = continuousSession?.capturePhase else { return }
            continuousSession?.capturePhase = .listening
            transition(.captureStarted)
            startupOperation = nil
            startContinuousReader(stream, sessionID: expectedSession)
            if let pendingIntent {
                stopContinuousSession(intent: pendingIntent)
            } else if let maximumContinuousSessionDuration {
                startCaptureWatchdog(for: expectedSession, duration: maximumContinuousSessionDuration)
            }
        } catch is CancellationError {
            return
        } catch {
            guard expectedSession == sessionID else { return }
            failContinuousSession(Self.captureFailure(for: error))
        }
    }

    private func receiveContinuousAudio(_ audio: DictationAudio, sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, let session = continuousSession,
              session.terminalFailure == nil,
              !audio.samples.isEmpty, audio.sampleRate > 0 else { return }
        guard session.pending.count < 3 else {
            failContinuousSession(.captureFailed("Dictation could not keep up. Stop and start again."))
            return
        }
        var leaseID: UUID?
        var unavailableReason: String?
        if session.targetPolicy == .followFocus {
            do {
                let phraseTarget = try await targetProvider.captureAdditionalTarget()
                guard expectedSession == sessionID, continuousSession != nil, !Task.isCancelled else {
                    await inserter.releaseTarget(phraseTarget)
                    return
                }
                targetSnapshot = phraseTarget
                targetObserver?(phraseTarget)
                let id = UUID()
                leasedTargets[id] = phraseTarget
                leaseID = id
            } catch {
                guard expectedSession == sessionID, continuousSession != nil, !Task.isCancelled else { return }
                targetSnapshot = nil
                targetObserver?(nil)
                if error as? DictationFailure == .secureTextTarget {
                    continuousSession?.terminalFailure = .secureTextTarget
                    stopContinuousSession(intent: .finish)
                    return
                }
                unavailableReason = Self.userFacingDetail(for: error)
            }
        }
        continuousSession?.pending.append(ContinuousJob(
            audio: audio, leaseID: leaseID, unavailableReason: unavailableReason
        ))
        guard continuousPipeline == nil else { return }
        continuousPipeline = Task { [weak self] in
            await self?.processContinuousQueue(sessionID: expectedSession)
        }
    }

    private func processContinuousQueue(sessionID expectedSession: UUID) async {
        while expectedSession == sessionID, continuousSession != nil {
            guard !continuousSession!.pending.isEmpty else {
                continuousPipeline = nil
                await completeContinuousSessionIfDrained(sessionID: expectedSession)
                return
            }
            let job = continuousSession!.pending.removeFirst()
            let policy = continuousSession!.targetPolicy
            var stage = PipelineStage.transcription
            do {
                let transcript = try await processedTranscript(for: job.audio, sessionID: expectedSession)
                let destination = job.leaseID.flatMap { leasedTargets[$0] } ?? (policy == .fixed ? target : nil)
                if let destination {
                    let destinationID = targetProvider.destinationIdentifier(for: destination)
                    let continuesDestination = policy == .fixed
                        || (destinationID != nil && destinationID == continuousSession?.lastDestinationID)
                    let insertion = continuesDestination
                        ? Self.joinedChunk(transcript, after: continuousSession?.lastInsertedCharacter)
                        : transcript
                    stage = .insertion
                    do {
                        try await inserter.insertRetainingTarget(insertion, into: destination)
                        try checkSession(expectedSession)
                        continuousSession?.lastInsertedCharacter = insertion.last
                        continuousSession?.lastDestinationID = destinationID
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        try checkSession(expectedSession)
                        guard policy == .followFocus else { throw error }
                        recoverTranscript(transcript, reason: Self.userFacingDetail(for: error))
                    }
                } else if policy == .followFocus {
                    recoverTranscript(transcript, reason: job.unavailableReason ?? "Click a text field to add the next phrase.")
                } else {
                    throw DictationFailure.targetUnavailable("The captured text target is no longer available.")
                }
                continuousSession?.lastTranscript = transcript
                await releaseLease(job.leaseID)
                try checkSession(expectedSession)
            } catch is CancellationError {
                await releaseLease(job.leaseID)
                return
            } catch {
                await releaseLease(job.leaseID)
                guard expectedSession == sessionID else { return }
                failContinuousSession(failure(for: error, stage: stage))
                return
            }
        }
    }

    private func releaseLease(_ id: UUID?) async {
        guard let id, let releasedTarget = leasedTargets.removeValue(forKey: id) else { return }
        await inserter.releaseTarget(releasedTarget)
    }

    private func recoverTranscript(_ transcript: String, reason: String) {
        recoveryText += Self.joinedChunk(transcript, after: recoveryText.last)
        recoveryMessage = reason
        if recoveryText.utf8.count >= maximumRecoveryTextBytes {
            recoveryMessage = "Voice mode finished because saved text is full. Copy or discard the saved text before continuing."
            stopContinuousSession(intent: .finish)
        }
        recoveryObserver?(recoveryText, recoveryMessage)
    }

    private func stopContinuousSession(intent: StopIntent) {
        guard let session = continuousSession else { return }
        switch session.capturePhase {
        case .starting(let pendingIntent):
            continuousSession?.capturePhase = .starting(pendingIntent == .finish ? .finish : intent)
            return
        case .paused:
            guard intent == .finish else { return }
            continuousSession?.capturePhase = .stopped(.finish)
            transition(.finishRequested)
            let currentSession = sessionID
            continuousStopOperation = Task { [weak self] in
                await self?.completeContinuousSessionIfDrained(sessionID: currentSession)
            }
            return
        case .stopping(let pendingIntent, let streamFinished):
            if intent == .finish, pendingIntent == .pause {
                continuousSession?.capturePhase = .stopping(.finish, streamFinished: streamFinished)
                transition(.finishRequested)
            }
            return
        case .stopped(let pendingIntent):
            if intent == .finish, pendingIntent == .pause {
                continuousSession?.capturePhase = .stopped(.finish)
                transition(.finishRequested)
            }
            return
        case .listening:
            break
        }
        let event: DictationSessionStateMachine.Event = intent == .pause ? .pauseRequested : .hotKeyUp
        guard machine.handle(event) == .finishCapture else { return }
        continuousSession?.capturePhase = .stopping(intent, streamFinished: false)
        cancelCaptureWatchdog()
        publishState()
        let currentSession = sessionID
        continuousStopOperation = Task { [weak self] in
            await self?.finishContinuousCapture(sessionID: currentSession)
        }
    }

    private func finishContinuousCapture(sessionID expectedSession: UUID) async {
        do {
            try await audioCapture.stopContinuousCapture()
            try checkSession(expectedSession)
            continuousStopOperation = nil
            if let session = continuousSession,
               case .stopping(let intent, streamFinished: true) = session.capturePhase {
                continuousSession?.capturePhase = .stopped(intent)
                await completeContinuousSessionIfDrained(sessionID: expectedSession)
            }
        } catch is CancellationError {
            return
        } catch {
            guard expectedSession == sessionID else { return }
            failContinuousSession(Self.captureFailure(for: error))
        }
    }

    private func continuousStreamFinished(sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, let session = continuousSession else { return }
        continuousReader = nil
        switch session.capturePhase {
        case .stopping(let intent, _):
            continuousSession?.capturePhase = continuousStopOperation == nil
                ? .stopped(intent)
                : .stopping(intent, streamFinished: true)
            await completeContinuousSessionIfDrained(sessionID: expectedSession)
        case .listening:
            failContinuousSession(.captureFailed("The microphone stopped unexpectedly. Start dictation again."))
        case .starting, .stopped, .paused:
            break
        }
    }

    private func continuousCaptureFailed(_ error: Error, sessionID expectedSession: UUID) {
        guard expectedSession == sessionID, continuousSession != nil else { return }
        failContinuousSession(Self.captureFailure(for: error))
    }

    private func completeContinuousSessionIfDrained(sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, let session = continuousSession,
              case .stopped(let intent) = session.capturePhase,
              session.pending.isEmpty, continuousPipeline == nil else { return }
        continuousStopOperation = nil
        if intent == .pause {
            continuousSession?.capturePhase = .paused
            transition(.capturePaused)
            return
        }
        let completedTarget = target
        target = nil
        continuousSession = nil
        if let completedTarget { await inserter.releaseTarget(completedTarget) }
        guard expectedSession == sessionID, !Task.isCancelled else { return }
        if let failure = session.terminalFailure {
            transition(.failed(failure))
        } else if let transcript = session.lastTranscript {
            transition(.transcriptionCompleted(transcript))
            transition(.insertionCompleted(transcript))
        } else {
            transition(.audioTooShort)
        }
    }

    private func failContinuousSession(_ failure: DictationFailure) {
        transition(.failed(failure))
        invalidateSessionAndScheduleCleanup()
    }

    private static func joinedChunk(_ transcript: String, after previous: Character?) -> String {
        guard let previous, let first = transcript.first,
              !previous.isWhitespace, !first.isWhitespace,
              !isNoSpaceCharacter(previous), !isNoSpaceCharacter(first),
              !",.;:!?)]}’'\"".contains(first),
              !"([{‘'\"".contains(previous) else { return transcript }
        return " " + transcript
    }

    private static func isNoSpaceCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            switch $0.value {
            case 0x2E80...0xA4CF, 0xAC00...0xD7AF, 0xF900...0xFAFF,
                 0xFE30...0xFE4F, 0xFF00...0xFFEF, 0x20000...0x323AF:
                return true
            default:
                return false
            }
        }
    }

    private func failure(for error: Error, stage: PipelineStage) -> DictationFailure {
        if error as? DictationFailure == .transcriptionReturnedNoText { return .transcriptionReturnedNoText }
        switch stage {
        case .capture: return Self.captureFailure(for: error)
        case .transcription: return .transcriptionFailed(Self.userFacingDetail(for: error))
        case .insertion: return .insertionFailed(Self.userFacingDetail(for: error))
        }
    }

    @discardableResult
    private func transition(_ event: DictationSessionStateMachine.Event) -> DictationSessionStateMachine.Action {
        let action = machine.handle(event)
        switch machine.state {
        case .idle, .succeeded, .error:
            startupReleaseSessionID = nil
            pendingVoiceLockPauseDuration = nil
            targetSnapshot = nil
            targetObserver?(nil)
        case .requestingPermission, .listening, .pausing, .paused, .transcribing, .inserting: break
        }
        publishState()
        return action
    }

    private func publishState() { stateObserver?(machine.state) }

    private func invalidateSessionAndScheduleCleanup() {
        sessionID = UUID()
        targetSnapshot = nil
        targetObserver?(nil)
        startupReleaseSessionID = nil
        pendingVoiceLockPauseDuration = nil
        let releasedTarget = continuousSession == nil ? nil : target
        let releasedLeases = Array(leasedTargets.values)
        leasedTargets.removeAll()
        target = nil
        continuousSession = nil
        cancelCaptureWatchdog()
        let oldStartup = startupOperation
        let oldOperation = operation
        let oldPipeline = continuousPipeline
        let oldStop = continuousStopOperation
        startupOperation?.cancel()
        operation?.cancel()
        continuousReader?.cancel()
        continuousPipeline?.cancel()
        continuousStopOperation?.cancel()
        startupOperation = nil
        operation = nil
        continuousReader = nil
        continuousPipeline = nil
        continuousStopOperation = nil

        Task { [inserter] in
            if let releasedTarget { await inserter.releaseTarget(releasedTarget) }
            for lease in releasedLeases { await inserter.releaseTarget(lease) }
        }
        let previousAudioCleanup = audioCleanupTask
        audioCleanupTask = Task { [audioCapture] in
            await previousAudioCleanup?.value
            await oldStartup?.value
            await oldStop?.value
            await audioCapture.cancelCapture()
        }
        let previousCleanup = cleanupTask
        cleanupTask = Task { [transcriber, polisher] in
            await previousCleanup?.value
            async let cancelTranscription: Void = transcriber.cancelTranscription()
            async let cancelPolishing: Void = polisher.cancelPolishing()
            await cancelTranscription
            await cancelPolishing
            await oldOperation?.value
            await oldPipeline?.value
        }
    }

    private func checkSession(_ expectedSession: UUID) throws {
        try Task.checkCancellation()
        guard expectedSession == sessionID else { throw CancellationError() }
    }

    private func isCurrent(_ expectedSession: UUID, state expectedState: DictationState) -> Bool {
        expectedSession == sessionID && machine.state == expectedState
    }

    private func consumeStartupRelease(for expectedSession: UUID) -> Bool {
        guard startupReleaseSessionID == expectedSession,
              isCurrent(expectedSession, state: .listening),
              machine.handle(.hotKeyUp) == .finishCapture else { return false }
        startupReleaseSessionID = nil
        publishState()
        cancelCaptureWatchdog()
        return true
    }

    private static func captureFailure(for error: Error) -> DictationFailure {
        if error as? DictationMicrophoneAuthorizationFailure == .denied {
            return .microphonePermissionDenied
        }
        return .captureFailed(userFacingDetail(for: error))
    }

    private static func userFacingDetail(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty { return description }
        return String(describing: error)
    }

    private func cancelCaptureWatchdog() {
        captureWatchdog?.cancel()
        captureWatchdog = nil
    }

    private func startCaptureWatchdog(for expectedSession: UUID, duration: Duration) {
        cancelCaptureWatchdog()
        captureWatchdog = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            await self?.captureWatchdogExpired(sessionID: expectedSession)
        }
    }

    private func captureWatchdogExpired(sessionID expectedSession: UUID) {
        guard isCurrent(expectedSession, state: .listening) else { return }
        if continuousSession != nil {
            stopContinuousSession(intent: .finish)
        } else if machine.handle(.cancel) == .cancel {
            publishState()
            invalidateSessionAndScheduleCleanup()
        }
    }
}
