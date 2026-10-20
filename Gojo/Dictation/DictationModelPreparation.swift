import Foundation

enum DictationModelPreparationError: LocalizedError {
    case insufficientStorage
    case storageCheckFailed(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientStorage:
            return "There is not enough free disk space to prepare the speech model. Make at least 1 GB available, then try again."
        case .storageCheckFailed(let detail):
            return "Gojo could not check available disk space. \(detail) Check your storage and try again."
        case .failed(let detail):
            return "Gojo could not prepare the speech model. \(detail)"
        }
    }

    static func userFacingDetail(for error: Error) -> String {
        classify(error).localizedDescription
    }

    static func classify(_ error: Error) -> Self {
        if let error = error as? Self { return error }
        var pending = [error as NSError]
        var visited = Set<ObjectIdentifier>()
        while let candidate = pending.popLast() {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { continue }
            if (candidate.domain == NSPOSIXErrorDomain && candidate.code == Int(POSIXErrorCode.ENOSPC.rawValue))
                || (candidate.domain == NSCocoaErrorDomain && candidate.code == CocoaError.fileWriteOutOfSpace.rawValue) {
                return .insufficientStorage
            }
            if let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? NSError { pending.append(underlying) }
            if let underlying = candidate.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] { pending.append(contentsOf: underlying) }
        }
        return .failed(error.localizedDescription)
    }

    static func checkStorage(capacity: () throws -> Int64 = availableCapacity) throws {
        let available: Int64
        do {
            available = try capacity()
        } catch {
            if case .insufficientStorage = classify(error) { throw Self.insufficientStorage }
            throw Self.storageCheckFailed(error.localizedDescription)
        }
        guard available >= 0 else { throw Self.storageCheckFailed("Available capacity is unknown.") }
        guard available >= 1_073_741_824 else { throw Self.insufficientStorage }
    }

    private static func availableCapacity() throws -> Int64 {
        let manager = FileManager.default
        var location = try manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        while !manager.fileExists(atPath: location.path), location.path != "/" {
            location.deleteLastPathComponent()
        }
        guard let available = try location.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity else {
            throw Self.storageCheckFailed("Available capacity is unknown.")
        }
        return Int64(available)
    }
}
