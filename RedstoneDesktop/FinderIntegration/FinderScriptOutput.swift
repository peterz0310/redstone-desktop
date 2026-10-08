import Foundation

/// Parses osascript's quoted data representation, never evaluating returned text as code.
/// Supports only the lists, strings, finite numbers and missing values in our fixed query.
enum FinderScriptOutput {
    private indirect enum Value {
        case list([Value]), string(String), number(Double), missing
        var descriptor: NSAppleEventDescriptor {
            switch self {
            case let .list(values):
                let result = NSAppleEventDescriptor.list()
                for (index, value) in values.enumerated() { result.insert(value.descriptor, at: index + 1) }
                return result
            case let .string(value): return NSAppleEventDescriptor(string: value)
            case let .number(value): return NSAppleEventDescriptor(double: value)
            case .missing: return .null()
            }
        }
    }

    static func descriptor(from data: Data) throws -> NSAppleEventDescriptor {
        guard data.count <= 4 * 1024 * 1024, String(data: data, encoding: .utf8) != nil else { throw malformed() }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw malformed() }
        return value.descriptor
    }

    private static func malformed() -> FinderReadError { .malformedResponse("Invalid structured Finder query output.") }
    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var values = 0
        mutating func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }
        mutating func consume(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1; return true
        }
        mutating func value(depth: Int) throws -> Value {
            values += 1
            guard depth < 8, values <= 60_000 else { throw malformed() }
            whitespace()
            if consume(123) { // {
                var items: [Value] = []
                if consume(125) { return .list(items) }
                repeat { items.append(try value(depth: depth + 1)) } while consume(44)
                guard consume(125) else { throw malformed() }
                return .list(items)
            }
            if consume(34) { // quoted string, including literal Unicode/control characters
                var string: [UInt8] = []
                while index < bytes.count {
                    var byte = bytes[index]; index += 1
                    if byte == 34 {
                        guard let result = String(bytes: string, encoding: .utf8) else { throw malformed() }
                        return .string(result)
                    }
                    if byte == 92 {
                        guard index < bytes.count else { throw malformed() }
                        byte = bytes[index]; index += 1
                        switch byte {
                        case 34, 92: break
                        case 110: byte = 10
                        case 114: byte = 13
                        case 116: byte = 9
                        default: throw malformed()
                        }
                    }
                    string.append(byte)
                }
                throw malformed()
            }
            let missing = Array("missing value".utf8)
            if bytes[index...].starts(with: missing) { index += missing.count; return .missing }
            let start = index
            while index < bytes.count, (48...57).contains(bytes[index]) || [43, 45, 46, 69, 101].contains(bytes[index]) { index += 1 }
            guard index > start, let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)), number.isFinite else { throw malformed() }
            return .number(number)
        }
    }
}
