import Foundation

final class DictationPreviewAudioBuffer: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let samples: [Float]
        let totalSampleCount: Int
        let sourceOffset: Int
    }

    private struct Chunk {
        let samples: [Float]
        let offset: Int
    }

    static let maximumChunkCount = 1_024
    private let maximumSampleCount: Int
    private let lock = NSLock()
    private var chunks: [Chunk] = []
    private var totalSampleCount = 0

    init(sampleRate: Double) {
        maximumSampleCount = max(1, Int(ceil(sampleRate * 12)))
    }

    func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let retained = samples.count > maximumSampleCount ? Array(samples.suffix(maximumSampleCount)) : samples
        lock.lock()
        totalSampleCount += samples.count
        chunks.append(Chunk(samples: retained, offset: totalSampleCount - retained.count))
        let earliest = totalSampleCount - maximumSampleCount
        while chunks.count > Self.maximumChunkCount ||
            (chunks.first.map { $0.offset + $0.samples.count <= earliest } ?? false) {
            chunks.removeFirst()
        }
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        let capturedChunks = chunks
        let total = totalSampleCount
        lock.unlock()
        let offset = max(0, total - maximumSampleCount, capturedChunks.first?.offset ?? total)
        var samples: [Float] = []
        samples.reserveCapacity(total - offset)
        for chunk in capturedChunks {
            let start = max(0, offset - chunk.offset)
            if start < chunk.samples.count { samples.append(contentsOf: chunk.samples[start...]) }
        }
        return Snapshot(samples: samples, totalSampleCount: total, sourceOffset: offset)
    }

    var retainedChunkCount: Int { lock.withLock { chunks.count } }

    func discard() {
        lock.withLock {
            chunks.removeAll(keepingCapacity: false)
            totalSampleCount = 0
        }
    }
}
