import Foundation

struct DictationAudio: Equatable, Sendable {
    static let transcriptionSampleRate = 16_000.0

    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double = transcriptionSampleRate) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

struct DictationAudioPolicy: Equatable, Sendable {
    let minimumDuration: TimeInterval

    init(minimumDuration: TimeInterval = 0.12) {
        self.minimumDuration = max(0, minimumDuration)
    }

    func shouldTranscribe(_ audio: DictationAudio) -> Bool {
        !audio.samples.isEmpty
            && audio.sampleRate > 0
            && audio.duration >= minimumDuration
    }
}

enum DictationTranscriptPolicy {
    static func normalize(_ transcript: String) -> String {
        let collapsed = transcript
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        return collapsed
            .replacingOccurrences(of: "Go-jo", with: "Gojo", options: .caseInsensitive)
            .replacingOccurrences(of: "Go jo", with: "Gojo", options: .caseInsensitive)
    }
}

enum DictationModelRequest: Sendable {
    case settingsDownload
    case transcription

    var allowsDownload: Bool {
        self == .settingsDownload
    }
}

enum DictationModelStorage {
    private static let downloadMetadataPath = [".cache", "huggingface", "download"]

    static func hubRepositoryRoot(_ repository: String) -> URL? {
        let components = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              let documents = FileManager.default.urls(
                  for: .documentDirectory,
                  in: .userDomainMask
              ).first else {
            return nil
        }
        return components.reduce(
            documents
                .appendingPathComponent("huggingface", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true)
        ) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: true)
        }
    }

    static func storedPath(_ storedPath: String?, matches expectedURL: URL) -> Bool {
        guard let storedPath else { return false }
        let storedURL = URL(fileURLWithPath: storedPath, isDirectory: true).standardizedFileURL
        return storedURL.path == expectedURL.standardizedFileURL.path
    }

    static func removeAllowlistedItems(
        from repositoryRoot: URL,
        topLevelItems: [String]
    ) throws {
        let standardizedRoot = try validatedRemovalRoot(repositoryRoot)
        try validateTopLevelItems(topLevelItems)
        // Validate the entire metadata path before deleting the model itself.
        // This keeps a malicious intermediate symlink from turning the second
        // deletion into an escape after the first deletion has already run.
        let metadataRoot = try existingDirectory(
            beneath: standardizedRoot,
            components: downloadMetadataPath
        )
        for item in topLevelItems {
            try removeItemIfPresent(standardizedRoot.appendingPathComponent(item))
            if let metadataRoot {
                try removeItemIfPresent(metadataRoot.appendingPathComponent(item))
            }
        }
    }

    static func removeAllowlistedTopLevelItems(
        from root: URL,
        topLevelItems: [String]
    ) throws {
        let standardizedRoot = try validatedRemovalRoot(root)
        try validateTopLevelItems(topLevelItems)
        for item in topLevelItems {
            try removeItemIfPresent(standardizedRoot.appendingPathComponent(item))
        }
    }

    private static func validatedRemovalRoot(_ root: URL) throws -> URL {
        let standardizedRoot = root.standardizedFileURL
        guard standardizedRoot.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw DictationModelStorageError.unsafeRemovalTarget
        }
        return standardizedRoot
    }

    private static func validateTopLevelItems(_ items: [String]) throws {
        guard !items.isEmpty, items.allSatisfy(isSafeTopLevelName) else {
            throw DictationModelStorageError.unsafeRemovalTarget
        }
    }

    private static func existingDirectory(
        beneath root: URL,
        components: [String]
    ) throws -> URL? {
        let fileManager = FileManager.default
        var current = root
        for component in components {
            let next = current.appendingPathComponent(component, isDirectory: true).standardizedFileURL
            guard next.path.hasPrefix(root.path + "/"),
                  (try? fileManager.destinationOfSymbolicLink(atPath: next.path)) == nil else {
                throw DictationModelStorageError.unsafeRemovalTarget
            }

            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: next.path, isDirectory: &isDirectory) else {
                return nil
            }
            guard isDirectory.boolValue,
                  next.path == next.resolvingSymlinksInPath().standardizedFileURL.path else {
                throw DictationModelStorageError.unsafeRemovalTarget
            }
            current = next
        }
        return current
    }

    private static func isSafeTopLevelName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.contains("/")
            && !name.contains(":")
    }

    private static func removeItemIfPresent(_ url: URL) throws {
        let fileManager = FileManager.default
        let isSymlink = (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
        if isSymlink || fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

enum DictationModelStorageError: Error {
    case unsafeRemovalTarget
}

enum DictationEngineID: String, Sendable {
    case whisperKit
    case fluidAudio
}

enum DictationModelID: String, CaseIterable, Identifiable, Sendable {
    case whisperSmallEnglish = "whisperkit:small.en_217MB"
    case whisperLargeV3 = "whisperkit:large-v3-v20240930_626MB"
    case parakeetUnifiedEnglish = "fluidaudio:parakeet-unified-en-0.6b"
    case parakeetV3Multilingual = "fluidaudio:parakeet-tdt-0.6b-v3"

    var id: String { rawValue }

    var engine: DictationEngineID {
        switch self {
        case .whisperSmallEnglish, .whisperLargeV3:
            return .whisperKit
        case .parakeetUnifiedEnglish, .parakeetV3Multilingual:
            return .fluidAudio
        }
    }

    static func resolveSelection(_ rawValue: String?) -> DictationModelID {
        if let rawValue, let current = DictationModelID(rawValue: rawValue) {
            return current
        }
        switch rawValue {
        case WhisperDictationModel.smallEnglish.rawValue:
            return .whisperSmallEnglish
        case WhisperDictationModel.largeV3.rawValue:
            return .whisperLargeV3
        default:
            return .whisperSmallEnglish
        }
    }

    var whisperModel: WhisperDictationModel? {
        switch self {
        case .whisperSmallEnglish: return .smallEnglish
        case .whisperLargeV3: return .largeV3
        case .parakeetUnifiedEnglish, .parakeetV3Multilingual: return nil
        }
    }
}

enum DictationModelOperation: Equatable, Sendable {
    case installing(DictationModelID)
    case selecting(DictationModelID)
    case removing(DictationModelID)

    var model: DictationModelID {
        switch self {
        case .installing(let model), .selecting(let model), .removing(let model):
            return model
        }
    }
}

struct DictationModelDescriptor: Identifiable, Sendable {
    let id: DictationModelID
    let displayName: String
    let detail: String
    let downloadSizeLabel: String
    let isRecommended: Bool

    var engine: DictationEngineID { id.engine }
    var engineLabel: String {
        switch engine {
        case .whisperKit: return "WhisperKit"
        case .fluidAudio: return "FluidAudio"
        }
    }

    static let all: [DictationModelDescriptor] = [
        DictationModelDescriptor(
            id: .parakeetUnifiedEnglish,
            displayName: "Parakeet Unified",
            detail: "Strong English dictation with punctuation and capitalization",
            downloadSizeLabel: "614 MB",
            isRecommended: true
        ),
        DictationModelDescriptor(
            id: .parakeetV3Multilingual,
            displayName: "Parakeet v3",
            detail: "Fast dictation in 25 European languages",
            downloadSizeLabel: "483 MB",
            isRecommended: false
        ),
        DictationModelDescriptor(
            id: .whisperSmallEnglish,
            displayName: "Whisper Small",
            detail: "Fast and good for everyday dictation",
            downloadSizeLabel: "217 MB",
            isRecommended: false
        ),
        DictationModelDescriptor(
            id: .whisperLargeV3,
            displayName: "Whisper Large v3",
            detail: "Higher accuracy for English dictation",
            downloadSizeLabel: "626 MB",
            isRecommended: false
        ),
    ]

    static func descriptor(for id: DictationModelID) -> DictationModelDescriptor {
        all.first { $0.id == id }!
    }
}

enum WhisperDictationModel: String, CaseIterable, Identifiable, Sendable {
    case smallEnglish = "small.en_217MB"
    case largeV3 = "large-v3-v20240930_626MB"

    static let repository = "argmaxinc/whisperkit-coreml"
    static let revision = "97a5bf9bbc74c7d9c12c755d04dea59e672e3808"

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .smallEnglish: return "openai_whisper-small.en_217MB"
        case .largeV3: return "openai_whisper-large-v3-v20240930_626MB"
        }
    }

}

enum DictationFailure: Error, Equatable, Sendable {
    case modelNotInstalled
    case microphonePermissionDenied
    case targetUnavailable(String)
    case captureFailed(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case insertionFailed(String)
}

enum DictationState: Equatable, Sendable {
    case idle
    case requestingPermission
    case listening
    case transcribing
    case inserting
    case succeeded(String)
    case error(DictationFailure)
}

enum DictationSettingsStatus {
    static func title(for state: DictationState) -> String {
        switch state {
        case .idle, .succeeded:
            return "Ready"
        case .requestingPermission:
            return "Getting ready"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .inserting:
            return "Adding text"
        case .error:
            return "Could not dictate"
        }
    }
}

enum DictationShortcutEvent: Sendable {
    case keyDown
    case keyUp
    case cancel
}

/// Preserves callback order even when a global shortcut library delivers events
/// from different executors. Each event waits for the previous handler to finish.
final class DictationShortcutEventQueue: @unchecked Sendable {
    typealias Handler = @Sendable (DictationShortcutEvent) async -> Void

    private let lock = NSLock()
    private let handler: Handler
    private var tail: Task<Void, Never>?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func send(_ event: DictationShortcutEvent) {
        lock.withLock {
            let predecessor = tail
            let handler = self.handler
            let next = Task {
                await predecessor?.value
                await handler(event)
            }
            tail = next
        }
    }

    func drain() async {
        let pending = lock.withLock { tail }
        await pending?.value
    }
}
