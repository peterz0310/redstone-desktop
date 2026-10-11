import Foundation

/// Visual world time only: never ticks circuits, changes terrain or executes actions.
struct WorldLightingSettings: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Sendable { case day, cycle, night, fixed, systemTime }
    var mode: Mode = .day
    var cycleMinutes: Double = 20
    var startPhase: Double = 0.25 // Dawn = 0, noon = 0.25, dusk = 0.5.
    var anchorTime: Double = 0
    var localLights = true

    func validate() throws {
        guard cycleMinutes.isFinite, (2...1440).contains(cycleMinutes),
              startPhase.isFinite, (0...1).contains(startPhase), anchorTime.isFinite, abs(anchorTime) <= 1_000_000_000_000 else {
            throw WorldStoreError.invalidDocument("World lighting settings are invalid.")
        }
    }
    func phase(at time: Double, calendar: Calendar = .autoupdatingCurrent) -> Double {
        guard mode != .fixed, time.isFinite else { return startPhase }
        if mode == .systemTime {
            // Derive local wall time on each sample: no saved offset to drift after sleep,
            // reopening, a time-zone change or daylight-saving transition.
            guard abs(time) <= 1_000_000_000_000 else { return startPhase }
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: Date(timeIntervalSince1970: time))
            let seconds = Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0))
                + Double(parts.nanosecond ?? 0) / 1_000_000_000
            let phase = seconds / 86400 - 0.25 // Local 6 AM = dawn, noon = 0.25.
            return phase < 0 ? phase + 1 : phase
        }
        let elapsed = (time - anchorTime).truncatingRemainder(dividingBy: cycleMinutes * 60)
        let phase = (startPhase + elapsed / (cycleMinutes * 60)).truncatingRemainder(dividingBy: 1)
        return phase < 0 ? phase + 1 : phase
    }
    func daylight(at time: Double, calendar: Calendar = .autoupdatingCurrent) -> Double {
        switch mode {
        case .day: return 1
        case .night: return 0.22
        case .cycle, .fixed, .systemTime:
            let sun = sin(phase(at: time, calendar: calendar) * 2 * .pi)
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
