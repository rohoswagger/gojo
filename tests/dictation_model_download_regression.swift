import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private enum InstallFailure: Error { case snapshot, validation }

private actor LocalDictationTranscriber {
    private var callbacks: [@Sendable (Double) -> Void] = []
    private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
    var attempts: Int { callbacks.count }

    func install(
        _ model: DictationModelID,
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let attempt = callbacks.count
        callbacks.append(onProgress)
        try await withCheckedThrowingContinuation { continuations[attempt] = $0 }
    }

    func emit(_ fraction: Double, attempt: Int) { callbacks[attempt](fraction) }

    func finish(_ attempt: Int, failure: InstallFailure? = nil) {
        guard let continuation = continuations.removeValue(forKey: attempt) else {
            preconditionFailure("Attempt has not started")
        }
        if let failure { continuation.resume(throwing: failure) }
        else { continuation.resume() }
    }
}

@MainActor
private final class GojoDictationService {
    let localTranscriber: LocalDictationTranscriber
    let modelResidency = DictationModelResidency {}
    var installedModels: Set<DictationModelID> = []
    var modelOperation: DictationModelOperation?
    var modelDownload: DictationModelDownload?
    var modelErrors: [DictationModelID: String] = [:]
    var canChangeModel: Bool { modelOperation == nil }

    init(_ localTranscriber: LocalDictationTranscriber) {
        self.localTranscriber = localTranscriber
    }

    func receive(_ fraction: Double, id: UUID) { receiveModelDownloadProgress(fraction, id: id) }
    func finish(_ id: UUID) { finishModelDownload(id: id) }

    #error("__PRODUCTION_SERVICE_MEMBERS__")
}

@main
private struct DictationModelDownloadRegression {
    @MainActor
    static func main() async {
        reducer()
        await serviceLifecycle()
        print("Dictation model download reducer and production service regression passed")
    }

    private static func reducer() {
        let initial = DictationModelDownload(id: UUID(), model: .whisperSmallEnglish, phase: .preparing)
        require(initial.phase == .preparing, "download begins preparing")
        for fraction in [Double.nan, .infinity, -.infinity] {
            require(initial.advancing(to: fraction) == initial, "nonfinite preparation events are ignored")
        }
        let zero = initial.advancing(to: -2)
        require(zero.phase == .downloading(0), "negative progress clamps to zero")
        let partial = zero.advancing(to: 0.42)
        require(partial.phase == .downloading(0.42), "partial file progress remains determinate")
        require(partial.id == initial.id && partial.model == initial.model, "reducer preserves attempt identity")
        for fraction in [0.1, 0.42, Double.nan, .infinity, -.infinity] {
            require(partial.advancing(to: fraction) == partial, "invalid or regressing events do not change partial progress")
        }
        let verifying = partial.advancing(to: 1)
        require(verifying.phase == .verifying, "snapshot completion begins verification")
        require(initial.advancing(to: 3).phase == .verifying, "oversized progress clamps to completion")
        for fraction in [0, 0.75, 1, Double.nan, .infinity] {
            require(verifying.advancing(to: fraction) == verifying, "verification is terminal")
        }
    }

    @MainActor
    private static func eventually(_ message: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<2_000 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        require(false, message)
    }

    @MainActor
    private static func serviceLifecycle() async {
        let backend = LocalDictationTranscriber()
        let service = GojoDictationService(backend)
        let model = DictationModelID.parakeetV3Multilingual
        service.downloadModel(model)
        let first = service.modelDownload!
        require(first.model == model && first.phase == .preparing, "service publishes preparation synchronously")
        require(service.modelOperation == .installing(model), "existing operation blocks concurrent model actions")
        service.downloadModel(.whisperSmallEnglish)
        require(service.modelDownload == first, "blocked download leaves the first attempt intact")
        await eventually("first install starts") { await backend.attempts == 1 }
        await backend.emit(0.42, attempt: 0)
        await eventually("callback publishes partial progress") { service.modelDownload?.phase == .downloading(0.42) }
        await backend.emit(0.1, attempt: 0)
        await backend.emit(.nan, attempt: 0)
        await backend.emit(1, attempt: 0)
        await eventually("callback enters verification") { service.modelDownload?.phase == .verifying }
        await backend.emit(0.8, attempt: 0)
        await backend.finish(0)
        await eventually("successful download cleans up") { service.modelOperation == nil }
        require(service.modelDownload == nil, "successful download clears progress")
        require(service.installedModels == [model] && service.modelErrors[model] == nil, "success updates installed status")
        await backend.emit(0.9, attempt: 0)
        service.receive(1, id: first.id)
        require(service.modelDownload == nil, "completed callback cannot resurrect progress")
        service.downloadModel(model)
        require(service.modelDownload == nil, "installed model rejects another download")

        let retryModel = DictationModelID.whisperSmallEnglish
        service.downloadModel(retryModel)
        let failed = service.modelDownload!
        await eventually("failure attempt starts") { await backend.attempts == 2 }
        await backend.emit(0.25, attempt: 1)
        await eventually("snapshot failure has partial progress") { service.modelDownload?.phase == .downloading(0.25) }
        await backend.finish(1, failure: .snapshot)
        await eventually("snapshot error cleans up") { service.modelOperation == nil }
        require(service.modelDownload == nil && !service.installedModels.contains(retryModel), "snapshot error clears progress without installing")
        require(service.modelErrors[retryModel] == "Could not download this model. Check your connection and try again.", "snapshot error retains retryable message")

        service.downloadModel(retryModel)
        let retry = service.modelDownload!
        require(retry.id != failed.id && retry.phase == .preparing, "retry gets a fresh attempt and preparation")
        require(service.modelErrors[retryModel] == nil, "retry clears the old error")
        service.receive(1, id: failed.id)
        service.finish(failed.id)
        await backend.emit(1, attempt: 1)
        require(service.modelDownload == retry, "old callbacks and completion leave the retry intact")
        await eventually("retry starts") { await backend.attempts == 3 }
        await backend.emit(1, attempt: 2)
        await eventually("validation starts") { service.modelDownload?.phase == .verifying }
        await backend.finish(2, failure: .validation)
        await eventually("validation error cleans up") { service.modelOperation == nil }
        require(service.modelDownload == nil && !service.installedModels.contains(retryModel), "validation error clears verification without installing")
        require(service.modelErrors[retryModel] != nil, "validation error remains visible")

        service.downloadModel(retryModel)
        await eventually("cached fast path starts") { await backend.attempts == 4 }
        await backend.finish(3)
        await eventually("cached fast path completes") { service.modelOperation == nil }
        require(service.modelDownload == nil && service.installedModels.contains(retryModel), "cache-valid success can finish directly from preparing")
        require(service.modelErrors[retryModel] == nil, "cached success clears prior errors")

        let mismatched = DictationModelDownload(id: UUID(), model: .whisperLargeV3, phase: .preparing)
        service.modelDownload = mismatched
        service.modelOperation = .installing(.underdogBark3English)
        service.receive(0.5, id: mismatched.id)
        require(service.modelDownload == mismatched, "current ID cannot update a different installing model")
        service.modelOperation = .selecting(mismatched.model)
        service.receive(1, id: mismatched.id)
        require(service.modelDownload == mismatched, "selection does not accept download progress")
        service.finish(mismatched.id)
        require(service.modelDownload == nil && service.modelOperation == .selecting(mismatched.model), "matching cleanup leaves another operation intact")
    }
}
