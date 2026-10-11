import Foundation

/// Visual world time only: never ticks circuits, changes terrain or executes actions.
struct WorldLightingSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case day, cycle, night }
    var mode: Mode = .day
    var cycleMinutes: Double = 20
    var startPhase: Double = 0.25 // Dawn = 0, noon = 0.25, dusk = 0.5.
    var anchorTime: Double = 0
    var localLights = true

    func validate() throws {
        guard cycleMinutes.isFinite, (2...120).contains(cycleMinutes),
              startPhase.isFinite, (0...1).contains(startPhase), anchorTime.isFinite, abs(anchorTime) <= 1_000_000_000_000 else {
            throw WorldStoreError.invalidDocument("World lighting settings are invalid.")
        }
    }
    func phase(at time: Double) -> Double {
        guard time.isFinite else { return startPhase }
        let elapsed = (time - anchorTime).truncatingRemainder(dividingBy: cycleMinutes * 60)
        let phase = (startPhase + elapsed / (cycleMinutes * 60)).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }
    func daylight(at time: Double) -> Double {
        switch mode {
        case .day: return 1
        case .night: return 0.22
        case .cycle:
            let sun = sin(phase(at: time) * 2 * .pi)
            let brightness = min(1, max(0, (sun + 0.2) / 0.7))
            return 0.22 + 0.78 * brightness
        }
    }
}

/// Smooth radial illumination with a bounded footprint, independent of SpriteKit.
enum WorldLightFalloff {
    static func intensity(dx: Int, dy: Int, radius: Int, strength: Double) -> Double {
        guard (1...16).contains(radius), strength.isFinite, (-radius...radius).contains(dx), (-radius...radius).contains(dy) else { return 0 }
        let distance = sqrt(Double(dx * dx + dy * dy))
        let t = max(0, 1 - distance / Double(radius))
        return min(1, max(0, strength)) * t * t * (3 - 2 * t)
    }
}
