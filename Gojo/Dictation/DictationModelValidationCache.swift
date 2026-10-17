import Darwin
import Foundation

struct DictationModelValidationCache {
    private struct FileFingerprint: Equatable {
        let device: dev_t
        let inode: ino_t
        let mode: mode_t
        let size: off_t
        let modifiedSeconds: time_t
        let modifiedNanoseconds: Int
        let changedSeconds: time_t
        let changedNanoseconds: Int

        init(at url: URL) throws {
            var info = stat()
            let result = url.withUnsafeFileSystemRepresentation { path in
                path.map { Darwin.fstatat(AT_FDCWD, $0, &info, 0) } ?? -1
            }
            guard result == 0, info.st_mode & S_IFMT == S_IFREG else {
                throw CocoaError(.fileReadCorruptFile)
            }
            device = info.st_dev
            inode = info.st_ino
            mode = info.st_mode
            size = info.st_size
            modifiedSeconds = info.st_mtimespec.tv_sec
            modifiedNanoseconds = info.st_mtimespec.tv_nsec
            changedSeconds = info.st_ctimespec.tv_sec
            changedNanoseconds = info.st_ctimespec.tv_nsec
        }
    }

    private struct Receipt: Equatable {
        let folder: URL
        let requiredFiles: [String]
        let fingerprints: [FileFingerprint]

        init(folder: URL, requiredFiles: [String]) throws {
            self.folder = folder.standardizedFileURL
            self.requiredFiles = requiredFiles.sorted()
            fingerprints = try self.requiredFiles.map {
                try FileFingerprint(at: folder.appendingPathComponent($0))
            }
        }
    }

    private var receipt: Receipt?

    mutating func validatedFolder(
        at folder: URL,
        requiredFiles: [String],
        validate: (URL) throws -> Void
    ) throws -> URL {
        do {
            let current = try Receipt(folder: folder, requiredFiles: requiredFiles)
            if current == receipt { return current.folder }
            receipt = nil
            try validate(current.folder)
            guard try current == Receipt(folder: folder, requiredFiles: requiredFiles) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            receipt = current
            return current.folder
        } catch {
            receipt = nil
            throw error
        }
    }

    mutating func invalidate() {
        receipt = nil
    }
}
