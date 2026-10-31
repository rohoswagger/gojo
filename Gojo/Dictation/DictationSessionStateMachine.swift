import Foundation

struct DictationSessionStateMachine: Sendable {
    enum Event: Equatable, Sendable {
        case hotKeyDown
        case hotKeyUp
        case pauseRequested
        case capturePaused
        case resumeRequested
        case resumeFailed
        case finishRequested
        case captureStarted
        case retryStarted
        case audioTooShort
        case transcriptionCompleted(String)
        case insertionCompleted(String)
        case transcriptSaved(String)
        case failed(DictationFailure)
        case cancel
    }

    enum Action: Equatable, Sendable {
        case none
        case beginRequest
        case finishCapture
        case insert
        case cancel
    }

    private(set) var state: DictationState = .idle
    private(set) var recoveryRecords: [DictationRecoveryRecord] = []
    private(set) var recoveryAttentionID: UUID?

    mutating func retainText(_ text: String, sessionID: UUID, chunkID: UUID = UUID(), outcome: DictationInsertionOutcome, plan: DictationSessionPlan, reason: String? = nil, requestsAttention: Bool = true) {
        var receipt: DictationDeliveryReceipt?
        if case .receipt(let value) = outcome { receipt = value } else { receipt = nil }
        if let receipt, let index = recoveryRecords.firstIndex(where: { $0.receipt?.transactionID == receipt.transactionID }) {
            guard !recoveryRecords[index].receipts.contains(receipt) else { return }
            recoveryRecords[index].receipts.append(receipt)
            recoveryRecords[index].receipt = receipt
            recoveryRecords[index].outcome = outcome
            recoveryRecords[index].reason = reason ?? outcome.recoveryMessage
            if receipt.disposition == .confirmed { recoveryRecords[index].payload = nil }
            if requestsAttention, index == recoveryRecords.count - 1 {
                recoveryAttentionID = [.confirmed, .allDispatched].contains(receipt.disposition) ? nil : recoveryRecords[index].id
            }
            return
        }
        let record = DictationRecoveryRecord(id: chunkID, sessionID: sessionID, plan: plan,
            payload: outcome.disposition == .confirmed ? nil : .text(text), outcome: outcome, receipt: receipt, reason: reason ?? outcome.recoveryMessage)
        recoveryRecords.append(record)
        if let receipt { recoveryRecords[recoveryRecords.count - 1].receipts.append(receipt) }
        if requestsAttention {
            recoveryAttentionID = [.allDispatched, .confirmed].contains(outcome.disposition) ? nil : record.id
        }
    }

    mutating func retainAudio(_ audio: DictationAudio, sessionID: UUID, plan: DictationSessionPlan, reason: String) {
        let record = DictationRecoveryRecord(id: UUID(), sessionID: sessionID, plan: plan,
            payload: .audio(audio), outcome: .notSent(reason), receipt: nil, reason: reason)
        recoveryRecords.append(record)
        recoveryAttentionID = record.id
    }

    mutating func linkLatestRecovery(to id: UUID) {
        guard !recoveryRecords.isEmpty else { return }
        recoveryRecords[recoveryRecords.count - 1].retryOf = id
    }

    mutating func markRecoveryCopied(ids: Set<UUID>) {
        for index in recoveryRecords.indices where ids.contains(recoveryRecords[index].id) {
            recoveryRecords[index].copyStatus = .copied
        }
        if let id = recoveryAttentionID, ids.contains(id) { recoveryAttentionID = nil }
    }

    mutating func discardRecovery(ids: Set<UUID>) {
        for index in recoveryRecords.indices where ids.contains(recoveryRecords[index].id) {
            recoveryRecords[index].payload = nil
        }
        if let id = recoveryAttentionID, ids.contains(id) { recoveryAttentionID = nil }
    }


    @discardableResult
    mutating func handle(_ event: Event) -> Action {
        switch (state, event) {
        case (.idle, .hotKeyDown),
             (.succeeded, .hotKeyDown),
             (.error, .hotKeyDown):
            state = .requestingPermission
            return .beginRequest

        case (.requestingPermission, .resumeFailed):
            state = .paused
            return .none

        case (.requestingPermission, .retryStarted):
            state = .transcribing
            return .none

        case (.requestingPermission, .captureStarted):
            state = .listening
            return .none

        case (.listening, .pauseRequested):
            state = .pausing
            return .finishCapture

        case (.pausing, .capturePaused):
            state = .paused
            return .none

        case (.paused, .resumeRequested):
            state = .requestingPermission
            return .beginRequest

        case (.paused, .finishRequested), (.pausing, .finishRequested):
            state = .transcribing
            return .finishCapture

        case (.listening, .hotKeyUp):
            state = .transcribing
            return .finishCapture

        case (.transcribing, .audioTooShort):
            state = .idle
            return .none

        case (.transcribing, .transcriptionCompleted):
            state = .inserting
            return .insert

        case (.transcribing, .transcriptSaved(let transcript)),
             (.inserting, .transcriptSaved(let transcript)):
            state = .succeeded(transcript)
            return .none

        case (.inserting, .insertionCompleted(let transcript)):
            state = .succeeded(transcript)
            return .none

        case (_, .failed(let failure)):
            state = .error(failure)
            return .none

        case (.idle, .cancel):
            return .none

        case (_, .cancel),
             (.requestingPermission, .hotKeyUp):
            state = .idle
            return .cancel

        default:
            // Repeated down events and unmatched up events are intentionally ignored.
            return .none
        }
    }
}

struct DictationRecoveryRecord: Equatable, Sendable, Identifiable {
    enum Payload: Equatable, Sendable {
        case text(String)
        case audio(DictationAudio)
    }
    enum CopyStatus: Equatable, Sendable { case untouched, copied }
    let id: UUID
    let sessionID: UUID
    let plan: DictationSessionPlan
    var payload: Payload?
    var outcome: DictationInsertionOutcome
    var receipt: DictationDeliveryReceipt?
    var reason: String?
    var retryOf: UUID?
    var receipts: [DictationDeliveryReceipt] = []
    var copyStatus: CopyStatus = .untouched
}
