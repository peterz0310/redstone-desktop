import Foundation

enum SoundID: String, Codable, CaseIterable, Sendable {
    case buttonPress, buttonRelease, leverToggleOn, leverToggleOff, repeaterTick, torchToggle
    case placeCircuit, removeCircuit, invalidPlacement, outputActivate
}

struct AudioSettings: Equatable, Codable, Sendable {
    var volume: Double = 0.35
    var muted = false
    var effectsEnabled = true

    var gain: Float { muted || !effectsEnabled ? 0 : Float(volume.isFinite ? min(1, max(0, volume)) : 0) }
}

/// Original procedural tones, authored for this app; no game/resource-pack assets.
struct BuiltInSounds {
    static let sampleRate = 44_100.0
    static func samples(for id: SoundID) -> [Float] {
        let frequency: Double
        let duration: Double
        switch id {
        case .buttonPress: (frequency, duration) = (620, 0.06)
        case .buttonRelease: (frequency, duration) = (410, 0.045)
        case .leverToggleOn: (frequency, duration) = (790, 0.09)
        case .leverToggleOff: (frequency, duration) = (390, 0.09)
        case .torchToggle: (frequency, duration) = (950, 0.045)
        case .repeaterTick: (frequency, duration) = (1080, 0.035)
        case .placeCircuit: (frequency, duration) = (880, 0.065)
        case .removeCircuit: (frequency, duration) = (330, 0.075)
        case .invalidPlacement: (frequency, duration) = (165, 0.11)
        case .outputActivate: (frequency, duration) = (1320, 0.14)
        }
        let count = Int(duration * sampleRate)
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            let envelope = min(1, t / 0.004) * pow(max(0, 1 - Double(index) / Double(count - 1)), 2)
            let wave = sin(2 * .pi * frequency * t) + 0.2 * sin(2 * .pi * frequency * 2 * t)
            return Float(0.09 * envelope * wave)
        }
    }
}

/// Pure semantic transition extraction; simulation does not own audio playback.
struct CircuitSounds {
    static func transitions(before: CircuitSimulator, after: CircuitSimulator) -> [(SoundID, WorldCoordinate)] {
        before.world.components.keys.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.compactMap { tile in
            let wasOn = before.power(at: tile) > .off, isOn = after.power(at: tile) > .off
            switch before.world.components[tile]?.kind {
            case .button where wasOn && !isOn: return (.buttonRelease, tile)
            case .torch where wasOn != isOn: return (.torchToggle, tile)
            case .repeater where wasOn != isOn: return (.repeaterTick, tile)
            default: return nil
            }
        }
    }
}
