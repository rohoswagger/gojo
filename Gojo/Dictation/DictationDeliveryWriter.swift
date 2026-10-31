import Foundation

final class DictationDeliveryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func withCommitPermission<T>(_ effect: () -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return nil }
        return effect()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
final class DictationDeliveryWriter {
    static let shared = DictationDeliveryWriter()
    let identity = "host:\(UUID().uuidString)"
    private var completed: [UUID: NSDictionary] = [:]
    private var pending: [UUID: Task<Void, Never>] = [:]
    private var tail: Task<Void, Never>?
    private(set) var admissionBlocked = false
    private let maximumTransactions = 4096

    func perform(
        transactionID: UUID,
        operation: @escaping @MainActor () async -> NSDictionary
    ) async -> NSDictionary {
        if let result = completed[transactionID] { return result }
        if let task = pending[transactionID] {
            await task.value
            return completed[transactionID]!
        }
        guard completed.count + pending.count < maximumTransactions else {
            return result(transactionID: transactionID, error: "deliveryHistoryFull")
        }
        let previous = tail
        let task = Task { @MainActor in
            _ = await previous?.value
            let value: NSDictionary
            if self.admissionBlocked {
                value = self.result(transactionID: transactionID, error: "writerCleanupBlocked")
            } else {
                let acknowledged = await operation()
                if acknowledged["transactionID"] as? String == transactionID.uuidString {
                    value = acknowledged
                } else {
                    value = ["transactionID": transactionID.uuidString, "writerID": "unacknowledged",
                             "disposition": "partialUnknown", "writerQuiescent": false,
                             "authorized": true, "success": false, "method": "none", "error": "invalidDeliveryReceipt"]
                }
                if (value["writerQuiescent"] as? NSNumber)?.boolValue != true { self.admissionBlocked = true }
            }
            self.completed[transactionID] = value
            self.pending.removeValue(forKey: transactionID)
        }
        pending[transactionID] = task
        tail = task
        await task.value
        return completed[transactionID]!
    }

    private func result(transactionID: UUID, error: String) -> NSDictionary {
        ["transactionID": transactionID.uuidString, "writerID": identity,
         "disposition": "notSent", "writerQuiescent": true,
         "authorized": true, "success": false, "method": "none", "error": error]
    }
}
