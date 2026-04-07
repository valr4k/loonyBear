import Foundation
import zlib

enum CompressionServiceError: LocalizedError {
    case compressionFailed
    case decompressionFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "The backup data could not be compressed."
        case .decompressionFailed:
            return "The backup data could not be decompressed."
        }
    }
}

final class CompressionService {
    func gzipCompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )

        guard initResult == Z_OK else {
            throw CompressionServiceError.compressionFailed
        }

        defer {
            deflateEnd(&stream)
        }

        let chunkSize = 16_384
        var compressed = Data()

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw CompressionServiceError.compressionFailed
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            var outputBuffer = [UInt8](repeating: 0, count: chunkSize)

            repeat {
                let result = try outputBuffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                    guard let outputBase = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                        throw CompressionServiceError.compressionFailed
                    }

                    stream.next_out = outputBase
                    stream.avail_out = uInt(chunkSize)
                    return deflate(&stream, Z_FINISH)
                }

                guard result == Z_OK || result == Z_STREAM_END else {
                    throw CompressionServiceError.compressionFailed
                }

                let bytesWritten = chunkSize - Int(stream.avail_out)
                compressed.append(outputBuffer, count: bytesWritten)

                if result == Z_STREAM_END {
                    break
                }
            } while stream.avail_out == 0
        }

        return compressed
    }

    func gzipDecompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        let initResult = inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )

        guard initResult == Z_OK else {
            throw CompressionServiceError.decompressionFailed
        }

        defer {
            inflateEnd(&stream)
        }

        let chunkSize = 16_384
        var decompressed = Data()

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else {
                throw CompressionServiceError.decompressionFailed
            }

            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(data.count)

            var outputBuffer = [UInt8](repeating: 0, count: chunkSize)

            while true {
                let result = try outputBuffer.withUnsafeMutableBytes { outputBytes -> Int32 in
                    guard let outputBase = outputBytes.bindMemory(to: Bytef.self).baseAddress else {
                        throw CompressionServiceError.decompressionFailed
                    }

                    stream.next_out = outputBase
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                guard result == Z_OK || result == Z_STREAM_END else {
                    throw CompressionServiceError.decompressionFailed
                }

                let bytesWritten = chunkSize - Int(stream.avail_out)
                decompressed.append(outputBuffer, count: bytesWritten)

                if result == Z_STREAM_END {
                    break
                }
            }
        }

        return decompressed
    }
}
