import Foundation

enum DictationSessionPurpose: Equatable, Sendable {
    case focusedField
    case practice(UUID)
}

enum DictationLanguageSelection: Equatable, Codable, Sendable {
    case automatic
    case fixed(String)

    var persistedCode: String {
        switch self {
        case .automatic: return "auto"
        case .fixed(let code): return code
        }
    }
}

enum DictationModelLanguageCapability: Equatable, Sendable {
    case fixedEnglish
    case automaticOnly(supportedLanguages: Set<String>)
    case selectable(supportedLanguages: Set<String>)

    var supportedLanguageCodes: Set<String> {
        switch self {
        case .fixedEnglish: return ["en"]
        case .automaticOnly(let languages), .selectable(let languages): return languages
        }
    }

    var defaultSelection: DictationLanguageSelection {
        switch self {
        case .fixedEnglish, .selectable: return .fixed("en")
        case .automaticOnly: return .automatic
        }
    }
}

struct DictationModelCapabilities: Equatable, Sendable {
    let language: DictationModelLanguageCapability
    let supportsTranslationToEnglish: Bool
    let supportsRecognizedPreview: Bool

    func validate(
        language selection: DictationLanguageSelection,
        translateToEnglish: Bool,
        model: DictationModelID
    ) throws {
        if translateToEnglish, !supportsTranslationToEnglish {
            throw DictationRecognitionValidationError.translationUnavailable(model)
        }
        switch (language, selection) {
        case (.fixedEnglish, .fixed("en")), (.automaticOnly, .automatic):
            return
        case (.fixedEnglish, .automatic):
            throw DictationRecognitionValidationError.automaticLanguageUnavailable(model)
        case (.automaticOnly, .fixed):
            throw DictationRecognitionValidationError.fixedLanguageUnavailable(model)
        case (.selectable, .automatic):
            return
        case (.fixedEnglish, .fixed(let code)):
            throw DictationRecognitionValidationError.unsupportedLanguage(model, code)
        case (.selectable(let supported), .fixed(let code)):
            guard supported.contains(code) else {
                throw DictationRecognitionValidationError.unsupportedLanguage(model, code)
            }
        }
    }
}

enum DictationRecognitionValidationError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedLanguage(DictationModelID, String)
    case automaticLanguageUnavailable(DictationModelID)
    case fixedLanguageUnavailable(DictationModelID)
    case translationUnavailable(DictationModelID)

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage(let model, let code):
            return "\(DictationModelDescriptor.descriptor(for: model).displayName) does not support language code \"\(code)\". Choose a supported language."
        case .automaticLanguageUnavailable(let model):
            return "\(DictationModelDescriptor.descriptor(for: model).displayName) supports English only."
        case .fixedLanguageUnavailable(let model):
            return "\(DictationModelDescriptor.descriptor(for: model).displayName) detects the language automatically."
        case .translationUnavailable(let model):
            return "\(DictationModelDescriptor.descriptor(for: model).displayName) does not support translation to English."
        }
    }
}

struct DictationLocalRecognition: Equatable, Sendable {
    let model: DictationModelID
    let language: DictationLanguageSelection
    let translateToEnglish: Bool
    let recognitionTerms: [String]

    static let english = DictationLocalRecognition(
        validatedModel: .whisperSmallEnglish,
        language: .fixed("en"),
        translateToEnglish: false,
        recognitionTerms: []
    )

    init(
        model: DictationModelID,
        language: DictationLanguageSelection? = nil,
        translateToEnglish: Bool = false,
        recognitionTerms: [String] = []
    ) throws {
        let capabilities = DictationModelDescriptor.descriptor(for: model).capabilities
        let selection = language ?? capabilities.language.defaultSelection
        try capabilities.validate(language: selection, translateToEnglish: translateToEnglish, model: model)
        self.init(
            validatedModel: model,
            language: selection,
            translateToEnglish: translateToEnglish,
            recognitionTerms: recognitionTerms
        )
    }

    private init(
        validatedModel model: DictationModelID,
        language: DictationLanguageSelection,
        translateToEnglish: Bool,
        recognitionTerms: [String]
    ) {
        self.model = model
        self.language = language
        self.translateToEnglish = translateToEnglish
        self.recognitionTerms = recognitionTerms
    }
}

enum DictationRecognitionRequest: Equatable, Sendable {
    case local(DictationLocalRecognition)
    case openRouter(modelID: String)
}

enum DictationSessionIntent: String, CaseIterable, Identifiable, Codable, Sendable {
    case standard
    case literal
    case code
    case chat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Standard"
        case .literal: return "Literal"
        case .code: return "Code"
        case .chat: return "Chat"
        }
    }
}

enum DictationSpokenCommandMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off
    case punctuation
    case punctuationAndCode

    var id: String { rawValue }
}

enum DictationCommandLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english
    case spanish
    case portuguese

    var id: String { rawValue }
}

enum DictationCleanupPolicy: Equatable, Sendable {
    case off
    case s1Mini(DictationWritingStyle)
}

struct DictationTextOptions: Equatable, Sendable {
    let intent: DictationSessionIntent
    let commands: DictationSpokenCommandMode
    let commandLanguage: DictationCommandLanguage
    let vocabulary: [DictationVocabularyEntry]
    let cleanup: DictationCleanupPolicy

    init(
        intent: DictationSessionIntent = .standard,
        commands: DictationSpokenCommandMode = .off,
        commandLanguage: DictationCommandLanguage = .english,
        vocabulary: [DictationVocabularyEntry] = [],
        cleanup: DictationCleanupPolicy = .off
    ) {
        self.intent = intent
        self.commands = intent == .literal ? .off : commands
        self.commandLanguage = commandLanguage
        self.vocabulary = DictationVocabularyPolicy.sanitized(vocabulary)
        switch intent {
        case .literal, .code: self.cleanup = .off
        case .standard, .chat: self.cleanup = cleanup
        }
    }
}

enum DictationInputSelection: Equatable, Codable, Sendable {
    case systemDefault
    case deviceUID(String)
}

struct DictationInputDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct DictationCaptureConfiguration: Equatable, Sendable {
    let input: DictationInputSelection
    let adaptiveSpeech: Bool
    let previewEnabled: Bool

    init(
        input: DictationInputSelection = .systemDefault,
        adaptiveSpeech: Bool = true,
        previewEnabled: Bool = false
    ) {
        self.input = input
        self.adaptiveSpeech = adaptiveSpeech
        self.previewEnabled = previewEnabled
    }
}

struct DictationCaptureSnapshot: Equatable, Sendable {
    let totalSampleCount: Int
    let sourceOffset: Int
    let audio: DictationAudio
    let isWindowed: Bool
}

struct DictationProvisionalPreview: Equatable, Sendable {
    let sessionID: UUID
    let revision: Int
    let text: String
    let isWindowed: Bool
}

enum DictationEmptyReason: Equatable, Sendable {
    case tooShort
    case noSpeech
    case noWordsRecognized
}

enum DictationCompletion: Equatable, Sendable {
    case empty(reason: DictationEmptyReason)
    case delivered
    case savedForCopying
    case cancelled
    case failed(DictationFailure)
}

enum DictationResidencyPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case keepWarm
    case releaseAfterIdle

    var id: String { rawValue }
}

struct DictationSessionPlan: Equatable, Sendable {
    let id: UUID
    let mode: DictationCaptureMode
    let pauseDuration: TimeInterval
    let targetPolicy: DictationTargetPolicy
    let purpose: DictationSessionPurpose
    let recognition: DictationRecognitionRequest
    let text: DictationTextOptions
    let capture: DictationCaptureConfiguration
    let cuesEnabled: Bool
    let learnsCorrections: Bool

    init(
        id: UUID = UUID(),
        mode: DictationCaptureMode = .singleUtterance,
        pauseDuration: TimeInterval = 0.9,
        targetPolicy: DictationTargetPolicy = .fixed,
        purpose: DictationSessionPurpose = .focusedField,
        recognition: DictationRecognitionRequest = .local(.english),
        text: DictationTextOptions = DictationTextOptions(),
        capture: DictationCaptureConfiguration = DictationCaptureConfiguration(),
        cuesEnabled: Bool = false,
        learnsCorrections: Bool = true
    ) {
        self.id = id
        self.mode = mode
        self.pauseDuration = pauseDuration.isFinite && pauseDuration > 0 ? pauseDuration : 0.9
        self.targetPolicy = targetPolicy
        self.purpose = purpose
        self.recognition = recognition
        self.text = text
        self.capture = capture
        self.cuesEnabled = cuesEnabled
        self.learnsCorrections = learnsCorrections
    }

    var supportsRecognizedPreview: Bool {
        guard mode == .singleUtterance, case .local(let request) = recognition else { return false }
        return DictationModelDescriptor.descriptor(for: request.model).capabilities.supportsRecognizedPreview
    }

    var previewEnabled: Bool {
        capture.previewEnabled && supportsRecognizedPreview
    }

    func mayLearnCorrections(currentConsent: Bool) -> Bool {
        learnsCorrections && currentConsent
    }
}

enum DictationSupportedLanguages {
    // WhisperKit Constants.languageCodes at pinned revision 25c62997041c134b03ca82731ce2f6fd2cae1eb9.
    static let whisper: Set<String> = [
        "af", "am", "ar", "as", "az", "ba", "be", "bg", "bn", "bo", "br", "bs", "ca", "cs", "cy",
        "da", "de", "el", "en", "es", "et", "eu", "fa", "fi", "fo", "fr", "gl", "gu", "ha", "haw",
        "he", "hi", "hr", "ht", "hu", "hy", "id", "is", "it", "ja", "jw", "ka", "kk", "km", "kn",
        "ko", "la", "lb", "ln", "lo", "lt", "lv", "mg", "mi", "mk", "ml", "mn", "mr", "ms", "mt",
        "my", "ne", "nl", "nn", "no", "oc", "pa", "pl", "ps", "pt", "ro", "ru", "sa", "sd", "si",
        "sk", "sl", "sn", "so", "sq", "sr", "su", "sv", "sw", "ta", "te", "tg", "th", "tk", "tl",
        "tr", "tt", "uk", "ur", "uz", "vi", "yi", "yo", "yue", "zh"
    ]

    static let parakeetV3: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv",
        "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
    ]
}
