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
}
