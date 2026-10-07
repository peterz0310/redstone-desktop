/// One redstone tick is two simulation ticks (100 ms at 20 Hz).
/// Invalid persisted values are rejected by the raw-value Codable implementation.
enum RepeaterDelay: Int, CaseIterable, Codable, Sendable {
    case one = 1, two, three, four
    var simulationTicks: Int { rawValue * 2 }
}
