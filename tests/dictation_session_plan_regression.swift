import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct DictationSessionPlanRegression {
    static func main() throws {
        try englishModelsRejectUnsupportedRequests()
        try multilingualCapabilities()
        try savedLanguageValidation()
        try frozenValueSnapshots()
        try previewCapabilityGate()
        for model in [DictationModelID.underdogBark3English, .underdogBark3CleanEnglish] {
            let bark = try DictationLocalRecognition(model: model)
            let direct = DictationSessionPlan(recognition: .local(bark))
            require(direct.text.cleanup == .off, "Both Bark variants work without an LLM cleanup model")
            require(!direct.supportsRecognizedPreview, "Bark does not advertise provisional preview")
            let polished = DictationSessionPlan(recognition: .local(bark), text: DictationTextOptions(cleanup: .s1Mini(.formal)))
            require(polished.text.cleanup == .s1Mini(.formal), "Both Bark variants honor explicit optional AI polish")
            require(DictationModelID.resolveSelection(bark.model.rawValue) == model, "saved Bark selections round trip")
        }
        defaultBehavior()
        textIntentCleanup()
        currentLearningConsentWins()
        speechEvidencePreservesAudioAdmission()
        print("Dictation session plan regression passed")
    }

    private static func expectFailure(
        _ expected: DictationRecognitionValidationError,
        _ operation: () throws -> DictationLocalRecognition
    ) {
        do {
            _ = try operation()
            require(false, "unsupported recognition request must fail")
        } catch let failure as DictationRecognitionValidationError {
            require(failure == expected, "recognition validation returns the exact failure")
        } catch {
            require(false, "unexpected recognition validation error \(error)")
        }
    }

    private static func englishModelsRejectUnsupportedRequests() throws {
        for model in [DictationModelID.whisperSmallEnglish, .parakeetUnifiedEnglish, .underdogBark3English, .underdogBark3CleanEnglish] {
            let descriptor = DictationModelDescriptor.descriptor(for: model)
            let request = try descriptor.resolveRecognition()
            require(request.model == model, "recognition retains the selected English model")
            require(request.language == .fixed("en"), "English models default to English")
            require(!request.translateToEnglish, "English models retain transcription")
            expectFailure(.unsupportedLanguage(model, "pt")) {
                try descriptor.resolveRecognition(language: .fixed("pt"))
            }
            expectFailure(.automaticLanguageUnavailable(model)) {
                try descriptor.resolveRecognition(language: .automatic)
            }
            expectFailure(.translationUnavailable(model)) {
                try descriptor.resolveRecognition(translateToEnglish: true)
            }
        }
    }

    private static func multilingualCapabilities() throws {
        let large = DictationModelDescriptor.descriptor(for: .whisperLargeV3)
        let english = try large.resolveRecognition()
        require(english.language == .fixed("en"), "Large preserves its existing English default")
        for selection in [DictationLanguageSelection.automatic, .fixed("es"), .fixed("pt"), .fixed("haw"), .fixed("yue")] {
            let request = try large.resolveRecognition(language: selection, translateToEnglish: true)
            require(request.language == selection, "Large keeps the explicit recognition language")
            require(request.translateToEnglish, "Large admits explicit English translation")
        }
        let v3 = DictationModelDescriptor.descriptor(for: .parakeetV3Multilingual)
        let detected = try v3.resolveRecognition()
        require(detected.language == .automatic, "Parakeet v3 defaults to detection")
        expectFailure(.fixedLanguageUnavailable(.parakeetV3Multilingual)) {
            try v3.resolveRecognition(language: .fixed("en"))
        }
        expectFailure(.translationUnavailable(.parakeetV3Multilingual)) {
            try v3.resolveRecognition(translateToEnglish: true)
        }
        require(v3.capabilities.language.supportedLanguageCodes.contains("pt"), "v3 language guidance includes Portuguese")
        require(!v3.capabilities.language.supportedLanguageCodes.contains("ja"), "v3 guidance stays with the installed European model")
        let previewModels = DictationModelDescriptor.all.filter { $0.capabilities.supportsRecognizedPreview }.map(\.id)
        require(previewModels == [.parakeetUnifiedEnglish], "only installed Unified decoding supports recognized preview")
    }

    private static func savedLanguageValidation() throws {
        let large = DictationModelDescriptor.descriptor(for: .whisperLargeV3)
        let missing = try large.resolveRecognition(persistedLanguageCode: nil)
        let detected = try large.resolveRecognition(persistedLanguageCode: "auto")
        let fixed = try large.resolveRecognition(persistedLanguageCode: "es")
        require(missing.language == .fixed("en"), "missing saved language preserves English")
        require(detected.language == .automatic, "saved auto resolves explicitly")
        require(fixed.language == .fixed("es"), "saved supported code resolves explicitly")
        for code in ["", "English", "pt-BR", "ES", "zz", "en\n"] {
            expectFailure(.unsupportedLanguage(.whisperLargeV3, code)) {
                try large.resolveRecognition(persistedLanguageCode: code)
            }
        }
        expectFailure(.automaticLanguageUnavailable(.whisperSmallEnglish)) {
            try DictationModelDescriptor.descriptor(for: .whisperSmallEnglish)
                .resolveRecognition(persistedLanguageCode: "auto")
        }
    }

    private static func frozenValueSnapshots() throws {
        var terms = ["PostgreSQL", "Gojo"]
        var vocabulary = [DictationVocabularyEntry(spoken: "post grez", replacement: "PostgreSQL")]
        let request = try DictationLocalRecognition(model: .whisperLargeV3, recognitionTerms: terms)
        let options = DictationTextOptions(vocabulary: vocabulary, cleanup: .s1Mini(.formal))
        let plan = DictationSessionPlan(recognition: .local(request), text: options)
        let copy = plan
        terms[0] = "changed"
        terms.append("next session")
        vocabulary[0].replacement = "changed"
        vocabulary.removeAll()
        require(plan == copy, "a copied plan keeps the complete frozen snapshot")
        guard case .local(let frozen) = plan.recognition else {
            require(false, "frozen plan retains local recognition")
            return
        }
        require(frozen.recognitionTerms == ["PostgreSQL", "Gojo"], "recognition terms survive later preference edits")
        require(plan.text.vocabulary.map(\.replacement) == ["PostgreSQL"], "vocabulary survives later preference edits")
        require(plan.text.cleanup == .s1Mini(.formal), "cleanup and style stay in the session snapshot")
    }

    private static func defaultBehavior() {
        let plan = DictationSessionPlan()
        require(plan.mode == .singleUtterance, "default plan uses held capture")
        require(plan.pauseDuration == 0.9, "default plan uses natural pauses")
        require(plan.targetPolicy == .fixed, "default plan freezes the target")
        require(plan.purpose == .focusedField, "default plan delivers to the focused field")
        require(plan.recognition == .local(.english), "default plan keeps local Small English")
        require(plan.text.intent == .standard, "default plan preserves existing output intent")
        require(plan.text.commands == .off, "default plan does not reinterpret spoken words")
        require(plan.text.cleanup == .off, "default cleanup remains opt-in")
        require(plan.capture.input == .systemDefault, "default capture follows the system microphone")
        require(plan.capture.adaptiveSpeech, "default capture enables bounded speech adaptation")
        require(!plan.previewEnabled && !plan.capture.previewEnabled, "recognized preview remains opt-in")
        require(!plan.cuesEnabled, "cues remain opt-in")
        require(plan.learnsCorrections, "learning keeps the existing default")
        require(DictationSessionPlan(pauseDuration: .nan).pauseDuration == 0.9, "invalid external pause duration falls back to natural")
    }

    private static func previewCapabilityGate() throws {
        let enabled = DictationCaptureConfiguration(previewEnabled: true)
        let unsupported = DictationSessionPlan(capture: enabled)
        require(!unsupported.previewEnabled, "unsupported recognition disables the preview preference")
        let unified = try DictationLocalRecognition(model: .parakeetUnifiedEnglish)
        let held = DictationSessionPlan(recognition: .local(unified), capture: enabled)
        require(held.previewEnabled, "held Unified capture admits opt-in recognized preview")
        let continuous = DictationSessionPlan(mode: .continuous, recognition: .local(unified), capture: enabled)
        require(!continuous.previewEnabled, "continuous capture keeps its existing final-phrase pipeline")
        let cloud = DictationSessionPlan(recognition: .openRouter(modelID: "configured-model"), capture: enabled)
        require(!cloud.previewEnabled, "cloud recognition has no invented preview capability")
    }

    private static func textIntentCleanup() {
        for intent in [DictationSessionIntent.literal, .code] {
            let text = DictationTextOptions(intent: intent, cleanup: .s1Mini(.casual))
            require(text.cleanup == .off, "Literal and Code bypass semantic cleanup")
        }
        let literal = DictationTextOptions(intent: .literal, commands: .punctuationAndCode)
        require(literal.commands == .off, "Literal keeps spoken command words literal")
        let code = DictationTextOptions(intent: .code, commands: .punctuationAndCode)
        require(code.commands == .punctuationAndCode, "Code keeps explicitly selected spoken commands")
        require(DictationTextOptions(intent: .chat).cleanup == .off, "Chat only cleans up when explicitly enabled")
        let chat = DictationTextOptions(intent: .chat, commands: .punctuation, commandLanguage: .spanish, cleanup: .s1Mini(.formal))
        require(chat.cleanup == .s1Mini(.formal), "Chat keeps the explicitly chosen writing style")
        require(chat.commandLanguage == .spanish, "command language stays explicit")
    }

    private static func currentLearningConsentWins() {
        let enabled = DictationSessionPlan(learnsCorrections: true)
        let disabled = DictationSessionPlan(learnsCorrections: false)
        require(enabled.mayLearnCorrections(currentConsent: true), "both frozen and current consent allow learning")
        require(!enabled.mayLearnCorrections(currentConsent: false), "revoking consent stops learning from an active session")
        require(!disabled.mayLearnCorrections(currentConsent: true), "enabling consent cannot opt an earlier session into learning")
        require(!disabled.mayLearnCorrections(currentConsent: false), "disabled learning stays disabled")
    }

    private static func speechEvidencePreservesAudioAdmission() {
        let samples = Array(repeating: Float.zero, count: 3_200)
        let plain = DictationAudio(samples: samples)
        let silence = DictationAudio(samples: samples, speechEvidence: .silence)
        require(plain.speechEvidence == nil, "existing capture callers have no speech-evidence override")
        require(DictationAudioPolicy().shouldTranscribe(plain), "existing minimum-duration admission remains unchanged")
        require(!DictationAudioPolicy().shouldTranscribe(silence), "confirmed silence is not sent to recognition")
        let uncertain = DictationAudio(samples: samples, speechEvidence: .uncertain)
        require(DictationAudioPolicy().shouldTranscribe(uncertain), "uncertain audio stays eligible for recognition")
        let invalid = DictationAudio(samples: [.nan] + samples.dropFirst())
        require(!DictationAudioPolicy().shouldTranscribe(invalid), "nonfinite samples never reach a decoder")
        let invalidRate = DictationAudio(samples: samples, sampleRate: .infinity)
        require(!DictationAudioPolicy().shouldTranscribe(invalidRate), "nonfinite sample rates cannot satisfy admission")
    }
}
