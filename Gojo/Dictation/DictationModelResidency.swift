import Foundation

actor DictationModelResidency {
    private let idleDelay: Duration
    private let releaseModels: @Sendable () async -> Void
    private var policy: DictationResidencyPolicy = .keepWarm
    private var leases: Set<UUID> = []
    private var timer: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var eviction: (id: UUID, task: Task<Void, Never>)?

    init(
        idleDelay: Duration = .seconds(60),
        releaseModels: @escaping @Sendable () async -> Void
    ) {
        self.idleDelay = idleDelay
        self.releaseModels = releaseModels
    }

    func acquire() async -> UUID {
        let id = UUID()
        leases.insert(id)
        cancelTimer()
        if let pending = eviction {
            await pending.task.value
            if eviction?.id == pending.id { eviction = nil }
        }
        return id
    }

    func release(_ id: UUID) async {
        guard leases.remove(id) != nil else { return }
        scheduleTimerIfIdle()
    }

    func setPolicy(_ policy: DictationResidencyPolicy) async {
        guard self.policy != policy else { return }
        self.policy = policy
        cancelTimer()
        scheduleTimerIfIdle()
    }

    private func cancelTimer() {
        generation &+= 1
        timer?.cancel()
        timer = nil
    }

    private func scheduleTimerIfIdle() {
        guard policy == .releaseAfterIdle, leases.isEmpty, eviction == nil else { return }
        cancelTimer()
        let expectedGeneration = generation
        let delay = idleDelay
        timer = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch { return }
            await self?.evict(ifGeneration: expectedGeneration)
        }
    }

    private func evict(ifGeneration expectedGeneration: UInt64) async {
        guard generation == expectedGeneration, policy == .releaseAfterIdle,
              leases.isEmpty, eviction == nil else { return }
        timer = nil
        let id = UUID()
        let releaseModels = releaseModels
        let task = Task { await releaseModels() }
        eviction = (id, task)
        await task.value
        if eviction?.id == id { eviction = nil }
    }
}
