import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

private func receipt(_ id: UUID, _ disposition: String, quiet: Bool = true) -> NSDictionary {
    ["transactionID": id.uuidString, "writerID": "host:test", "disposition": disposition,
     "writerQuiescent": quiet, "authorized": true, "success": true]
}

@main
struct DeliveryReceiptRegression {
    @MainActor static func main() async {
        require(DictationInsertionOutcome.unverified.recoveryMessage == nil,
                "All dispatched Unicode must stay passive instead of opening recovery")
        print("PASS: All dispatched Unicode stays passive")
        let id = UUID()
        let confirmed = DictationDeliveryReceipt(dictionary: receipt(id, "confirmed"))!
        require(confirmed.transactionID == id && confirmed.writerID == "host:test" && confirmed.writerQuiescent,
                "Receipt preserves actual writer identity and transaction")
        require(DictationInsertionOutcome.receipt(confirmed).recoveryMessage == nil, "Confirmed remains quiet")
        require(DictationInsertionOutcome.notSent("Target changed").recoveryMessage == "Target changed",
                "Not-sent retains actual reason")
        require(DictationInsertionOutcome.partialUnknown("Interrupted").recoveryMessage?.contains("may already") == true,
                "Partial never promises no insertion")
        require(DictationDeliveryReceipt(dictionary: ["transactionID": id.uuidString]) == nil,
                "Incomplete wire replies cannot masquerade as delivery receipts")
        print("PASS: Receipt identity, certainty, quiescence and honest recovery reasons")

        let writer = DictationDeliveryWriter()
        let nextID = UUID()
        var calls: [Int] = []
        var release: CheckedContinuation<Void, Never>?
        var firstResult: NSDictionary?
        var duplicateResult: NSDictionary?
        let first = Task { @MainActor in
            firstResult = await writer.perform(transactionID: id) {
                calls.append(1)
                await withCheckedContinuation { release = $0 }
                return receipt(id, "allDispatched")
            }
        }
        while release == nil { await Task.yield() }
        let duplicate = Task { @MainActor in
            duplicateResult = await writer.perform(transactionID: id) { calls.append(99); return receipt(id, "confirmed") }
        }
        let next = Task { @MainActor in
            _ = await writer.perform(transactionID: nextID) { calls.append(2); return receipt(nextID, "confirmed") }
        }
        for _ in 0..<10 { await Task.yield() }
        require(calls == [1], "Second writer must wait for physical writer acknowledgement")
        release?.resume()
        await first.value
        await duplicate.value
        _ = await next.value
        require(firstResult?.isEqual(duplicateResult) == true, "Repeated pending ID must return the same receipt")
        _ = await writer.perform(transactionID: id) { calls.append(100); return receipt(id, "confirmed") }
        require(calls == [1, 2], "Pending and completed IDs never repeat writes")
        print("PASS: Shared writer serializes all paths and deduplicates pending/completed IDs")

        let blocked = DictationDeliveryWriter()
        _ = await blocked.perform(transactionID: UUID()) { receipt(UUID(), "partialUnknown", quiet: false) }
        var blockedCalls = 0
        let rejected = await blocked.perform(transactionID: UUID()) {
            blockedCalls += 1
            return receipt(UUID(), "confirmed")
        }
        require(blockedCalls == 0 && rejected["disposition"] as? String == "notSent" && blocked.admissionBlocked,
                "Unknown helper quiescence must keep global writer admission blocked")
        let cancellation = DictationDeliveryCancellation()
        cancellation.cancel()
        require(cancellation.isCancelled, "Cancellation persists without cancelling receipt accounting")
        print("PASS: Unacknowledged physical writer blocks later writes")
    }
}
