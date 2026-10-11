import SpriteKit

/// Presentation only: bounded persistent emitters built from visible terrain and power snapshots.
@MainActor final class WorldParticleRenderer {
    static let maximumEmitters = 64
    private struct Key: Hashable { let tile: WorldCoordinate; let texture: TextureAssetID }
    var assets: any AssetProvider = BuiltInAssetProvider()
    private var revision: UUID?
    private var textures: [TextureAssetID: SKTexture] = [:]
    private var emitters: [Key: SKEmitterNode] = [:]
    private var previousPositions: [Key: CGPoint] = [:]
    private(set) var emitterBuilds = 0
    var emitterCount: Int { emitters.count }

    func advance(into layer: SKNode, reducedMotion: Bool) {
        if reducedMotion && !layer.isHidden { for emitter in emitters.values { emitter.resetSimulation() } }
        layer.isHidden = reducedMotion; layer.isPaused = reducedMotion
    }
    func render(world: World, lava: Set<WorldCoordinate>, power: [WorldCoordinate: PowerLevel],
                mapper: CoordinateMapper, screen: ScreenDescriptor, into layer: SKNode, reducedMotion: Bool) {
        if revision != assets.revision {
            for emitter in emitters.values { emitter.removeFromParent() }
            emitters = [:]; textures = [:]; previousPositions = [:]; revision = assets.revision
        }
        let viewport = CGRect(origin: .zero, size: screen.frame.size)
        var requested: [(Key, Double)] = []
        for tile in world.circuit.components.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            guard mapper.sceneRect(forTile: tile, on: screen).intersects(viewport), let component = world.circuit.components[tile] else { continue }
            let level = Double(power[tile]?.rawValue ?? 0) / 15
            if component.kind == .lightTorch {
                requested.append((Key(tile: tile, texture: .particleFlame), 1))
                requested.append((Key(tile: tile, texture: .particleSmoke), 1))
            } else if (component.kind == .dust || component.kind == .torch) && level > 0 { requested.append((Key(tile: tile, texture: .particleDust), level)) }
            if requested.count >= Self.maximumEmitters { break }
        }
        // Spread lava effects over the pool instead of attaching one to every liquid tile.
        for tile in lava.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) where requested.count < Self.maximumEmitters {
            let hash = UInt64(bitPattern: Int64(tile.x)) &* 0x9e3779b97f4a7c15 ^ UInt64(bitPattern: Int64(tile.y)) &* 0xbf58476d1ce4e5b9
            guard hash % 4 == 0, mapper.sceneRect(forTile: tile, on: screen).intersects(viewport) else { continue }
            requested.append((Key(tile: tile, texture: .particleLava), 1))
        }
        requested = Array(requested.prefix(Self.maximumEmitters))
        let keys = Set(requested.map { $0.0 })
        for (key, emitter) in emitters where !keys.contains(key) { emitter.resetSimulation(); emitter.removeFromParent() }
        emitters = emitters.filter { keys.contains($0.key) }
        previousPositions = previousPositions.filter { keys.contains($0.key) }
        for (key, strength) in requested {
            let rect = mapper.sceneRect(forTile: key.tile, on: screen)
            let isNew = emitters[key] == nil
            let emitter: SKEmitterNode
            if let existing = emitters[key] { emitter = existing }
            else {
                emitter = SKEmitterNode()
                emitter.name = "particle:\(key.texture.rawValue):\(key.tile.x),\(key.tile.y)"
                if textures[key.texture] == nil { textures[key.texture] = assets.texture(for: key.texture) }
                emitter.particleTexture = textures[key.texture]
                emitter.targetNode = layer
                emitter.particleLifetime = key.texture == .particleSmoke ? 2.5 : 1.6
                emitter.particleLifetimeRange = 0.3
                emitter.particleAlpha = key.texture == .particleSmoke ? 0.45 : (key.texture == .particleDust ? 0.95 : 0.9)
                emitter.particleAlphaSpeed = -emitter.particleAlpha / emitter.particleLifetime
                emitter.particleScaleRange = 0.2
                emitter.particleScaleSpeed = key.texture == .particleSmoke ? 0.1 : -0.08
                emitter.emissionAngle = .pi / 2; emitter.emissionAngleRange = .pi / 5
                if key.texture == .particleDust {
                    emitter.particleColor = .red; emitter.particleColorBlendFactor = 1
                }
                emitters[key] = emitter; layer.addChild(emitter); emitterBuilds += 1
            }
            let position = CGPoint(x: rect.midX, y: rect.midY + (key.texture == .particleFlame || key.texture == .particleSmoke || world.circuit.components[key.tile]?.kind == .torch ? rect.height * 0.30 : 0))
            if previousPositions[key] != position { emitter.resetSimulation() }
            previousPositions[key] = position
            emitter.position = position
            emitter.particleSize = CGSize(width: rect.width * (key.texture == .particleDust ? 0.12 : 0.18), height: rect.height * (key.texture == .particleDust ? 0.12 : 0.18))
            emitter.particleSpeed = rect.width * (key.texture == .particleDust ? 0.04 : 0.10)
            emitter.particleSpeedRange = rect.width * 0.025
            emitter.yAcceleration = key.texture == .particleLava ? -rect.width * 0.12 : 0
            emitter.particlePositionRange = CGVector(dx: rect.width * (key.texture == .particleLava ? 0.5 : 0.15), dy: rect.height * 0.10)
            emitter.particleBirthRate = CGFloat((key.texture == .particleSmoke ? 0.7 : key.texture == .particleDust ? 2.4 : 1.8) * (key.texture == .particleDust ? max(0.35, strength) : strength))
            if isNew && !reducedMotion {
                // Short powered pulses must be visible before the next sparse birth interval.
                emitter.advanceSimulationTime(0.65)
            }
        }
        advance(into: layer, reducedMotion: reducedMotion)
    }
    static func originalImage(for id: TextureAssetID) -> NSImage {
        NSImage(size: CGSize(width: 8, height: 8), flipped: false) { _ in
            let color: NSColor = id == .particleSmoke ? .lightGray : id == .particleDust ? .white : .orange
            color.setFill(); NSBezierPath(rect: CGRect(x: 2, y: 2, width: 4, height: 4)).fill()
            if id == .particleFlame || id == .particleLava {
                NSColor.yellow.setFill(); NSBezierPath(rect: CGRect(x: 3, y: 3, width: 2, height: 3)).fill()
            }
            return true
        }
    }
}
