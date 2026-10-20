import Foundation

@main struct ModelPreparationRegression {
    static func main() throws {
        let diskError = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXErrorCode.ENOSPC.rawValue))
        let cocoaError = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileWriteOutOfSpace.rawValue)
        for error in [diskError, cocoaError,
                      NSError(domain: "CoreML", code: 1, userInfo: [NSUnderlyingErrorKey: diskError]),
                      NSError(domain: "CoreML", code: 2, userInfo: [NSMultipleUnderlyingErrorsKey: [cocoaError]])] {
            let detail = DictationModelPreparationError.userFacingDetail(for: error)
            precondition(detail.contains("disk space") && detail.contains("try again"), "Storage failures need an actionable message")
        }
        let unrelated = NSError(domain: "AnotherDomain", code: Int(POSIXErrorCode.ENOSPC.rawValue), userInfo: [NSLocalizedDescriptionKey: "Model initialization failed"])
        let detail = DictationModelPreparationError.userFacingDetail(for: unrelated)
        precondition(detail.contains("Model initialization failed") && !detail.contains("disk space"), "Only domain-matched disk errors may be classified as low storage")
        do {
            try DictationModelPreparationError.checkStorage(capacity: { 656 * 1_048_576 })
            preconditionFailure("Low storage must fail before starting Core ML")
        } catch DictationModelPreparationError.insufficientStorage {}
        try DictationModelPreparationError.checkStorage(capacity: { 2_147_483_648 })
        do {
            try DictationModelPreparationError.checkStorage(capacity: { throw unrelated })
            preconditionFailure("An unavailable capacity check must report its own failure")
        } catch DictationModelPreparationError.storageCheckFailed(let reason) {
            precondition(reason.contains("Model initialization failed"))
        }
        print("Dictation model preparation error regressions passed")
    }
}
