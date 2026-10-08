import Foundation

/// Constant-space callback cadence. Measures observed work, never creates a timer.
struct DiagnosticRateMeter: Equatable {
    private(set) var count = 0
    private var windowStart: TimeInterval?
    private var intervals = 0
    private(set) var lastEvent: TimeInterval?
    private var rate: Double?

    mutating func record(at time: TimeInterval) {
        guard time.isFinite else { return }
        if let lastEvent, time <= lastEvent { return }
        count += 1
        lastEvent = time
        guard let windowStart else { self.windowStart = time; return }
        intervals += 1
        let elapsed = time - windowStart
        if elapsed >= 1 {
            rate = Double(intervals) / elapsed
            self.windowStart = time
            intervals = 0
        }
    }

    func recentRate(at time: TimeInterval) -> Double? {
        guard let lastEvent, time.isFinite, time >= lastEvent, time - lastEvent <= 2 else { return nil }
        return rate
    }
}

struct DiagnosticOverlaySettings: Equatable {
    var tileCoordinates = false
    var rawFinderPoints = false
    var mappedFinderCenters = false
    var outputOccupancy = false
    var chunkBoundaries = false
    var enabled: Bool { tileCoordinates || rawFinderPoints || mappedFinderCenters || outputOccupancy || chunkBoundaries }
}

struct OutputActivationDiagnostic: Equatable {
    let worldID: UUID
    let areaID: UUID
    let tile: WorldCoordinate
    let power: PowerLevel
    let tick: Int
}
