import Foundation
import Darwin

/// Check the opened descriptor, then cap every read even if the file grows afterwards.
enum BoundedFileReader {
    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        // Nonblocking open lets us refuse pipes instead of hanging startup on an invalid save.
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            if code == ENOENT { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard info.st_mode & S_IFMT == S_IFREG else {
            throw WorldStoreError.invalidDocument("This save must be a regular file.")
        }
        guard info.st_size <= maximumBytes else { throw oversized(maximumBytes) }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw oversized(maximumBytes)
    }

    private static func oversized(_ limit: Int) -> WorldStoreError {
        .invalidDocument("This file exceeds the allowed size (\(limit) bytes). The file has been preserved.")
    }
}
