import CryptoKit
import Darwin
import Foundation

enum RunMode: String, Codable {
    case baseline
    case candidate
}

struct Phase: Codable {
    let name: String
    let seconds: Double
    let hashedBytes: UInt64
    let hashedFiles: Int
}

struct Report: Codable {
    let mode: RunMode
    let modelRevision: String
    let phases: [Phase]
    let shaPasses: Int
    let hashedBytes: UInt64
    let errors: Int
    let candidateImplementation: String?
}

struct Options {
    let mode: RunMode
    let modelFolder: URL
    let output: URL

    init(arguments: [String]) throws {
        guard arguments.count.isMultiple(of: 2) else { throw RunError.arguments }
        var values: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            values[arguments[index]] = arguments[index + 1]
        }
        guard let mode = RunMode(rawValue: values["--mode"] ?? "baseline"),
              let modelFolder = values["--model-folder"],
              let output = values["--output"] else {
            throw RunError.arguments
        }
        self.mode = mode
        self.modelFolder = URL(fileURLWithPath: modelFolder)
        self.output = URL(fileURLWithPath: output)
    }
}

enum RunError: Error {
    case arguments
    case integrityFailed(String)
    case workCounts
}

func uptime() -> Double {
    ProcessInfo.processInfo.systemUptime
}

func validate(_ folder: URL) throws -> (bytes: UInt64, files: Int) {
    guard PinnedModelManifest.hashes.keys.allSatisfy({ relativePath in
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(relativePath).path)
    }) else { throw RunError.integrityFailed("required-file-presence") }
    var totalBytes: UInt64 = 0
    var files = 0
    for (relativePath, expectedHash) in PinnedModelManifest.hashes {
        let fileURL = folder.appendingPathComponent(relativePath)
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize else {
            throw RunError.integrityFailed(relativePath)
        }
        totalBytes += UInt64(fileSize)
        guard totalBytes <= PinnedModelManifest.maximumBytes,
              try sha256(of: fileURL) == expectedHash else {
            throw RunError.integrityFailed(relativePath)
        }
        files += 1
    }
    return (totalBytes, files)
}

func sha256(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func emitPhase(_ phase: Phase) {
    let data = try! JSONEncoder().encode(phase)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

@main
struct Main {
    static func main() {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            var phases: [Phase] = []
            var cache = DictationModelValidationCache()
            var shaPasses = 0
            for name in ["status-validation", "load-validation"] {
                let start = uptime()
                var work: (bytes: UInt64, files: Int) = (0, 0)
                switch options.mode {
                case .baseline:
                    work = try validate(options.modelFolder)
                case .candidate:
                    _ = try cache.validatedFolder(
                        at: options.modelFolder,
                        requiredFiles: Array(PinnedModelManifest.hashes.keys)
                    ) { folder in
                        work = try validate(folder)
                    }
                }
                if work.files > 0 { shaPasses += 1 }
                let phase = Phase(name: name, seconds: uptime() - start, hashedBytes: work.bytes, hashedFiles: work.files)
                phases.append(phase)
                emitPhase(phase)
            }
            let expectedPasses = options.mode == .baseline ? 2 : 1
            guard shaPasses == expectedPasses,
                  phases.reduce(0, { $0 + $1.hashedFiles }) == 14 * expectedPasses,
                  phases.reduce(UInt64(0), { $0 + $1.hashedBytes }) == UInt64(expectedPasses) * PinnedModelManifest.maximumBytes else {
                throw RunError.workCounts
            }
            let report = Report(
                mode: options.mode,
                modelRevision: PinnedModelManifest.revision,
                phases: phases,
                shaPasses: shaPasses,
                hashedBytes: phases.reduce(0) { $0 + $1.hashedBytes },
                errors: 0,
                candidateImplementation: options.mode == .candidate ? PinnedModelManifest.cacheSourceSHA256 : nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: options.output, options: .atomic)
            print("REPORT \(options.output.path)")
        } catch {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if let outputIndex = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputIndex + 1) {
                let failure: [String: Any] = [
                    "errors": 1,
                    "error": String(describing: error)
                ]
                if let data = try? JSONSerialization.data(withJSONObject: failure, options: [.prettyPrinted, .sortedKeys]) {
                    try? data.write(to: URL(fileURLWithPath: arguments[outputIndex + 1]), options: .atomic)
                }
            }
            FileHandle.standardError.write(Data("ERROR \(error)\n".utf8))
            exit(1)
        }
    }
}
