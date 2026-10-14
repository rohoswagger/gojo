import CryptoKit
import Darwin
import Foundation

private enum FixtureError: Error {
    case integrityFailed
    case expectedFailure(String)
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

private func expectFailure(_ message: String, _ operation: () throws -> URL) throws {
    do {
        _ = try operation()
    } catch {
        return
    }
    throw FixtureError.expectedFailure(message)
}

private final class ModelFixture {
    let folder: URL
    let requiredFiles = ["weights/model.bin", "vocab.json"]
    let weights = Data("model weights".utf8)
    var validations = 0

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("gojo-model-validation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("weights", isDirectory: true),
            withIntermediateDirectories: true
        )
        try weights.write(to: weightURL)
        try Data("vocabulary".utf8).write(to: folder.appendingPathComponent("vocab.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    var weightURL: URL { folder.appendingPathComponent(requiredFiles[0]) }

    func validate(_ folder: URL) throws {
        validations += 1
        for (path, expected) in zip(requiredFiles, [weights, Data("vocabulary".utf8)]) {
            let actual = try Data(contentsOf: folder.appendingPathComponent(path))
            guard SHA256.hash(data: actual) == SHA256.hash(data: expected) else {
                throw FixtureError.integrityFailed
            }
        }
    }

    func restoreModificationDate(after mutation: () throws -> Void) throws {
        var info = stat()
        assertEqual(fstatat(AT_FDCWD, weightURL.path, &info, 0), 0, "read original file timestamps")
        try mutation()
        let timestamps = [info.st_atimespec, info.st_mtimespec]
        let result = timestamps.withUnsafeBufferPointer {
            utimensat(AT_FDCWD, weightURL.path, $0.baseAddress, 0)
        }
        assertEqual(result, 0, "restore the exact original modification timestamp")
    }
}

@main
private enum DictationModelValidationRegression {
    static func main() throws {
        try unchangedFilesReuseValidation()
        try replacementRequiresValidation()
        try inPlaceCorruptionRequiresValidation()
        try missingFileRejectsReceipt()
        try changesDuringValidationRejectReceipt()
        try failedValidationClearsReceipt()
        try invalidationRequiresValidation()
        try changedFolderRequiresValidation()
        try changedRequiredFilesRequireValidation()
        print("dictation-model-validation-regression-pass")
    }

    private static func unchangedFilesReuseValidation() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        let first = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        let second = try cache.validatedFolder(at: fixture.folder, requiredFiles: Array(fixture.requiredFiles.reversed()), validate: fixture.validate)
        assertEqual(first, fixture.folder, "initial validation returns the validated folder")
        assertEqual(second, fixture.folder, "unchanged files remain available for loading")
        assertEqual(fixture.validations, 1, "installed status then loading hashes once")
    }

    private static func replacementRequiresValidation() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        try fixture.restoreModificationDate {
            let replacement = fixture.folder.appendingPathComponent("replacement.bin")
            try fixture.weights.write(to: replacement)
            let result = rename(replacement.path, fixture.weightURL.path)
            assertEqual(result, 0, "replace model at the same path")
        }
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "valid replacement can be loaded after validation")
        assertEqual(fixture.validations, 2, "same-size replacement with restored mtime is hashed again")
    }

    private static func inPlaceCorruptionRequiresValidation() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        try fixture.restoreModificationDate {
            let handle = try FileHandle(forWritingTo: fixture.weightURL)
            defer { try? handle.close() }
            try handle.write(contentsOf: Data("wrong weights".utf8))
        }
        try expectFailure("same-size corruption with restored mtime must be rejected") {
            try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        }
        assertEqual(fixture.validations, 2, "in-place corruption is hashed again")
        try fixture.weights.write(to: fixture.weightURL)
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "repaired model is accepted after validation")
        assertEqual(fixture.validations, 3, "repair requires its own successful validation")
    }

    private static func missingFileRejectsReceipt() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        try FileManager.default.removeItem(at: fixture.weightURL)
        try expectFailure("deleted required files must be rejected") {
            try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        }
        try fixture.weights.write(to: fixture.weightURL)
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "restored file is accepted after validation")
        assertEqual(fixture.validations, 2, "missing metadata fails before hashing and restoration hashes again")
    }

    private static func changesDuringValidationRejectReceipt() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        try expectFailure("a model changed during hashing must be rejected") {
            try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles) { folder in
                try fixture.validate(folder)
                try Data("wrong weights".utf8).write(to: fixture.weightURL)
            }
        }
        try expectFailure("changed bytes must not receive a cached receipt") {
            try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        }
        assertEqual(fixture.validations, 2, "a race cannot cache the post-validation metadata")
        try fixture.weights.write(to: fixture.weightURL)
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "unchanged repair is accepted")
        assertEqual(fixture.validations, 3, "a rejected race requires fresh validation")
    }

    private static func failedValidationClearsReceipt() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        try expectFailure("a failed validator must not create a receipt") {
            try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles) { _ in
                throw FixtureError.integrityFailed
            }
        }
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "retry after failure validates successfully")
        assertEqual(fixture.validations, 1, "retry invokes the validator")
    }

    private static func invalidationRequiresValidation() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        cache.invalidate()
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        assertEqual(folder, fixture.folder, "explicit invalidation still permits revalidation")
        assertEqual(fixture.validations, 2, "removal invalidates the previous receipt")
    }

    private static func changedFolderRequiresValidation() throws {
        let first = try ModelFixture()
        let second = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: first.folder, requiredFiles: first.requiredFiles, validate: first.validate)
        let folder = try cache.validatedFolder(at: second.folder, requiredFiles: second.requiredFiles, validate: second.validate)
        assertEqual(folder, second.folder, "a changed folder returns only the newly validated location")
        assertEqual(first.validations, 1, "first folder is validated")
        assertEqual(second.validations, 1, "second folder requires separate validation")
    }

    private static func changedRequiredFilesRequireValidation() throws {
        let fixture = try ModelFixture()
        var cache = DictationModelValidationCache()
        _ = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles, validate: fixture.validate)
        let extra = fixture.folder.appendingPathComponent("metadata.json")
        try Data("metadata".utf8).write(to: extra)
        let folder = try cache.validatedFolder(at: fixture.folder, requiredFiles: fixture.requiredFiles + ["metadata.json"], validate: fixture.validate)
        assertEqual(folder, fixture.folder, "new required files belong to a new validation")
        assertEqual(fixture.validations, 2, "required-file set is part of the receipt")
    }
}
