/// A signal strength constrained to 0...15, including when loaded from JSON.
struct PowerLevel: Equatable, Comparable, Codable, Sendable {
    let rawValue: UInt8

    static let off = PowerLevel(0)
    static let full = PowerLevel(15)

    init(_ value: Int) {
        rawValue = UInt8(min(15, max(0, value)))
    }

    static func < (lhs: PowerLevel, rhs: PowerLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(Int.self, forKey: .rawValue))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rawValue, forKey: .rawValue)
    }
}
