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
    typealias PreviewObserver = @Sendable (DictationProvisionalPreview?) -> Void
    typealias CompletionObserver = @Sendable (UUID, DictationCompletion, DictationSessionPlan) -> Void
    typealias SessionResources = @Sendable (DictationSessionPlan) async -> CaptureCleanup?
    typealias TargetObserver = @Sendable (TargetProvider.Target?) -> Void

    private enum PipelineStage {
        case capture
        case transcription
        case insertion
    }

    typealias RecoveryObserver = @Sendable (String, String?) -> Void
    typealias RecoveryRecordsObserver = @Sendable ([DictationRecoveryRecord], UUID?) -> Void
    typealias CaptureCleanup = @Sendable () async -> Void
    typealias BeforeCapture = @Sendable () async -> CaptureCleanup?

    private enum StopIntent {
        case pause
        case finish
    }

    private struct ContinuousJob {
        let audio: DictationAudio
        let leaseID: UUID?
        let unavailableReason: String?
        let recoveryOriginalID: UUID?
        let recoveryAttemptID: UUID?
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
        var pendingTargetCaptures = 0
        var recoveryAttempts: [UUID: UUID] = [:]
        var outstandingAudioDuration: TimeInterval = 0
        var lastDestinationID: String?
        var lastInsertedCharacter: Character?
        var lastCompletion: DictationSessionStateMachine.Event?
        var workFailure: DictationFailure?
        var terminalFailure: DictationFailure?
        var emptyReason: DictationEmptyReason = .noSpeech
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
    private let recoveryRecordsObserver: RecoveryRecordsObserver?
    private let targetObserver: TargetObserver?
    private let maximumRecoveryTextBytes: Int
    private let beforeCapture: BeforeCapture?
    private let acquireSessionResources: SessionResources?
    private let previewObserver: PreviewObserver?
    private let completionObserver: CompletionObserver?
    private let previewInterval: Duration
    private var pendingCompletions: [UUID: (DictationSessionPlan, DictationCompletion)] = [:]
    private var readyCompletions: Set<UUID> = []
    private var deliveryAdmissionBlocked = false
    private var captureAdmissionBlocked = false
    private var recoveryAttemptID: UUID?
    private var activePlan: DictationSessionPlan?
    private var sessionResourceCleanup: CaptureCleanup?
    private var preparationTask: Task<Void, Error>?
    private var previewTask: Task<Void, Never>?
    private var previewDrainTask: Task<Void, Never>?
    private var previewInferenceRevision: Int?
    private var previewRevision = 0
    private(set) var provisionalPreview: DictationProvisionalPreview?
    private(set) var lastCompletion: DictationCompletion?


    private var machine = DictationSessionStateMachine()
    private var initialResolution: DictationTargetResolution<TargetProvider.Target>?
    private(set) var targetSnapshot: TargetProvider.Target?
    private var startupOperation: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var continuousReader: Task<Void, Never>?
    private var continuousPipeline: Task<Void, Never>?
    private var continuousStopOperation: Task<Void, Never>?
    private var continuousSession: ContinuousSession?
    private var cleanupTask: Task<Void, Never>?
    private var audioCleanupTask: Task<Void, Never>?
    private var captureCleanup: CaptureCleanup?
    private var captureCleanupRun: Task<Void, Never>?
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
        recoveryRecordsObserver: RecoveryRecordsObserver? = nil,
        targetObserver: TargetObserver? = nil,
        beforeCapture: BeforeCapture? = nil,
        acquireSessionResources: SessionResources? = nil,
        previewObserver: PreviewObserver? = nil,
        completionObserver: CompletionObserver? = nil,
        previewInterval: Duration = .seconds(2)
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
        self.recoveryRecordsObserver = recoveryRecordsObserver
        self.targetObserver = targetObserver
        self.maximumRecoveryTextBytes = maximumRecoveryTextBytes
        self.beforeCapture = beforeCapture
        self.acquireSessionResources = acquireSessionResources
        self.previewObserver = previewObserver
        self.completionObserver = completionObserver
        self.previewInterval = previewInterval
    }

    var state: DictationState { machine.state }
    var isVoiceModeActive: Bool {
        continuousSession != nil ||
            (machine.state == .requestingPermission && pendingVoiceLockPauseDuration != nil)
    }
    var latestDeliveryUnconfirmed: Bool {
        machine.recoveryRecords.last { $0.sessionID == sessionID }?.outcome.disposition == .allDispatched
    }
    var recoveryRecords: [DictationRecoveryRecord] { machine.recoveryRecords }
    var recoveryAttentionID: UUID? { machine.recoveryAttentionID }
    var recoverySnapshot: (text: String, message: String?) { (recoveryText, recoveryMessage) }

    @discardableResult
    func hotKeyDown(
        plan: DictationSessionPlan = DictationSessionPlan()
    ) async -> Bool {
        if captureAdmissionBlocked, await audioCapture.captureIsQuiescent() {
            captureAdmissionBlocked = false
            flushCompletions()
        }
        let mode = plan.mode
        let pauseDuration = plan.pauseDuration
        let targetPolicy = plan.targetPolicy
        if mode == .continuous, isVoiceModeActive { return true }
        guard !deliveryAdmissionBlocked, !captureAdmissionBlocked, recoveryPayloadBytes < recoveryHighWaterBytes else { return false }
        guard machine.handle(.hotKeyDown) == .beginRequest else { return false }

        let currentSession = plan.id
        sessionID = currentSession
        activePlan = plan
        lastCompletion = nil
        startupReleaseSessionID = nil
        pendingVoiceLockPauseDuration = nil
        initialResolution = nil
        targetSnapshot = nil
        continuousSession = mode == .continuous
            ? ContinuousSession(targetPolicy: targetPolicy, pauseDuration: pauseDuration) : nil
        let pendingCleanup = cleanupTask
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

    func lockVoiceMode() -> Bool {
        let pauseDuration = activePlan?.pauseDuration ?? 0.9
        guard continuousSession == nil else { return false }
        if machine.state == .requestingPermission {
            pendingVoiceLockPauseDuration = pauseDuration
            return true
        }
        let expectedSession = sessionID
        guard machine.state == .listening else { return false }
        cancelCaptureWatchdog()
        let targetPolicy: DictationTargetPolicy
        if case .practice = activePlan?.purpose { targetPolicy = .fixed } else { targetPolicy = .followFocus }
        continuousSession = ContinuousSession(targetPolicy: targetPolicy, pauseDuration: pauseDuration)
        startupOperation = Task { [weak self] in
            await self?.promoteCaptureToVoiceMode(sessionID: expectedSession, pauseDuration: pauseDuration)
        }
        return true
    }

    private func promoteCaptureToVoiceMode(sessionID expectedSession: UUID, pauseDuration: TimeInterval) async {
        do {
            try checkSession(expectedSession)
            beginPreviewDrain()
            let stream = try await audioCapture.promoteCaptureToContinuous(pauseDuration: pauseDuration)
            try checkSession(expectedSession)
            if continuousSession?.targetPolicy == .followFocus { releaseInitialTarget() }
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
        guard let initialTarget = initialResolution?.capturedTarget else { return }
        initialResolution = nil
        Task { [inserter] in await inserter.releaseTarget(initialTarget) }
    }

    func pauseVoiceMode() {
        stopContinuousSession(intent: .pause)
    }

    func resumeVoiceMode() {
        guard !captureAdmissionBlocked, recoveryPayloadBytes < recoveryHighWaterBytes,
              let session = continuousSession, case .paused = session.capturePhase,
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

    @discardableResult
    func clearRecoveryText(matching expectedText: String? = nil) -> Bool {
        guard expectedText == nil || recoveryText == expectedText else { return false }
        let ids = Set(machine.recoveryRecords.compactMap { record -> UUID? in
            guard case .text = record.payload else { return nil }
            return record.id
        })
        machine.discardRecovery(ids: ids)
        publishRecovery()
        switch machine.state {
        case .succeeded, .error: cancel()
        default: break
        }
        return true
    }

    func markRecoveryCopied(id: UUID) {
        machine.markRecoveryCopied(ids: [id])
        publishRecovery()
    }

    func markRecoveryCopied(matching text: String) {
        guard !text.isEmpty, recoveryText == text else { return }
        machine.markRecoveryCopied(ids: Set(machine.recoveryRecords.compactMap { record in
            if case .text = record.payload { return record.id }
            return nil
        }))
        publishRecovery()
    }

    func discardRecovery(id: UUID) {
        machine.discardRecovery(ids: [id])
        publishRecovery()
    }

    @discardableResult
    func retryRecovery(id: UUID) async -> Bool {
        if !deliveryAdmissionBlocked, !captureAdmissionBlocked,
           let original = machine.recoveryRecords.first(where: { $0.id == id }),
           original.sessionID == sessionID, original.outcome.disposition == .notSent,
           case .audio(let audio) = original.payload,
           case .paused = continuousSession?.capturePhase {
            return await receiveContinuousAudio(audio, sessionID: sessionID, recoveryOriginalID: id)
        }
        guard !deliveryAdmissionBlocked, !captureAdmissionBlocked,
              activePlan == nil, recoveryAttemptID == nil,
              let original = machine.recoveryRecords.first(where: { $0.id == id }),
              let payload = original.payload, original.outcome.disposition == .notSent,
              machine.handle(.hotKeyDown) == .beginRequest else { return false }
        let previous = original.plan
        let plan = DictationSessionPlan(mode: .singleUtterance, purpose: previous.purpose,
            recognition: previous.recognition, text: previous.text, capture: previous.capture,
            cuesEnabled: false, learnsCorrections: previous.learnsCorrections)
        sessionID = plan.id
        activePlan = plan
        recoveryAttemptID = id
        publishState()
        let predecessor = cleanupTask
        operation = Task { [weak self] in
            await self?.runRecoveryAttempt(originalID: id, payload: payload, plan: plan, predecessor: predecessor)
        }
        return true
    }

    private func runRecoveryAttempt(originalID: UUID, payload: DictationRecoveryRecord.Payload, plan: DictationSessionPlan, predecessor: Task<Void, Never>?) async {
        do {
            try checkSession(plan.id)
            await predecessor?.value
            try checkSession(plan.id)
            if let acquireSessionResources {
                let cleanup = await acquireSessionResources(plan)
                guard sessionID == plan.id, !Task.isCancelled else {
                    await cleanup?()
                    return
                }
                sessionResourceCleanup = cleanup
            }
            preparationTask = Task { [transcriber] in
                try await transcriber.beginSession(plan)
                try Task.checkCancellation()
                try await transcriber.prepare(request: plan.recognition)
            }
            transition(.retryStarted)
            let text: String
            switch payload {
            case .text(let saved): text = saved
            case .audio(let audio): text = try await processedTranscript(for: audio, sessionID: plan.id)
            }
            try checkSession(plan.id)
            let resolution = try await targetProvider.captureTarget(purpose: plan.purpose)
            guard sessionID == plan.id, !Task.isCancelled else {
                if let target = resolution.capturedTarget { await inserter.releaseTarget(target) }
                throw CancellationError()
            }
            guard let target = resolution.capturedTarget else {
                if case .audio = payload {
                    recordDelivery(text, outcome: .notSent(resolution.copyOnlyReason!.message), plan: plan)
                    machine.linkLatestRecovery(to: originalID)
                    machine.discardRecovery(ids: [originalID])
                    publishRecovery()
                }
                transition(.transcriptSaved(text))
                return
            }
            transition(.transcriptionCompleted(text))
            let outcome: DictationInsertionOutcome
            do { outcome = try await inserter.insert(text, into: target, plan: plan) }
            catch {
                await inserter.releaseTarget(target)
                throw error
            }
            recordDelivery(text, outcome: outcome, plan: plan)
            machine.linkLatestRecovery(to: originalID)
            if outcome.disposition != .notSent { machine.discardRecovery(ids: [originalID]) }
            publishRecovery()
            try checkSession(plan.id)
            transition(outcome.recoveryMessage == nil ? .insertionCompleted(text) : .transcriptSaved(text))
        } catch {
            guard sessionID == plan.id, !Task.isCancelled else { return }
            transition(.failed(failure(for: error, stage: .transcription)))
            scheduleResourceRelease()
        }
        if sessionID == plan.id { operation = nil }
    }

    func cancel() {
        guard machine.handle(.cancel) == .cancel else { return }
        complete(.cancelled)
        publishState()
        invalidateSessionAndScheduleCleanup()
    }

    func cancelPractice(fieldID: UUID) -> Bool {
        guard activePlan?.purpose == .practice(fieldID) else { return false }
        cancel()
        return true
    }

    func cancelIfTranscribing() -> Bool {
        guard continuousSession == nil,
              machine.state == .transcribing,
              machine.handle(.cancel) == .cancel else { return false }
        complete(.cancelled)
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
        let resolution: DictationTargetResolution<TargetProvider.Target>
        do {
            guard !captureAdmissionBlocked, !deliveryAdmissionBlocked else { throw AVAudioEngineCaptureError.cleanupBlocked }
            guard let plan = activePlan else { throw CancellationError() }
            if let acquireSessionResources {
                let cleanup = await acquireSessionResources(plan)
                guard expectedSession == sessionID, !Task.isCancelled else {
                    await cleanup?()
                    throw CancellationError()
                }
                sessionResourceCleanup = cleanup
            }
            try await audioCapture.configure(plan.capture)
            try checkSession(expectedSession)
            resolution = try await targetProvider.captureTarget(purpose: plan.purpose)
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
            if let target = resolution.capturedTarget { await inserter.releaseTarget(target) }
            return
        }
        initialResolution = resolution
        targetSnapshot = resolution.capturedTarget
        targetObserver?(resolution.capturedTarget)

        let plan = activePlan!
        let previousPipelineCleanup = cleanupTask
        preparationTask = Task { [transcriber] in
            await previousPipelineCleanup?.value
            try Task.checkCancellation()
            try await transcriber.beginSession(plan)
            try Task.checkCancellation()
            try await transcriber.prepare(request: plan.recognition)
        }
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

            try await runBeforeCapture(sessionID: expectedSession)

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
            } else if pendingVoiceLockPauseDuration != nil {
                pendingVoiceLockPauseDuration = nil
                _ = lockVoiceMode()
            } else {
                startPreview(sessionID: expectedSession)
                startCaptureWatchdog(for: expectedSession, duration: maximumCaptureDuration)
            }
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            if captureCleanup != nil {
                await audioCapture.cancelCapture()
                guard isCurrent(expectedSession, state: .requestingPermission) else { return }
                await finishCaptureSideEffects()
                guard isCurrent(expectedSession, state: .requestingPermission) else { return }
            }
            if error as? AVAudioEngineCaptureError == .cleanupBlocked { captureAdmissionBlocked = true }
            failCaptureStartup(Self.captureFailure(for: error))
        }
    }

    private func failCaptureStartup(_ failure: DictationFailure) {
        transition(.failed(failure))
        invalidateSessionAndScheduleCleanup()
    }

    private func finishCapture(sessionID expectedSession: UUID) async {
        var stage = PipelineStage.capture
        var completedTranscript: String?
        var attemptedDeliveryPlan: DictationSessionPlan?
        var deliveryAcknowledged = false
        var acceptedAudio: DictationAudio?
        do {
            beginPreviewDrain()
            let audio = try await audioCapture.stopCapture()
            try checkSession(expectedSession)
            await finishCaptureSideEffects()
            try checkSession(expectedSession)
            guard machine.state == .transcribing else { return }
            guard audioPolicy.shouldTranscribe(audio) else {
                if let target = initialResolution?.capturedTarget { await inserter.releaseTarget(target) }
                initialResolution = nil
                complete(.empty(reason: audio.samples.isEmpty || audio.speechEvidence == .silence ? .noSpeech : .tooShort))
                scheduleResourceRelease()
                transition(.audioTooShort)
                operation = nil
                return
            }

            await previewDrainTask?.value
            try checkSession(expectedSession)
            stage = .transcription
            acceptedAudio = audio
            let transcript = try await processedTranscript(for: audio, sessionID: expectedSession)
            try checkSession(expectedSession)
            guard machine.state == .transcribing else { return }
            completedTranscript = transcript
            guard let target = initialResolution?.capturedTarget else {
                try recoverTranscript(
                    transcript,
                    reason: initialResolution?.copyOnlyReason?.message ?? "The captured text target is no longer available. Your text is saved for copying.",
                    sessionID: expectedSession
                )
                initialResolution = nil
                transition(.transcriptSaved(transcript))
                operation = nil
                return
            }
            guard transition(.transcriptionCompleted(transcript)) == .insert else { return }

            stage = .insertion
            #if DEBUG
            let insertionStart = ProcessInfo.processInfo.systemUptime
            #endif
            let deliveryPlan = activePlan!
            attemptedDeliveryPlan = deliveryPlan
            let outcome = try await inserter.insert(transcript, into: target, plan: deliveryPlan)
            recordDelivery(transcript, outcome: outcome, plan: deliveryPlan)
            deliveryAcknowledged = true
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=insertion ms=\(Int(((ProcessInfo.processInfo.systemUptime - insertionStart) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            try checkSession(expectedSession)
            guard machine.state == .inserting else { return }
            initialResolution = nil
            if let message = outcome.recoveryMessage {
                _ = message
                transition(.transcriptSaved(transcript))
            } else {
                transition(.insertionCompleted(transcript))
            }
            operation = nil
        } catch {
            if stage == .insertion, !deliveryAcknowledged, let completedTranscript, let attemptedDeliveryPlan {
                recordDelivery(completedTranscript, outcome: .partialUnknown(Self.userFacingDetail(for: error)), plan: attemptedDeliveryPlan)
            }
            guard expectedSession == sessionID, !Task.isCancelled else { return }
            if stage == .capture {
                if let audio = await audioCapture.takeInterruptedAudio(), let plan = activePlan {
                    guard expectedSession == sessionID else { return }
                    machine.retainAudio(audio, sessionID: expectedSession, plan: plan, reason: Self.userFacingDetail(for: error))
                    publishRecovery()
                }
                await audioCapture.cancelCapture()
                guard expectedSession == sessionID else { return }
                if !(await audioCapture.captureIsQuiescent()) { captureAdmissionBlocked = true }
                await finishCaptureSideEffects()
                guard expectedSession == sessionID else { return }
            }
            if stage == .transcription, let acceptedAudio, let plan = activePlan,
               error as? DictationFailure != .transcriptionReturnedNoText {
                machine.retainAudio(acceptedAudio, sessionID: expectedSession, plan: plan,
                    reason: Self.userFacingDetail(for: error))
                publishRecovery()
            }
            if error as? DictationFailure == .transcriptionReturnedNoText {
                if let target = initialResolution?.capturedTarget { await inserter.releaseTarget(target) }
                initialResolution = nil
                complete(.empty(reason: .noWordsRecognized))
                scheduleResourceRelease()
                transition(.audioTooShort)
            } else {
                releaseInitialTarget()
                transition(.failed(failure(for: error, stage: stage)))
                scheduleResourceRelease()
            }
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
        await previewDrainTask?.value
        try await preparationTask?.value
        try checkSession(expectedSession)
        guard let plan = activePlan else { throw CancellationError() }
        let rawTranscript = try await transcriber.transcribe(audio, request: plan.recognition)
        #if DEBUG
        dictationControllerLatencyLogger.notice(
            "stage=transcription ms=\(Int(((ProcessInfo.processInfo.systemUptime - transcriptionStart) * 1_000).rounded()), privacy: .public)"
        )
        #endif
        try checkSession(expectedSession)
        let normalizedRawTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRawTranscript.isEmpty else { throw DictationFailure.transcriptionReturnedNoText }
        let fallback = DictationFinalTextPolicy.finalize(DictationFinalTextPolicy.prepare(normalizedRawTranscript, options: plan.text))

        do {
            #if DEBUG
            let polishStart = ProcessInfo.processInfo.systemUptime
            #endif
            let polishedTranscript = try await polisher.polish(normalizedRawTranscript, options: plan.text)
            #if DEBUG
            dictationControllerLatencyLogger.notice(
                "stage=polish ms=\(Int(((ProcessInfo.processInfo.systemUptime - polishStart) * 1_000).rounded()), privacy: .public)"
            )
            #endif
            try checkSession(expectedSession)
            let finalTranscript = polishedTranscript.trimmingCharacters(in: .whitespaces)
            return finalTranscript.isEmpty ? fallback : finalTranscript
        } catch {
            try checkSession(expectedSession)
            return fallback
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
                await failResume(sessionID: expectedSession)
                return
            }
            try await runBeforeCapture(sessionID: expectedSession)
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
            if error as? AVAudioEngineCaptureError == .cleanupBlocked {
                captureAdmissionBlocked = true
                await finishCaptureSideEffects()
                continuousSession?.capturePhase = .stopping(.pause, streamFinished: true)
                publishState()
            } else {
                await failResume(sessionID: expectedSession)
            }
        }
    }

    private func failResume(sessionID expectedSession: UUID) async {
        await audioCapture.cancelCapture()
        guard sessionID == expectedSession else { return }
        let quiescent = await audioCapture.captureIsQuiescent()
        await finishCaptureSideEffects()
        guard sessionID == expectedSession else { return }
        guard quiescent else { captureAdmissionBlocked = true; return }
        let intent: StopIntent?
        if case .starting(let pendingIntent) = continuousSession?.capturePhase { intent = pendingIntent }
        else { intent = nil }
        continuousSession?.capturePhase = .paused
        startupOperation = nil
        transition(.resumeFailed)
        if intent == .finish { stopContinuousSession(intent: .finish) }
    }

    @discardableResult
    private func receiveContinuousAudio(_ audio: DictationAudio, sessionID expectedSession: UUID, recoveryOriginalID: UUID? = nil) async -> Bool {
        guard expectedSession == sessionID, let session = continuousSession,
              session.terminalFailure == nil,
              !audio.samples.isEmpty, audio.sampleRate.isFinite, audio.sampleRate > 0,
              audio.speechEvidence != .silence, audio.samples.allSatisfy(\.isFinite) else { return false }
        var recoveryAttemptID: UUID?
        if let recoveryOriginalID {
            guard session.recoveryAttempts[recoveryOriginalID] == nil,
                  session.pending.count + session.pendingTargetCaptures < 2,
                  session.outstandingAudioDuration + audio.duration <= 60 else { return false }
            let attemptID = UUID()
            recoveryAttemptID = attemptID
            continuousSession?.recoveryAttempts[recoveryOriginalID] = attemptID
        }
        continuousSession?.pendingTargetCaptures += 1
        continuousSession?.outstandingAudioDuration += audio.duration
        var enqueued = false
        defer {
            if expectedSession == sessionID, !enqueued {
                continuousSession?.pendingTargetCaptures -= 1
                continuousSession?.outstandingAudioDuration -= audio.duration
                if let recoveryOriginalID,
                   continuousSession?.recoveryAttempts[recoveryOriginalID] == recoveryAttemptID {
                    continuousSession?.recoveryAttempts.removeValue(forKey: recoveryOriginalID)
                }
                Task { [weak self] in
                    await self?.completeContinuousSessionIfDrained(sessionID: expectedSession)
                }
            }
        }
        continuousSession?.emptyReason = .noWordsRecognized
        var leaseID: UUID?
        var unavailableReason: String?
        if session.targetPolicy == .followFocus || recoveryOriginalID != nil {
            do {
                let resolution = try await targetProvider.captureAdditionalTarget(purpose: activePlan!.purpose)
                guard expectedSession == sessionID, continuousSession != nil, !Task.isCancelled else {
                    if let target = resolution.capturedTarget { await inserter.releaseTarget(target) }
                    return false
                }
                targetSnapshot = resolution.capturedTarget
                targetObserver?(resolution.capturedTarget)
                switch resolution {
                case .captured(let phraseTarget):
                    let id = UUID()
                    leasedTargets[id] = phraseTarget
                    leaseID = id
                case .copyOnly(let reason):
                    unavailableReason = reason.message
                }
            } catch {
                guard expectedSession == sessionID, continuousSession != nil, !Task.isCancelled else { return false }
                targetSnapshot = nil
                targetObserver?(nil)
                if error as? DictationFailure == .secureTextTarget {
                    continuousSession?.terminalFailure = .secureTextTarget
                    stopContinuousSession(intent: .finish)
                    return false
                }
                unavailableReason = Self.userFacingDetail(for: error)
            }
        }
        continuousSession?.pending.append(ContinuousJob(
            audio: audio, leaseID: leaseID, unavailableReason: unavailableReason,
            recoveryOriginalID: recoveryOriginalID, recoveryAttemptID: recoveryAttemptID
        ))
        continuousSession?.pendingTargetCaptures -= 1
        enqueued = true
        if continuousSession!.pending.count >= 2 || continuousSession!.outstandingAudioDuration >= 60 {
            stopContinuousSession(intent: .pause)
        }
        guard continuousPipeline == nil else { return true }
        continuousPipeline = Task { [weak self] in
            await self?.processContinuousQueue(sessionID: expectedSession)
        }
        return true
    }

    private func processContinuousQueue(sessionID expectedSession: UUID) async {
        while expectedSession == sessionID, continuousSession != nil {
            guard !continuousSession!.pending.isEmpty else {
                continuousPipeline = nil
                await completeContinuousSessionIfDrained(sessionID: expectedSession)
                return
            }
            let job = continuousSession!.pending.removeFirst()
            defer {
                if expectedSession == sessionID {
                    continuousSession?.outstandingAudioDuration -= job.audio.duration
                    if let originalID = job.recoveryOriginalID,
                       continuousSession?.recoveryAttempts[originalID] == job.recoveryAttemptID {
                        continuousSession?.recoveryAttempts.removeValue(forKey: originalID)
                    }
                }
            }
            let policy = continuousSession!.targetPolicy
            var stage = PipelineStage.transcription
            do {
                let transcript = try await processedTranscript(for: job.audio, sessionID: expectedSession)
                try checkSession(expectedSession)
                var completion: DictationSessionStateMachine.Event = .transcriptSaved(transcript)
                let destination = job.leaseID.flatMap { leasedTargets[$0] } ?? (policy == .fixed && job.recoveryOriginalID == nil ? initialResolution?.capturedTarget : nil)
                if let destination {
                    let destinationID = targetProvider.destinationIdentifier(for: destination)
                    let continuesDestination = policy == .fixed
                        || (destinationID != nil && destinationID == continuousSession?.lastDestinationID)
                    let insertion = continuesDestination
                        ? Self.joinedChunk(transcript, after: continuousSession?.lastInsertedCharacter)
                        : transcript
                    stage = .insertion
                    let deliveryPlan = activePlan!
                    var deliveryAcknowledged = false
                    do {
                        let outcome = try await inserter.insertRetainingTarget(insertion, into: destination, plan: deliveryPlan)
                        recordDelivery(transcript, outcome: outcome, plan: deliveryPlan)
                        deliveryAcknowledged = true
                        if let originalID = job.recoveryOriginalID {
                            machine.linkLatestRecovery(to: originalID)
                            if outcome.disposition != .notSent { machine.discardRecovery(ids: [originalID]) }
                            if !machine.recoveryRecords.contains(where: { record in
                                if case .audio = record.payload { return record.sessionID == expectedSession }
                                return false
                            }) { continuousSession?.workFailure = nil }
                            publishRecovery()
                        }
                        try checkSession(expectedSession)
                        continuousSession?.lastInsertedCharacter = insertion.last
                        continuousSession?.lastDestinationID = destinationID
                        if outcome.recoveryMessage == nil {
                            completion = .insertionCompleted(transcript)
                        }
                    } catch {
                        if !deliveryAcknowledged {
                            recordDelivery(transcript, outcome: .partialUnknown(Self.userFacingDetail(for: error)), plan: deliveryPlan)
                        }
                        try checkSession(expectedSession)
                        guard policy == .followFocus else { throw error }
                    }
                } else {
                    let reason = policy == .followFocus
                        ? job.unavailableReason ?? "Click a text field to add the next phrase."
                        : initialResolution?.copyOnlyReason?.message ?? "The captured text target is no longer available. Your text is saved for copying."
                    try recoverTranscript(transcript, reason: reason, sessionID: expectedSession)
                }
                continuousSession?.lastCompletion = completion
                await releaseLease(job.leaseID)
                try checkSession(expectedSession)
            } catch {
                await releaseLease(job.leaseID)
                guard expectedSession == sessionID, !Task.isCancelled else { return }
                if error as? DictationFailure == .transcriptionReturnedNoText { continue }
                if stage == .transcription, let plan = activePlan {
                    continuousSession?.workFailure = failure(for: error, stage: stage)
                    if job.recoveryOriginalID == nil {
                        machine.retainAudio(job.audio, sessionID: expectedSession, plan: plan,
                            reason: Self.userFacingDetail(for: error))
                        publishRecovery()
                    }
                    stopContinuousSession(intent: .pause)
                    continue
                }
                failContinuousSession(failure(for: error, stage: stage))
                return
            }
        }
    }

    private func releaseLease(_ id: UUID?) async {
        guard let id, let releasedTarget = leasedTargets.removeValue(forKey: id) else { return }
        await inserter.releaseTarget(releasedTarget)
    }

    private var recoveryHighWaterBytes: Int { max(1, maximumRecoveryTextBytes) }
    private var recoveryPayloadBytes: Int {
        machine.recoveryRecords.reduce(0) { count, record in
            switch record.payload {
            case .text(let text): return count + text.utf8.count
            case .audio(let audio): return count + audio.samples.count * MemoryLayout<Float>.size
            case nil: return count
            }
        }
    }

    private func recordDelivery(_ transcript: String, outcome: DictationInsertionOutcome, plan: DictationSessionPlan) {
        if case .receipt(let receipt) = outcome, !receipt.writerQuiescent { deliveryAdmissionBlocked = true }
        machine.retainText(transcript, sessionID: plan.id, outcome: outcome, plan: plan,
            requestsAttention: plan.id == sessionID)
        publishRecovery()
    }

    private func publishRecovery() {
        recoveryText = machine.recoveryRecords.compactMap { record -> String? in
            guard case .text(let text) = record.payload else { return nil }
            return text
        }.reduce("") { $0 + Self.joinedChunk($1, after: $0.last) }
        recoveryMessage = machine.recoveryRecords.first { $0.id == machine.recoveryAttentionID }?.reason
        if continuousSession != nil, recoveryPayloadBytes >= recoveryHighWaterBytes {
            stopContinuousSession(intent: .pause)
        }
        recoveryObserver?(recoveryText, recoveryMessage)
        recoveryRecordsObserver?(machine.recoveryRecords, machine.recoveryAttentionID)
    }

    private func recoverTranscript(_ transcript: String, reason: String, sessionID expectedSession: UUID) throws {
        try checkSession(expectedSession)
        guard let plan = activePlan else { throw CancellationError() }
        recordDelivery(transcript, outcome: .notSent(reason), plan: plan)
        if continuousSession != nil, recoveryText.utf8.count >= maximumRecoveryTextBytes {
            recoveryMessage = "Voice mode finished because saved text is full. Copy or discard the saved text before continuing."
            stopContinuousSession(intent: .finish)
            recoveryObserver?(recoveryText, recoveryMessage)
        }
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
            await finishCaptureSideEffects()
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
            if error as? AVAudioEngineCaptureError == .cleanupBlocked { captureAdmissionBlocked = true }
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
            await continuousCaptureFailed(AVAudioEngineCaptureError.inputUnavailable, sessionID: expectedSession)
        case .starting, .stopped, .paused:
            break
        }
    }

    private func continuousCaptureFailed(_ error: Error, sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, continuousSession != nil else { return }
        continuousReader = nil
        cancelCaptureWatchdog()
        if error as? AVAudioEngineCaptureError == .cleanupBlocked {
            captureAdmissionBlocked = true
            await finishCaptureSideEffects()
            guard expectedSession == sessionID else { return }
            continuousSession?.capturePhase = .stopping(.pause, streamFinished: true)
            _ = transition(.pauseRequested)
            return
        }
        await finishCaptureSideEffects()
        guard expectedSession == sessionID else { return }
        _ = transition(.pauseRequested)
        continuousSession?.capturePhase = .stopped(.pause)
        await completeContinuousSessionIfDrained(sessionID: expectedSession)
    }

    private func completeContinuousSessionIfDrained(sessionID expectedSession: UUID) async {
        guard expectedSession == sessionID, let session = continuousSession,
              case .stopped(let intent) = session.capturePhase else { return }
        continuousStopOperation = nil
        if intent == .pause {
            continuousSession?.capturePhase = .paused
            transition(.capturePaused)
            return
        }
        guard session.pending.isEmpty, session.pendingTargetCaptures == 0, continuousPipeline == nil else { return }
        let completedTarget = initialResolution?.capturedTarget
        initialResolution = nil
        continuousSession = nil
        if let completedTarget { await inserter.releaseTarget(completedTarget) }
        guard expectedSession == sessionID, !Task.isCancelled else { return }
        if let failure = session.terminalFailure ?? session.workFailure {
            transition(.failed(failure))
        } else if let completion = session.lastCompletion {
            if case .insertionCompleted(let transcript) = completion {
                transition(.transcriptionCompleted(transcript))
            }
            transition(completion)
        } else {
            complete(.empty(reason: session.emptyReason))
            transition(.audioTooShort)
        }
        scheduleResourceRelease()
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
        case .transcription:
            return .transcriptionFailed(error is CancellationError
                ? "Speech recognition stopped before it finished. Try dictation again."
                : Self.userFacingDetail(for: error))
        case .insertion: return .insertionFailed(Self.userFacingDetail(for: error))
        }
    }

    @discardableResult
    private func transition(_ event: DictationSessionStateMachine.Event) -> DictationSessionStateMachine.Action {
        let action = machine.handle(event)
        switch event {
        case .insertionCompleted: complete(.delivered); scheduleResourceRelease()
        case .transcriptSaved: complete(.savedForCopying); scheduleResourceRelease()
        case .failed(let failure): complete(.failed(failure))
        default: break
        }
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
        let oldSessionID = sessionID
        let oldPlan = activePlan
        activePlan = nil
        recoveryAttemptID = nil
        let oldResourceCleanup = sessionResourceCleanup
        sessionResourceCleanup = nil
        let oldPreparation = preparationTask
        oldPreparation?.cancel()
        preparationTask = nil
        let oldPreview = invalidatePreview()
        let oldPreviewDrain = previewDrainTask
        previewDrainTask = nil
        sessionID = UUID()
        targetSnapshot = nil
        targetObserver?(nil)
        startupReleaseSessionID = nil
        pendingVoiceLockPauseDuration = nil
        let releasedTarget = initialResolution?.capturedTarget
        let releasedLeases = Array(leasedTargets.values)
        leasedTargets.removeAll()
        initialResolution = nil
        continuousSession = nil
        cancelCaptureWatchdog()
        let oldCaptureCleanup = captureCleanup
        let oldCaptureCleanupRun = captureCleanupRun
        captureCleanup = nil
        captureCleanupRun = nil
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

        let targetCleanup = Task { [inserter] in
            if let releasedTarget { await inserter.releaseTarget(releasedTarget) }
            for lease in releasedLeases { await inserter.releaseTarget(lease) }
        }
        let previousAudioCleanup = audioCleanupTask
        audioCleanupTask = Task { [weak self, audioCapture] in
            await previousAudioCleanup?.value
            await oldStartup?.value
            await oldStop?.value
            await oldCaptureCleanupRun?.value
            await audioCapture.cancelCapture()
            let quiescent = await audioCapture.captureIsQuiescent()
            await self?.acknowledgeCaptureCleanup(quiescent: quiescent)
            await oldCaptureCleanup?()
        }
        let previousCleanup = cleanupTask
        let audioCleanup = audioCleanupTask
        cleanupTask = Task { [transcriber, polisher] in
            await previousCleanup?.value
            async let cancelTranscription: Void = transcriber.cancelTranscription()
            async let cancelPolishing: Void = polisher.cancelPolishing()
            await cancelTranscription
            await cancelPolishing
            await oldPreview?.value
            await oldPreviewDrain?.value
            _ = try? await oldPreparation?.value
            await oldOperation?.value
            await oldPipeline?.value
            await audioCleanup?.value
            await targetCleanup.value
            if oldPlan != nil { await transcriber.endSession(oldSessionID) }
            await oldResourceCleanup?()
        }
        publishCompletion(after: cleanupTask)
    }

    private func publishCompletion(after cleanup: Task<Void, Never>?) {
        for id in pendingCompletions.keys {
            Task { [weak self] in
                await cleanup?.value
                await self?.completionCleanupFinished(id: id)
            }
        }
    }

    private func acknowledgeCaptureCleanup(quiescent: Bool) {
        if !quiescent { captureAdmissionBlocked = true }
    }

    private func completionCleanupFinished(id: UUID) {
        readyCompletions.insert(id)
        flushCompletions()
    }

    private func flushCompletions() {
        guard !deliveryAdmissionBlocked, !captureAdmissionBlocked else { return }
        for id in readyCompletions {
            if let (plan, completion) = pendingCompletions.removeValue(forKey: id) {
                completionObserver?(plan.id, completion, plan)
            }
        }
        readyCompletions.removeAll()
    }

    private func complete(_ completion: DictationCompletion) {
        guard recoveryAttemptID == nil, let plan = activePlan, lastCompletion == nil else { return }
        let resolved: DictationCompletion
        if completion == .delivered, machine.recoveryRecords.contains(where: {
            $0.sessionID == plan.id && $0.payload != nil && $0.outcome.disposition != .allDispatched
        }) { resolved = .savedForCopying } else { resolved = completion }
        lastCompletion = resolved
        pendingCompletions[plan.id] = (plan, resolved)
    }

    private func scheduleResourceRelease() {
        guard let plan = activePlan else { return }
        activePlan = nil
        recoveryAttemptID = nil
        let cleanup = sessionResourceCleanup
        sessionResourceCleanup = nil
        let preparation = preparationTask
        preparationTask = nil
        let previewDrain = previewDrainTask
        previewDrainTask = nil
        let previous = cleanupTask
        cleanupTask = Task { [transcriber] in
            await previous?.value
            _ = try? await preparation?.value
            await previewDrain?.value
            await transcriber.endSession(plan.id)
            await cleanup?()
        }
        publishCompletion(after: cleanupTask)
    }

    private func invalidatePreview() -> Task<Void, Never>? {
        previewRevision &+= 1
        provisionalPreview = nil
        previewObserver?(nil)
        let pending = previewTask
        previewTask = nil
        pending?.cancel()
        return pending
    }

    @discardableResult
    private func beginPreviewDrain() -> Task<Void, Never>? {
        let cancelsInference = previewInferenceRevision != nil
        guard let pending = invalidatePreview() else { return previewDrainTask }
        let drain = Task { [transcriber] in
            if cancelsInference { await transcriber.cancelTranscription() }
            await pending.value
        }
        previewDrainTask = drain
        return drain
    }

    private func startPreview(sessionID expectedSession: UUID) {
        guard let plan = activePlan, plan.previewEnabled else { return }
        let revision = previewRevision
        previewTask = Task { [weak self, audioCapture, previewInterval] in
            do { try await self?.preparationTask?.value } catch { return }
            var previousCount = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: previewInterval) } catch { return }
                guard let self, await self.canPublishPreview(sessionID: expectedSession, revision: revision) else { return }
                guard let snapshot = await audioCapture.captureSnapshot(), snapshot.totalSampleCount > previousCount else { continue }
                previousCount = snapshot.totalSampleCount
                do {
                    try await self.recognizePreview(snapshot, request: plan.recognition, sessionID: expectedSession, revision: revision)
                } catch { return }
            }
        }
    }

    private func canPublishPreview(sessionID expectedSession: UUID, revision: Int) -> Bool {
        expectedSession == sessionID && revision == previewRevision && machine.state == .listening && continuousSession == nil
    }

    private func recognizePreview(_ snapshot: DictationCaptureSnapshot, request: DictationRecognitionRequest, sessionID expectedSession: UUID, revision: Int) async throws {
        guard canPublishPreview(sessionID: expectedSession, revision: revision), !Task.isCancelled else { return }
        previewInferenceRevision = revision
        defer {
            if previewInferenceRevision == revision { previewInferenceRevision = nil }
        }
        let text = try await transcriber.transcribe(snapshot.audio, request: request)
        publishPreview(text, snapshot: snapshot, sessionID: expectedSession, revision: revision)
    }

    private func publishPreview(_ text: String, snapshot: DictationCaptureSnapshot, sessionID expectedSession: UUID, revision: Int) {
        guard canPublishPreview(sessionID: expectedSession, revision: revision), !Task.isCancelled else { return }
        let bounded = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_000))
        guard !bounded.isEmpty else { return }
        let preview = DictationProvisionalPreview(sessionID: expectedSession, revision: revision, text: bounded, isWindowed: snapshot.isWindowed)
        provisionalPreview = preview
        previewObserver?(preview)
    }

    private func runBeforeCapture(sessionID expectedSession: UUID) async throws {
        guard let beforeCapture else { return }
        try checkSession(expectedSession)
        let cleanup = await beforeCapture()
        do {
            try checkSession(expectedSession)
        } catch {
            await cleanup?()
            throw error
        }
        captureCleanup = cleanup
    }

    private func finishCaptureSideEffects() async {
        guard let cleanup = captureCleanup else { return }
        captureCleanup = nil
        let run = Task { await cleanup() }
        captureCleanupRun = run
        await run.value
        if captureCleanupRun == run { captureCleanupRun = nil }
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
        } else {
            hotKeyUp()
        }
    }
}
