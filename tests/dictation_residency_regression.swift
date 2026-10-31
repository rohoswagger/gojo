import Foundation

private func require(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}

private actor ReleaseProbe {
    private(set) var releases = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var blocks = false

    func block() { blocks = true }

    func releaseModels() async {
        releases += 1
        if blocks {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func unblock() {
        blocks = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor AcquisitionProbe {
    private(set) var completed = false
    func finish() { completed = true }
}

@main
struct DictationResidencyRegression {
    static func main() async throws {
        try await keepsWarmByDefault()
        try await leaseProtectsModelsThroughDeadline()
        try await cancelledTimerCannotEvictNewLease()
        try await acquisitionWaitsForEvictionAndProtectsNextDeadline()
        try await maintenanceWaitsForReaders()
        try await readersWaitForMaintenance()
        try await evictionPinDoesNotClaimRuntimeRead()
        try await runtimeAdmissionWaitsForUnload()
        try await staleReleaseCannotUnblockNewMaintenance()
        try await optionalMaintenanceDoesNotBlockRecognition()
        print("Dictation residency regression passed")
    }

    private static func waitForReleases(_ count: Int, _ probe: ReleaseProbe) async throws {
        for _ in 0..<500 {
            if await probe.releases >= count { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        fatalError("idle eviction did not finish")
    }

    private static func keepsWarmByDefault() async throws {
        let probe = ReleaseProbe()
        let residency = DictationModelResidency(idleDelay: .milliseconds(15)) {
            await probe.releaseModels()
        }
        let lease = await residency.acquire()
        await residency.release(lease)
        try await Task.sleep(for: .milliseconds(50))
        require(await probe.releases == 0, "keep warm must retain models after release")
        await residency.setPolicy(.releaseAfterIdle)
        await residency.setPolicy(.keepWarm)
        try await Task.sleep(for: .milliseconds(50))
        require(await probe.releases == 0, "turning the policy off must cancel pending disposal")
    }

    private static func leaseProtectsModelsThroughDeadline() async throws {
        let probe = ReleaseProbe()
        let residency = DictationModelResidency(idleDelay: .milliseconds(15)) {
            await probe.releaseModels()
        }
        await residency.setPolicy(.releaseAfterIdle)
        let first = await residency.acquire()
        let second = await residency.acquire()
        await residency.release(first)
        await residency.release(first)
        await residency.release(UUID())
        try await Task.sleep(for: .milliseconds(50))
        require(await probe.releases == 0, "the remaining lease must protect capture and finalization")
        await residency.release(second)
        try await waitForReleases(1, probe)
        await residency.release(second)
        try await Task.sleep(for: .milliseconds(50))
        require(await probe.releases == 1, "release must be idempotent and eviction must not repeat")
    }

    private static func cancelledTimerCannotEvictNewLease() async throws {
        let probe = ReleaseProbe()
        let residency = DictationModelResidency(idleDelay: .milliseconds(30)) {
            await probe.releaseModels()
        }
        await residency.setPolicy(.releaseAfterIdle)
        let old = await residency.acquire()
        await residency.release(old)
        try await Task.sleep(for: .milliseconds(10))
        let current = await residency.acquire()
        try await Task.sleep(for: .milliseconds(60))
        require(await probe.releases == 0, "a stale timer cannot evict models held by a new lease")
        await residency.release(current)
        try await waitForReleases(1, probe)
    }

    private static func acquisitionWaitsForEvictionAndProtectsNextDeadline() async throws {
        let probe = ReleaseProbe()
        await probe.block()
        let residency = DictationModelResidency(idleDelay: .milliseconds(15)) {
            await probe.releaseModels()
        }
        await residency.setPolicy(.releaseAfterIdle)
        try await waitForReleases(1, probe)
        let acquisition = AcquisitionProbe()
        let waiting = Task {
            let lease = await residency.acquire()
            await acquisition.finish()
            return lease
        }
        try await Task.sleep(for: .milliseconds(30))
        require(!(await acquisition.completed), "acquire must await the in-flight unload")
        await residency.setPolicy(.keepWarm)
        await residency.setPolicy(.releaseAfterIdle)
        await probe.unblock()
        let lease = await waiting.value
        try await Task.sleep(for: .milliseconds(50))
        require(await probe.releases == 1, "acquire must register its lease before awaiting eviction")
        await residency.release(lease)
        try await waitForReleases(2, probe)
    }
    private static func maintenanceWaitsForReaders() async throws {
        let residency = DictationModelResidency { }
        let reader = await residency.acquireRead()
        let completion = AcquisitionProbe()
        let maintenance = Task {
            let lease = await residency.acquireMaintenance()
            await completion.finish()
            return lease
        }
        try await Task.sleep(for: .milliseconds(30))
        require(!(await completion.completed), "maintenance must wait for the active runtime reader")
        await residency.release(reader)
        let lease = await maintenance.value
        await residency.release(lease)
    }

    private static func readersWaitForMaintenance() async throws {
        let residency = DictationModelResidency { }
        let maintenance = await residency.acquireMaintenance()
        let completion = AcquisitionProbe()
        let reading = Task {
            let lease = await residency.acquireRead()
            await completion.finish()
            return lease
        }
        try await Task.sleep(for: .milliseconds(30))
        require(!(await completion.completed), "reload must wait for positive maintenance completion")
        await residency.release(maintenance)
        let reader = await reading.value
        await residency.release(reader)
    }

    private static func evictionPinDoesNotClaimRuntimeRead() async throws {
        let probe = ReleaseProbe()
        let residency = DictationModelResidency(idleDelay: .milliseconds(15)) {
            await probe.releaseModels()
        }
        await residency.setPolicy(.releaseAfterIdle)
        let pin = await residency.acquire()
        let maintenance = await residency.acquireMaintenance()
        await residency.release(maintenance)
        try await Task.sleep(for: .milliseconds(40))
        require(await probe.releases == 0, "a residency pin must prevent idle unload without blocking explicit maintenance")
        await residency.release(pin)
        try await waitForReleases(1, probe)
    }

    private static func runtimeAdmissionWaitsForUnload() async throws {
        let probe = ReleaseProbe()
        await probe.block()
        let residency = DictationModelResidency(idleDelay: .milliseconds(15)) {
            await probe.releaseModels()
        }
        await residency.setPolicy(.releaseAfterIdle)
        try await waitForReleases(1, probe)
        let completion = AcquisitionProbe()
        let maintenance = Task {
            let lease = await residency.acquireMaintenance()
            await completion.finish()
            return lease
        }
        try await Task.sleep(for: .milliseconds(30))
        require(!(await completion.completed), "artifact maintenance must wait for unresolved runtime unload")
        await probe.unblock()
        let lease = await maintenance.value
        require(lease.generation > 0, "runtime ownership must carry the generation after unload")
        await residency.release(lease)
    }

    private static func staleReleaseCannotUnblockNewMaintenance() async throws {
        let residency = DictationModelResidency { }
        let old = await residency.acquireMaintenance()
        await residency.release(old)
        let current = await residency.acquireMaintenance()
        require(current.generation > old.generation, "exclusive ownership must advance runtime generation")
        let completion = AcquisitionProbe()
        let reading = Task {
            let lease = await residency.acquireRead()
            await completion.finish()
            return lease
        }
        await residency.release(old)
        try await Task.sleep(for: .milliseconds(30))
        require(!(await completion.completed), "an old release must not admit reload during newer maintenance")
        await residency.release(current)
        let lease = await reading.value
        require(lease.generation == current.generation, "the next runtime reader must use the admitted generation")
        await residency.release(lease)
    }

    private static func optionalMaintenanceDoesNotBlockRecognition() async throws {
        let residency = DictationModelResidency { }
        let optionalModel = await residency.acquireMaintenance(.polisher)
        let completion = AcquisitionProbe()
        let reading = Task {
            let lease = await residency.acquireRead(.recognizer)
            await completion.finish()
            return lease
        }
        try await Task.sleep(for: .milliseconds(30))
        require(await completion.completed, "optional model maintenance must not gate required recognition")
        let requiredModel = await reading.value
        require(requiredModel.generation == 0, "optional model maintenance must not invalidate the required recognizer")
        await residency.release(requiredModel)
        await residency.release(optionalModel)
    }

}
