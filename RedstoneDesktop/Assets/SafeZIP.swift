import Foundation
import zlib

/// Read-only bounded ZIP reader. Never writes archive paths or executes archive content.
/// Supports ordinary single-disk ZIP (stored/raw deflate), not encryption or ZIP64.
struct SafeZIP: Sendable {
    struct Entry: Sendable {
        let name: String
        let method: Int
        let flags: Int
        let crc: UInt32
        let compressed: Int
        let size: Int
        let offset: Int
    }
    let data: Data
    let entries: [String: Entry]
    private let centralOffset: Int

    init(url: URL) throws { try self.init(data: PackFiles.read(url, limit: 256 * 1024 * 1024)) }
    init(data: Data) throws {
        guard data.count >= 22, data.count <= 256 * 1024 * 1024 else { throw PackError("ZIP size is invalid.") }
        func number(_ offset: Int, _ bytes: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - bytes else { throw PackError("Truncated ZIP header.") }
            return (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try number(offset, 4) == 0x06054b50,
               try offset + 22 + number(offset + 20, 2) == data.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw PackError("ZIP end record missing or multi-disk archive.") }
        let count = try number(end + 10, 2), centralSize = try number(end + 12, 4), central = try number(end + 16, 4)
        guard count != 65535, centralSize != Int(UInt32.max), central != Int(UInt32.max),
              try number(end + 8, 2) == count, centralSize <= 32 * 1024 * 1024,
              central >= 0, central + centralSize == end else { throw PackError("ZIP64 or invalid central directory.") }
        var offset = central, result: [String: Entry] = [:], names: Set<String> = [], total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw PackError("Invalid central ZIP entry.") }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let compressed = try number(offset + 20, 4), size = try number(offset + 24, 4)
            let nameLength = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let local = try number(offset + 42, 4), attributes = try number(offset + 38, 4)
            let finish = offset + 46 + nameLength + extra + comment
            guard finish <= end, nameLength > 0, nameLength <= 1024,
                  flags & 0x2041 == 0, method == 0 || method == 8,
                  size <= 16 * 1024 * 1024, compressed <= 32 * 1024 * 1024,
                  local < central, try number(offset + 34, 2) == 0,
                  (attributes >> 16) & 0xf000 != 0xa000 else { throw PackError("Unsupported/encrypted/oversized/symlink ZIP entry.") }
            guard let name = String(data: data[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8) else { throw PackError("ZIP names must be UTF-8 or ASCII.") }
            let directory = name.hasSuffix("/")
            let path = directory ? String(name.dropLast()) : name
            try PackFiles.validatePath(path)
            guard names.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw PackError("Duplicate ZIP path.") }
            total += size
            guard total <= 512 * 1024 * 1024 else { throw PackError("ZIP expanded size exceeds limit.") }
            if !directory {
                result[name] = Entry(name: name, method: method, flags: flags, crc: UInt32(try number(offset + 16, 4)),
                    compressed: compressed, size: size, offset: local)
            }
            offset = finish
        }
        guard offset == end else { throw PackError("ZIP directory length mismatch.") }
        self.data = data; entries = result; centralOffset = central
    }

    func read(_ name: String, limit: Int) throws -> Data {
        guard let entry = entries[name], entry.size <= limit else { throw PackError("Missing or oversized ZIP asset: \(name)") }
        func number(_ offset: Int, _ bytes: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - bytes else { throw PackError("Truncated local ZIP header.") }
            return (0..<bytes).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        let offset = entry.offset
        guard try number(offset, 4) == 0x04034b50,
              try number(offset + 6, 2) == entry.flags, try number(offset + 8, 2) == entry.method else { throw PackError("ZIP local/central header mismatch.") }
        let nameLength = try number(offset + 26, 2), extra = try number(offset + 28, 2)
        let start = offset + 30 + nameLength + extra
        guard start <= centralOffset, start + entry.compressed <= centralOffset,
              let name = String(data: data[(offset + 30)..<(offset + 30 + nameLength)], encoding: .utf8), name == entry.name else { throw PackError("Invalid local ZIP name/data range.") }
        let input = Data(data[start..<(start + entry.compressed)])
        let output: Data
        if entry.method == 0 {
            guard input.count == entry.size else { throw PackError("Stored ZIP size mismatch.") }
            output = input
        } else {
            var bytes = [UInt8](repeating: 0, count: max(1, entry.size))
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw PackError("Deflate initialization failed.") }
            defer { inflateEnd(&stream) }
            let status = input.withUnsafeBytes { source in
                bytes.withUnsafeMutableBytes { destination in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(input.count)
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(destination.count)
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, stream.total_out == entry.size, stream.total_in == input.count else { throw PackError("Invalid deflate stream or declared size.") }
            output = Data(bytes.prefix(entry.size))
        }
        let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(output.count)) }
        guard UInt32(checksum) == entry.crc else { throw PackError("ZIP checksum mismatch.") }
        return output
    }
}
