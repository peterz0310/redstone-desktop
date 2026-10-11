import SpriteKit
import Combine

/// Diagnostic world tiles and cursor outline, using CoordinateMapper exclusively.
final class DesktopScene: SKScene {
    private(set) var frameRate = DiagnosticRateMeter()
    private var diagnosticOverlays = DiagnosticOverlaySettings()
    private let diagnosticLayer = SKNode()
    private var diagnosticMappings: [FinderItemMapping] = []
    private let terrainRenderer: TerrainChunkRenderer
    var terrainMetrics: TerrainRenderMetrics { terrainRenderer.metrics }
    private(set) var screen: ScreenDescriptor
    private(set) var mapper: CoordinateMapper
    private let highlight = SKShapeNode()
    private let clickFlash = SKShapeNode()
    private let tileLayer = SKNode()
    private let particleLayer = SKNode()
    private let particleRenderer = WorldParticleRenderer()
    var particleEmitterCount: Int { particleRenderer.emitterCount }
    private let lightingLayer = SKNode()
    private let lightingRenderer = WorldLightingRenderer()
    var lightingTextureBuilds: Int { lightingRenderer.textureBuilds }
    var lightingTimeProviding: () -> Double = { Date().timeIntervalSince1970 }
    private let circuitLayer = SKNode()
    private let outputFlash = SKNode()
    private let circuitRenderer = CircuitRenderer()
    private var renderedOccupancy: DesktopOccupancySnapshot = .unavailable("Read Finder Items.")
    private let occupancyLayer = SKNode()
    private let finderMarkers = SKNode()
    private var renderedWorld: World?
    private var renderedPower: Set<WorldCoordinate> = []
    private var renderedPowerLevels: [WorldCoordinate: PowerLevel]?
    private var renderedLevers: Set<WorldCoordinate>?
    private var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var motionObserver: AnyCancellable?
    var reduceMotionProviding: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private(set) var feedbackUsesReducedMotion = false
    private(set) var highlightedTile: WorldCoordinate?

    init(screen: ScreenDescriptor, mapper: CoordinateMapper, terrainRenderer: TerrainChunkRenderer = TerrainChunkRenderer()) {
        self.terrainRenderer = terrainRenderer
        self.screen = screen
        self.mapper = mapper
        super.init(size: screen.frame.size)
        motionObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
            }
        scaleMode = .resizeFill
        backgroundColor = .black
        highlight.name = "cursor-highlight"
        highlight.strokeColor = .white.withAlphaComponent(0.75)
        highlight.fillColor = .white.withAlphaComponent(0.08)
        highlight.lineWidth = 2
        highlight.zPosition = 1
        highlight.isHidden = true
        clickFlash.name = "click-flash"
        clickFlash.fillColor = NSColor.systemOrange.withAlphaComponent(0.55)
        clickFlash.strokeColor = .systemOrange
        clickFlash.zPosition = 2
        clickFlash.isHidden = true
        particleLayer.name = "world-particles"; particleLayer.zPosition = 0.85
        lightingLayer.name = "world-lighting"; lightingLayer.zPosition = 0.9
        tileLayer.name = "world-tiles"
        tileLayer.zPosition = 0.25
        circuitLayer.name = "circuit"
        circuitLayer.zPosition = 0.75
        outputFlash.name = "output-flash"
        outputFlash.zPosition = 4
        occupancyLayer.name = "desktop-occupancy"
        occupancyLayer.zPosition = 0.5
        finderMarkers.name = "finder-markers"
        finderMarkers.zPosition = 3
        rebuildChecker()
    }

    required init?(coder: NSCoder) {
        fatalError("DesktopScene is created programmatically")
    }

    override func update(_ currentTime: TimeInterval) {
        // Sample real scene callbacks without publishing to SwiftUI each frame.
        frameRate.record(at: ProcessInfo.processInfo.systemUptime)
        terrainRenderer.advanceAnimation(at: currentTime, reducedMotion: reducedMotion)
        particleRenderer.advance(into: particleLayer, reducedMotion: reducedMotion)
        lightingRenderer.advance(settings: renderedWorld?.lighting ?? WorldLightingSettings(), time: lightingTimeProviding())
    }

    func setDiagnosticOverlays(_ settings: DiagnosticOverlaySettings) {
        guard diagnosticOverlays != settings else { return }
        diagnosticOverlays = settings
        rebuildDiagnostics()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildChecker()
        if let world = renderedWorld { updateWorld(world, poweredTiles: renderedPower, leverPositions: renderedLevers, powerLevels: renderedPowerLevels) }
    }

    /// Editor navigation keeps scene, texture and renderer ownership stable.
    func updateViewport(screen: ScreenDescriptor, mapper: CoordinateMapper) {
        self.screen = screen
        self.mapper = mapper
        if size != screen.frame.size { size = screen.frame.size }
        else {
            rebuildChecker()
            if let world = renderedWorld { updateWorld(world, poweredTiles: renderedPower, leverPositions: renderedLevers, powerLevels: renderedPowerLevels) }
        }
        highlightedTile = nil
        highlight.isHidden = true
    }

    private var assetProvider: (any AssetProvider)?
    private var assetRevision: UUID?
    func setAssets(_ assets: any AssetProvider) {
        guard assetRevision != assets.revision else { return }
        assetRevision = assets.revision
        assetProvider = assets
        terrainRenderer.assets = assets
        circuitRenderer.textures.assets = assets
        particleRenderer.assets = assets
        if let world = renderedWorld { updateWorld(world, poweredTiles: renderedPower, leverPositions: renderedLevers, powerLevels: renderedPowerLevels) }
    }

    func updateHighlight(_ coordinate: WorldCoordinate?) {
        guard coordinate != highlightedTile else { return }
        highlightedTile = coordinate
        highlight.isHidden = coordinate == nil
        if let coordinate {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 1, dy: 1)
            highlight.path = CGPath(rect: rect, transform: nil)
        }
    }

    func flashTile(_ coordinate: WorldCoordinate) {
        clickFlash.removeAllActions()
        clickFlash.path = CGPath(rect: mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 1, dy: 1), transform: nil)
        clickFlash.alpha = 1
        clickFlash.isHidden = false
        feedbackUsesReducedMotion = reduceMotionProviding()
        clickFlash.run(.sequence([feedbackUsesReducedMotion ? .wait(forDuration: 0.2) : .fadeOut(withDuration: 0.3), .hide()]))
    }

    func updateFinderMarkers(_ mappings: [FinderItemMapping]) {
        finderMarkers.removeAllChildren()
        // Ordinary Finder presentation stays clear; diagnostic markers require explicit opt-in.
        if diagnosticMappings != mappings { diagnosticMappings = mappings; rebuildDiagnostics() }
    }

    func updateOccupancy(_ snapshot: DesktopOccupancySnapshot) {
        renderedOccupancy = snapshot
        rebuildCircuit()
        occupancyLayer.removeAllChildren()
        rebuildDiagnostics()
    }

    func updateWorld(_ world: World, poweredTiles: Set<WorldCoordinate> = [], leverPositions: Set<WorldCoordinate>? = nil,
                     powerLevels: [WorldCoordinate: PowerLevel]? = nil) {
        renderedWorld = world
        renderedPower = poweredTiles
        renderedPowerLevels = powerLevels
        renderedLevers = leverPositions
        if world.generation == nil { tileLayer.removeAllChildren() }
        circuitLayer.removeAllChildren()
        let viewport = CGRect(origin: .zero, size: size)
        if world.generation != nil {
            terrainRenderer.render(world, mapper: mapper, screen: screen, viewport: viewport, into: tileLayer)
        }
        for (coordinate, tile) in (world.generation == nil ? world.tiles : [:]).sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen)
            guard rect.intersects(viewport) else { continue }
            let node = SKShapeNode(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            node.name = "tile:\(coordinate.x),\(coordinate.y)"
            node.fillColor = .white
            node.fillTexture = assetProvider?.texture(for: .terrain(tile.terrain))
            if node.fillTexture == nil { node.fillColor = terrainColor(tile.terrain) }
            node.strokeColor = .clear
            tileLayer.addChild(node)
            if let decoration = tile.decoration {
                let appearance = DecorationAppearance.choose(decoration, at: coordinate, seed: world.generation?.seed ?? 0, terrain: tile.terrain)
                let label = SKLabelNode(text: appearance.name)
                label.fontName = "Menlo"
                label.fontSize = 9
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: rect.midX, y: rect.midY)
                tileLayer.addChild(label)
            }
        }
        rebuildCircuit()
        let lava = world.generation == nil ? Set(world.tiles.filter { $0.value.terrain == .lava }.keys) : terrainRenderer.lavaTiles
        particleRenderer.render(world: world, lava: lava, power: powerLevels ?? Dictionary(uniqueKeysWithValues: poweredTiles.map { ($0, PowerLevel.full) }),
            mapper: mapper, screen: screen, into: particleLayer, reducedMotion: reducedMotion)
        lightingRenderer.render(world: world, lava: lava,
            power: powerLevels ?? Dictionary(uniqueKeysWithValues: poweredTiles.map { ($0, PowerLevel.full) }),
            mapper: mapper, screen: screen, into: lightingLayer, time: lightingTimeProviding())
        rebuildDiagnostics()
        // Cancel effects for outputs removed from the model; power refreshes keep them.
        for node in outputFlash.children {
            guard let name = node.name,
                  world.circuit.components.contains(where: { coordinate, component in
                      component.kind == .output && name == "output-flash:\(coordinate.x),\(coordinate.y)"
                  }) else { node.removeAllActions(); node.removeFromParent(); continue }
        }
    }

    private func rebuildCircuit() {
        guard let world = renderedWorld else { return }
        circuitRenderer.render(world.circuit, poweredTiles: renderedPower, occupancy: renderedOccupancy,
            mapper: mapper, screen: screen, viewport: CGRect(origin: .zero, size: size), into: circuitLayer, leverPositions: renderedLevers, powerLevels: renderedPowerLevels)
    }

    private func terrainColor(_ terrain: TerrainID) -> NSColor {
        switch terrain {
        case .dryGrass: return NSColor(red: 0.68, green: 0.63, blue: 0.29, alpha: 1)
        case .snow: return NSColor(red: 0.89, green: 0.93, blue: 0.95, alpha: 1)
        case .gravel: return NSColor(red: 0.47, green: 0.48, blue: 0.47, alpha: 1)
        case .grass: return NSColor(calibratedRed: 0.28, green: 0.5, blue: 0.35, alpha: 1)
        case .dirt: return .brown
        case .stone: return .gray
        case .sand: return NSColor(calibratedRed: 0.8, green: 0.72, blue: 0.45, alpha: 1)
        case .shallowWater: return .cyan
        case .lava: return .systemOrange
        case .deepWater: return .blue
        }
    }

    func flashOutput(at coordinate: WorldCoordinate) {
        guard renderedWorld?.circuit.components[coordinate]?.kind == .output else { return }
        let name = "output-flash:\(coordinate.x),\(coordinate.y)"
        let flash = (outputFlash.childNode(withName: name) as? SKShapeNode) ?? SKShapeNode()
        flash.name = name
        flash.removeAllActions()
        flash.path = CGPath(rect: mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 3, dy: 3), transform: nil)
        flash.strokeColor = .white
        flash.fillColor = NSColor.white.withAlphaComponent(0.5)
        flash.lineWidth = 4
        flash.alpha = 1
        if flash.parent == nil { outputFlash.addChild(flash) }
        feedbackUsesReducedMotion = reduceMotionProviding()
        flash.run(.sequence([feedbackUsesReducedMotion ? .wait(forDuration: 0.2) : .fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func rebuildChecker() {
        removeAllChildren()
        addChild(tileLayer)
        addChild(lightingLayer)
        addChild(particleLayer)
        addChild(circuitLayer)
        addChild(outputFlash)
        addChild(occupancyLayer)
        addChild(highlight)
        addChild(clickFlash)
        addChild(finderMarkers)
        guard size.width > 0, size.height > 0,
              let first = mapper.tile(atScreen: screen.frame.origin),
              let last = mapper.tile(atScreen: CGPoint(x: screen.frame.minX + size.width, y: screen.frame.minY + size.height)) else { return }
        let paths = [CGMutablePath(), CGMutablePath()]

        for y in first.y...last.y {
            for x in first.x...last.x {
                let parity = ((x % 2) + (y % 2) + 2) % 2
                paths[parity].addRect(mapper.sceneRect(forTile: WorldCoordinate(x: x, y: y), on: screen))
            }
        }
        let colors: [NSColor] = [
            NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.38, alpha: 1),
            NSColor(calibratedRed: 0.36, green: 0.59, blue: 0.55, alpha: 1)
        ]
        for index in 0..<2 {
            let node = SKShapeNode(path: paths[index])
            node.fillColor = colors[index]
            node.strokeColor = .clear
            node.isAntialiased = false
            addChild(node)
        }
        rebuildDiagnostics()
    }

    /// Geometry stays bounded and every world/screen conversion uses the mapper.
    private func rebuildDiagnostics() {
        diagnosticLayer.removeAllChildren()
        guard diagnosticOverlays.enabled else { diagnosticLayer.removeFromParent(); return }
        diagnosticLayer.name = "diagnostic-overlays"; diagnosticLayer.zPosition = 8
        if diagnosticLayer.parent == nil { addChild(diagnosticLayer) }
        let viewport = CGRect(origin: .zero, size: size)
        func label(_ text: String, at point: CGPoint, color: NSColor = .white) {
            let node = SKLabelNode(text: text)
            node.fontName = "Menlo"; node.fontSize = 9; node.fontColor = color
            node.position = point; diagnosticLayer.addChild(node)
        }
        if diagnosticOverlays.tileCoordinates,
           let first = mapper.tile(atScreen: screen.frame.origin),
           let last = mapper.tile(atScreen: CGPoint(x: screen.frame.minX + size.width, y: screen.frame.minY + size.height)) {
            var count = 0
            tiles: for y in first.y...last.y { for x in first.x...last.x {
                if count == 128 { break tiles }
                let rect = mapper.sceneRect(forTile: WorldCoordinate(x: x, y: y), on: screen)
                if rect.intersects(viewport) { label("\(x),\(y)", at: CGPoint(x: rect.midX, y: rect.midY)); count += 1 }
            } }
        }
        if diagnosticOverlays.chunkBoundaries {
            for chunk in mapper.visibleChunks(on: screen, viewport: viewport).sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }).prefix(64) {
                guard let rect = mapper.sceneRect(forChunk: chunk, on: screen), rect.intersects(viewport) else { continue }
                let node = SKShapeNode(rect: rect)
                node.strokeColor = .systemYellow; node.fillColor = .clear; node.lineWidth = 2
                diagnosticLayer.addChild(node)
            }
        }
        if diagnosticOverlays.rawFinderPoints || diagnosticOverlays.mappedFinderCenters {
            for mapping in diagnosticMappings.filter({ screen.contains($0.screenCenter) }).prefix(256) {
                let point = mapper.scenePoint(fromScreen: mapping.screenCenter, on: screen)
                if diagnosticOverlays.rawFinderPoints {
                    let node = SKShapeNode(rectOf: CGSize(width: 5, height: 5))
                    node.name = "diagnostic-raw:\(mapping.id)"
                    node.fillColor = .systemPink; node.strokeColor = .clear; node.position = point
                    diagnosticLayer.addChild(node)
                    label("raw \(mapping.item.position.x),\(mapping.item.position.y)", at: CGPoint(x: point.x, y: point.y + 14), color: .systemPink)
                }
                if diagnosticOverlays.mappedFinderCenters {
                    let node = SKShapeNode(circleOfRadius: 9)
                    node.name = "diagnostic-center:\(mapping.id)"
                    node.strokeColor = .systemCyan; node.fillColor = .clear; node.position = point
                    diagnosticLayer.addChild(node)
                }
            }
        }
        if diagnosticOverlays.outputOccupancy, let world = renderedWorld {
            for tile in world.circuit.components.keys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) })
                .filter({ world.circuit.components[$0]?.kind == .output && mapper.sceneRect(forTile: $0, on: screen).intersects(viewport) }).prefix(256) {
                let rect = mapper.sceneRect(forTile: tile, on: screen)
                let text: String
                switch renderedOccupancy.state(at: tile) {
                case .empty: text = "EMPTY"
                case .occupied: text = "1 ITEM"
                case let .ambiguous(items): text = "\(items.count) ITEMS"
                case .unavailable: text = "UNAVAILABLE"
                }
                label(text, at: CGPoint(x: rect.midX, y: rect.midY))
            }
        }
    }
}
