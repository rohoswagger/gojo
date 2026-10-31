import Foundation

actor DictationModelResidency {
    enum Resource: CaseIterable, Sendable { case recognizer, polisher }

    struct RuntimeLease: Equatable, Sendable {
        fileprivate let id: UUID
        fileprivate let resource: Resource
        let generation: UInt64
    }

    private enum Access { case read, maintenance }
    private struct Admission {
        let id: UUID
        let access: Access
        let resource: Resource
        let continuation: CheckedContinuation<Void, Never>
    }

    private let idleDelay: Duration
    private let releaseModels: @Sendable () async -> Void
    private var policy: DictationResidencyPolicy = .keepWarm
    private var leases: Set<UUID> = []
    private var readers: [Resource: Set<UUID>] = [:]
    private var maintenance: [Resource: UUID] = [:]
    private var pendingAdmissions: [Admission] = []
    private var runtimeGeneration: [Resource: UInt64] = [:]
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

    func acquireRead(_ resource: Resource = .recognizer) async -> RuntimeLease {
        await acquireRuntime(.read, resource: resource)
    }

    func acquireMaintenance(_ resource: Resource = .recognizer) async -> RuntimeLease {
        await acquireRuntime(.maintenance, resource: resource)
    }

    private func acquireRuntime(_ access: Access, resource: Resource) async -> RuntimeLease {
        let id = UUID()
        cancelTimer()
        await withCheckedContinuation { continuation in
            pendingAdmissions.append(Admission(id: id, access: access, resource: resource, continuation: continuation))
            admitWaitingOperations()
        }
        if let pending = eviction {
            await pending.task.value
            if eviction?.id == pending.id { eviction = nil }
        }
        return RuntimeLease(id: id, resource: resource, generation: runtimeGeneration[resource, default: 0])
    }

    func release(_ lease: RuntimeLease) async {
        if maintenance[lease.resource] == lease.id {
            maintenance.removeValue(forKey: lease.resource)
        } else {
            guard readers[lease.resource]?.remove(lease.id) != nil else { return }
        }
        admitWaitingOperations()
        scheduleTimerIfIdle()
    }

    private func admitWaitingOperations() {
        for resource in Resource.allCases where maintenance[resource] == nil {
            while let index = pendingAdmissions.firstIndex(where: { $0.resource == resource }) {
                let next = pendingAdmissions[index]
                if next.access == .maintenance, !readers[resource, default: []].isEmpty { break }
                pendingAdmissions.remove(at: index)
                switch next.access {
                case .read:
                    readers[resource, default: []].insert(next.id)
                case .maintenance:
                    maintenance[resource] = next.id
                    runtimeGeneration[resource, default: 0] &+= 1
                }
                next.continuation.resume()
                if maintenance[resource] != nil { break }
            }
        }
    }

    private var isIdle: Bool {
        leases.isEmpty && readers.values.allSatisfy(\.isEmpty) && maintenance.isEmpty && pendingAdmissions.isEmpty
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
        guard policy == .releaseAfterIdle, isIdle, eviction == nil else { return }
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
              isIdle, eviction == nil else { return }
        timer = nil
        for resource in Resource.allCases { runtimeGeneration[resource, default: 0] &+= 1 }
        let id = UUID()
        let releaseModels = releaseModels
        let task = Task { await releaseModels() }
        eviction = (id, task)
        await task.value
        if eviction?.id == id { eviction = nil }
    }
}
