import AppKit
import SpriteKit

/// Native renderer examples using only original assets. No app state, Finder, files or actions.
@main struct ReadmePreviews {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let assets = BuiltInAssetProvider()
        func render(_ world: World, origin: WorldPoint, tileSize: Double = 24,
                    simulator: CircuitSimulator? = nil) throws -> NSImage {
            let size = CGSize(width: 768, height: 432)
            let screen = ScreenDescriptor(id: "readme-example", frame: CGRect(origin: .zero, size: size), backingScale: 1)
            let mapper = try CoordinateMapper(canvasFrame: screen.frame,
                camera: CameraState(worldOrigin: origin, pointsPerTile: tileSize))
            let scene = DesktopScene(screen: screen, mapper: mapper)
            scene.setAssets(assets)
            scene.lightingTimeProviding = { 0 }
            scene.setVisualSettings(VisualSettings(liquidAnimations: false, sceneryAnimations: false, particles: false))
            let view = SKView(frame: screen.frame)
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view // Offscreen only; never order a window or request desktop permissions.
            view.presentScene(scene)
            scene.updateWorld(world, poweredTiles: simulator?.poweredTiles ?? [],
                              leverPositions: simulator?.activeLevers, powerLevels: simulator?.power)
            guard let texture = view.texture(from: scene) else { throw NSError(domain: "Preview", code: 1) }
            return NSImage(cgImage: texture.cgImage(), size: size)
        }
        func write(_ image: NSImage, name: String) throws {
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        func pair(_ left: NSImage, _ right: NSImage, titles: [String], name: String) throws {
            let image = NSImage(size: CGSize(width: 1536, height: 480))
            image.lockFocus()
            NSColor(white: 0.08, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1536, height: 480).fill()
            for (index, example) in [left, right].enumerated() {
                example.draw(in: NSRect(x: index * 768, y: 0, width: 768, height: 432))
                (titles[index] as NSString).draw(at: NSPoint(x: index * 768 + 20, y: 446), withAttributes:
                    [.font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: NSColor.white])
            }
            image.unlockFocus(); try write(image, name: name)
        }
        let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: 42))
        // Find a naturally generated river/woodland view and snowy view deterministically.
        var river = WorldPoint(x: 0, y: 0), snow = river, riverScore = -1, snowScore = -1
        for cy in stride(from: -512, through: 512, by: 32) {
            for cx in stride(from: -512, through: 512, by: 32) {
                var water = 0, trees = 0, snowy = 0, pines = 0
                for y in stride(from: cy, to: cy + 27, by: 2) {
                    for x in stride(from: cx, to: cx + 48, by: 2) {
                        let tile = generator.tile(at: WorldCoordinate(x: x, y: y))
                        if [TerrainID.shallowWater, .deepWater].contains(tile.terrain) { water += 1 }
                        if [.tree, .treeLeaves].contains(tile.decoration) { trees += 1 }
                        if tile.terrain == .snow { snowy += 1 }
                        if [.pine, .pineLeaves].contains(tile.decoration) { pines += 1 }
                    }
                }
                let score = (20...90).contains(water) ? trees * 3 + min(water, 50) : 0
                if score > riverScore { riverScore = score; river = WorldPoint(x: Double(cx), y: Double(cy)) }
                let snowyScore = snowy > 100 && pines > 10 ? pines * 3 + min(snowy, 180) : 0
                if snowyScore > snowScore { snowScore = snowyScore; snow = WorldPoint(x: Double(cx), y: Double(cy)) }
            }
        }
        let landscape = World(generation: WorldGenerationSettings(seed: 42))
        try pair(render(landscape, origin: river, tileSize: 16), render(landscape, origin: snow, tileSize: 16),
            titles: ["Rivers & woodland", "Snowy forests"], name: "worlds.png")
        var build = World(generation: WorldGenerationSettings(seed: 2026))
        for y in 0..<18 { for x in 0..<32 { build.tiles[WorldCoordinate(x: x, y: y)] = Tile(terrain: .grass) } }
        for x in 4...14 {
            let kind: CircuitComponentKind = x == 4 ? .lever : x == 10 ? .repeater : x == 14 ? .lamp : .dust
            build.circuit.components[WorldCoordinate(x: x, y: 8)] = CircuitComponent(kind: kind, direction: .east)
        }
        for point in [WorldCoordinate(x: 5, y: 4), WorldCoordinate(x: 21, y: 12)] {
            build.circuit.components[point] = CircuitComponent(kind: .lightTorch)
        }
        for y in 3...5 { for x in 23...25 { build.tiles[WorldCoordinate(x: x, y: y)] = Tile(terrain: .lava) } }
        for point in [WorldCoordinate(x: 2, y: 13), WorldCoordinate(x: 2, y: 14), WorldCoordinate(x: 3, y: 14), WorldCoordinate(x: 4, y: 14), WorldCoordinate(x: 3, y: 13)] {
            build.tiles[point] = Tile(terrain: .grass, decoration: point == WorldCoordinate(x: 3, y: 14) ? .tree : .treeLeaves)
        }
        var simulator = CircuitSimulator(world: build.circuit)
        _ = simulator.toggleLever(at: WorldCoordinate(x: 4, y: 8))
        for _ in 0..<8 { _ = simulator.advanceTick() }
        guard (simulator.power[WorldCoordinate(x: 14, y: 8)] ?? .off) > .off else { throw NSError(domain: "Preview unpowered lamp", code: 2) }
        let day = try render(build, origin: WorldPoint(x: 0, y: 0), simulator: simulator)
        build.lighting = WorldLightingSettings(mode: .night)
        try pair(day, render(build, origin: WorldPoint(x: 0, y: 0), simulator: simulator),
            titles: ["Build by day", "Redstone, lamps, torches & lava at night"], name: "lighting.png")
        print("README previews: native SpriteKit, original art, synthetic circuit, no Finder/actions/imports.")
    }
}
