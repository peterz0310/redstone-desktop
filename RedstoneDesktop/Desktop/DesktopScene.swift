import SpriteKit

/// Diagnostic world tiles and cursor outline, using CoordinateMapper exclusively.
final class DesktopScene: SKScene {
    private let terrainRenderer: TerrainChunkRenderer
    var terrainMetrics: TerrainRenderMetrics { terrainRenderer.metrics }
    private(set) var screen: ScreenDescriptor
    private(set) var mapper: CoordinateMapper
    private let highlight = SKShapeNode()
    private let clickFlash = SKShapeNode()
    private let tileLayer = SKNode()
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
    private(set) var highlightedTile: WorldCoordinate?

    init(screen: ScreenDescriptor, mapper: CoordinateMapper, terrainRenderer: TerrainChunkRenderer = TerrainChunkRenderer()) {
        self.terrainRenderer = terrainRenderer
        self.screen = screen
        self.mapper = mapper
        super.init(size: screen.frame.size)
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
        clickFlash.run(.sequence([.fadeOut(withDuration: 0.3), .hide()]))
    }

    func updateFinderMarkers(_ mappings: [FinderItemMapping]) {
        finderMarkers.removeAllChildren()
        // Finder icons provide their own presentation; retain no desktop crosshairs.
    }

    func updateOccupancy(_ snapshot: DesktopOccupancySnapshot) {
        renderedOccupancy = snapshot
        rebuildCircuit()
        occupancyLayer.removeAllChildren()
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
        case .grass: return NSColor(calibratedRed: 0.28, green: 0.5, blue: 0.35, alpha: 1)
        case .dirt: return .brown
        case .stone: return .gray
        case .sand: return NSColor(calibratedRed: 0.8, green: 0.72, blue: 0.45, alpha: 1)
        case .shallowWater: return .cyan
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
        flash.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
    }

    private func rebuildChecker() {
        removeAllChildren()
        addChild(tileLayer)
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
    }
}
