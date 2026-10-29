import CryptoKit
import Foundation

struct BarkModelVariant: Sendable {
    static let verbatim = Self(name: "verbatim", modelID: .underdogBark3English)
    static let clean = Self(name: "clean", modelID: .underdogBark3CleanEnglish)
    let name: String
    let modelID: DictationModelID
    var repository: String { "fixture/\(name)" }
    var revision: String { "pinned-revision" }
    var cachedModelFolderKey: String { "bark-installation-regression.\(name)" }
    var removalItems: [String] { [name] }
    var downloadPatterns: [String] { Array(modelSHA256.keys) }
    var maximumModelBytes: UInt64 { 16 }
    var modelSHA256: [String: String] {
        let hash = SHA256.hash(data: Data("verified".utf8)).map { String(format: "%02x", $0) }.joined()
        return ["\(name)/weights": hash, "\(name)/vocab": hash]
    }
}

enum BarkSpeechEngine: Sendable {
    static func load(variant: BarkModelVariant, from root: URL) async throws -> Self { .fixture }
    case fixture
    func transcribe(_ samples: [Float]) async throws -> String { "fixture" }
    func cleanup() async {}
}

enum BarkRuntimeError: Error { case unsupportedSystem }

private final class SnapshotFixture: @unchecked Sendable {
    enum Mode { case success, snapshotFailure, validationFailure }
    static let shared = SnapshotFixture()
    private let lock = NSLock()
    private var mode = Mode.success
    func setMode(_ mode: Mode) { lock.withLock { self.mode = mode } }
    func currentMode() -> Mode { lock.withLock { mode } }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double] = []
    func append(_ fraction: Double) { lock.withLock { fractions.append(fraction) } }
    var values: [Double] { lock.withLock { fractions } }
}

private enum SnapshotFailure: Error { case failed }

struct HubApiWrapper {
    struct Repo { let id: String }
    init(useBackgroundSession: Bool) {}
    func snapshot(
        from repo: Repo, revision: String, matching paths: [String],
        progressHandler: @escaping (Progress) -> Void = { _ in }
    ) async throws -> URL {
        let progress = Progress(totalUnitCount: 100)
        progress.completedUnitCount = 25
        progressHandler(progress)
        progress.completedUnitCount = 100
        progressHandler(progress)
        let mode = SnapshotFixture.shared.currentMode()
        if mode == .snapshotFailure { throw SnapshotFailure.failed }
        let folder = DictationModelStorage.hubRepositoryRoot(repo.id)!
        for path in paths {
            let file = folder.appendingPathComponent(path)
            let metadata = folder.appendingPathComponent(".cache/huggingface/download/\(path).metadata")
            if FileManager.default.fileExists(atPath: file.path),
               (try? String(contentsOf: metadata, encoding: .utf8)) == revision { continue }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: metadata.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((mode == .validationFailure ? "corrupt!" : "verified").utf8).write(to: file, options: .atomic)
            try revision.write(to: metadata, atomically: true, encoding: .utf8)
        }
        return folder
    }
}

@main struct BarkInstallationRegression {
    static func main() async throws {
        let isolatedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]!
        guard URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
            == URL(fileURLWithPath: isolatedHome).resolvingSymlinksInPath() else { throw NSError(domain: "isolated-home-required", code: 1) }
        #if arch(arm64)
        if #available(macOS 15.0, *) {
            try await repairVariants()
            return
        }
        #endif
        do {
            try await BarkDictationTranscriber().install()
            preconditionFailure("unsupported systems must reject Bark installation")
        } catch BarkRuntimeError.unsupportedSystem {}
        print("Bark unsupported-system installation guard passed")
    }

    private static func repairVariants() async throws {
        for variant in [BarkModelVariant.verbatim, .clean] {
            let backend = BarkDictationTranscriber(variant: variant)
            let progress = ProgressCapture()
            try await backend.install { progress.append($0) }
            precondition(progress.values == [0.25, 1], "snapshot completion follows partial progress")
            let cached = ProgressCapture()
            try await backend.install { cached.append($0) }
            precondition(cached.values.isEmpty, "validated cache returns directly without snapshot progress")
            let installed = await backend.isModelInstalled()
            precondition(installed)
            let root = DictationModelStorage.hubRepositoryRoot(variant.repository)!
            let corrupt = root.appendingPathComponent("\(variant.name)/vocab")
            try Data("corrupt!".utf8).write(to: corrupt, options: .atomic)
            let corruptInstalled = await backend.isModelInstalled()
            precondition(!corruptInstalled, "corruption must invalidate installed status")
            try await backend.install()
            let repairedInstalled = await backend.isModelInstalled()
            precondition(repairedInstalled, "Settings download must repair a corrupt cached model")
            let repaired = try Data(contentsOf: corrupt)
            precondition(repaired == Data("verified".utf8))
            let unrelated = root.appendingPathComponent("unrelated")
            try Data("keep".utf8).write(to: unrelated)
            try await backend.remove()
            let removedInstalled = await backend.isModelInstalled()
            precondition(!removedInstalled)
            precondition(FileManager.default.fileExists(atPath: unrelated.path))

            SnapshotFixture.shared.setMode(.snapshotFailure)
            let snapshotFailure = ProgressCapture()
            do {
                try await backend.install { snapshotFailure.append($0) }
                preconditionFailure("snapshot error must fail installation")
            } catch SnapshotFailure.failed {}
            precondition(snapshotFailure.values == [0.25], "SDK completion before a failed snapshot must not begin verification")

            SnapshotFixture.shared.setMode(.validationFailure)
            let validationFailure = ProgressCapture()
            do {
                try await backend.install { validationFailure.append($0) }
                preconditionFailure("invalid snapshot must fail verification")
            } catch BarkDictationError.integrityFailed {}
            precondition(validationFailure.values == [0.25, 1], "snapshot return begins verification before validation failure")
            let failedInstalled = await backend.isModelInstalled()
            precondition(!failedInstalled, "invalid model cannot appear installed")

            SnapshotFixture.shared.setMode(.success)
            let repairedProgress = ProgressCapture()
            try await backend.install { repairedProgress.append($0) }
            precondition(repairedProgress.values == [0.25, 1], "retry repairs the invalid snapshot and reports verification")
            try await backend.remove()
        }
        print("Bark installation progress, cache, failures, corruption repair, and removal regression passed")
    }
}
