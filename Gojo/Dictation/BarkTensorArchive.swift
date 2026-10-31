import Foundation
import zlib

struct BarkTensorArchive {
    struct Tensor {
        let shape: [Int]
        let values: [Float]
    }
    let tensors: [String: Tensor]

    init(url: URL) throws {
        let data = [UInt8](try Data(contentsOf: url))
        func integer(_ offset: Int, _ width: Int) throws -> Int {
            guard offset >= 0, offset + width <= data.count else { throw BarkRuntimeError.invalidWeights }
            return (0..<width).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 22,
              let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1)
                .first(where: { (try? integer($0, 4)) == 0x06054b50 }) else {
            throw BarkRuntimeError.invalidWeights
        }
        var position = try integer(end + 16, 4)
        var result: [String: Tensor] = [:]
        for _ in 0..<(try integer(end + 10, 2)) {
            guard try integer(position, 4) == 0x02014b50,
                  try integer(position + 10, 2) == 8 else { throw BarkRuntimeError.invalidWeights }
            let compressed = try integer(position + 20, 4)
            let size = try integer(position + 24, 4)
            let nameSize = try integer(position + 28, 2)
            let local = try integer(position + 42, 4)
            let payload = try local + 30 + integer(local + 26, 2) + integer(local + 28, 2)
            guard size <= 32_000_000, compressed <= data.count,
                  payload >= 0, payload + compressed <= data.count,
                  position + 46 + nameSize <= data.count else { throw BarkRuntimeError.invalidWeights }
            let name = String(decoding: data[(position + 46)..<(position + 46 + nameSize)], as: UTF8.self)
            var output = [UInt8](repeating: 0, count: size)
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw BarkRuntimeError.invalidWeights
            }
            let status = output.withUnsafeMutableBufferPointer { destination in
                data.withUnsafeBufferPointer { source in
                    stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress! + payload)
                    stream.avail_in = uInt(compressed)
                    stream.next_out = destination.baseAddress
                    stream.avail_out = uInt(size)
                    return inflate(&stream, Z_FINISH)
                }
            }
            let written = stream.total_out
            inflateEnd(&stream)
            guard status == Z_STREAM_END, written == size else { throw BarkRuntimeError.invalidWeights }
            result[String(name.dropLast(4))] = try Self.npy(output)
            position += try 46 + nameSize + integer(position + 30, 2) + integer(position + 32, 2)
        }
        tensors = result
    }

    private static func npy(_ bytes: [UInt8]) throws -> Tensor {
        guard bytes.count >= 10, Array(bytes[0..<6]) == [147, 78, 85, 77, 80, 89], bytes[6] == 1 else {
            throw BarkRuntimeError.invalidWeights
        }
        let headerSize = Int(bytes[8]) | Int(bytes[9]) << 8
        guard 10 + headerSize <= bytes.count else { throw BarkRuntimeError.invalidWeights }
        let header = String(decoding: bytes[10..<(10 + headerSize)], as: UTF8.self)
        guard header.contains("'fortran_order': False"),
              let start = header.range(of: "'shape': ("),
              let end = header[start.upperBound...].firstIndex(of: ")") else { throw BarkRuntimeError.invalidWeights }
        let shape = header[start.upperBound..<end].split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        let width: Int
        if header.contains("'<f2'") { width = 2 }
        else if header.contains("'<f4'") { width = 4 }
        else if header.contains("'|i1'") { width = 1 }
        else { throw BarkRuntimeError.invalidWeights }
        let count = shape.reduce(1, *)
        guard count > 0, count * width == bytes.count - 10 - headerSize else { throw BarkRuntimeError.invalidWeights }
        let values: [Float] = (0..<count).map { index in
            let offset = 10 + headerSize + index * width
            if width == 1 { return Float(Int8(bitPattern: bytes[offset])) }
            let low = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            if width == 2 { return Float(Float16(bitPattern: low)) }
            return Float(bitPattern: UInt32(low) | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24)
        }
        guard values.allSatisfy(\.isFinite) else { throw BarkRuntimeError.invalidWeights }
        return Tensor(shape: shape, values: values)
    }

    func weight(_ name: String) throws -> Tensor {
        if let tensor = tensors[name] { return tensor }
        guard let quantized = tensors[name + ".q"], let scales = tensors[name + ".s"],
              quantized.shape.count == 2, scales.values.count == quantized.shape[0] else {
            throw BarkRuntimeError.invalidWeights
        }
        let columns = quantized.shape[1]
        return Tensor(shape: quantized.shape, values: quantized.values.enumerated().map {
            $0.element * scales.values[$0.offset / columns]
        })
    }
}

enum BarkRuntimeError: LocalizedError {
    case invalidWeights
    case unsupportedSystem
    case invalidEncoderOutput

    var errorDescription: String? {
        switch self {
        case .invalidWeights: return "Bark model weights could not be read. Remove the model and download it again."
        case .unsupportedSystem: return "Underdog Bark 3.0 requires Apple silicon and macOS 15 or later."
        case .invalidEncoderOutput: return "Bark returned invalid audio features."
        }
    }
}
