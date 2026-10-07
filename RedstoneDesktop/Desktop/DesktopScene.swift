import SpriteKit

/// Diagnostic world tiles and cursor outline, using CoordinateMapper exclusively.
final class DesktopScene: SKScene {
    let screen: ScreenDescriptor
    let mapper: CoordinateMapper
    private let highlight = SKShapeNode()
    private let clickFlash = SKShapeNode()
    private let tileLayer = SKNode()
    private let circuitLayer = SKNode()
    private let outputFlash = SKShapeNode()
    private let occupancyLayer = SKNode()
    private let finderMarkers = SKNode()
    private var renderedWorld: World?
    private var renderedPower: Set<WorldCoordinate> = []
    private(set) var highlightedTile: WorldCoordinate?

    init(screen: ScreenDescriptor, mapper: CoordinateMapper) {
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
        outputFlash.strokeColor = .white
        outputFlash.fillColor = NSColor.white.withAlphaComponent(0.5)
        outputFlash.lineWidth = 4
        outputFlash.zPosition = 4
        outputFlash.isHidden = true
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
        if let world = renderedWorld { updateWorld(world, poweredTiles: renderedPower) }
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
        for mapping in mappings where screen.contains(mapping.screenCenter) {
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: -32, y: -32, width: 64, height: 64))
            path.move(to: CGPoint(x: -40, y: 0))
            path.addLine(to: CGPoint(x: 40, y: 0))
            path.move(to: CGPoint(x: 0, y: -40))
            path.addLine(to: CGPoint(x: 0, y: 40))
            let marker = SKShapeNode(path: path)
            marker.name = mapping.id
            marker.position = mapper.scenePoint(fromScreen: mapping.screenCenter, on: screen)
            marker.strokeColor = .systemPink.withAlphaComponent(0.85)
            marker.fillColor = .clear
            marker.lineWidth = 1.5
            finderMarkers.addChild(marker)
        }
    }

    func updateOccupancy(_ snapshot: DesktopOccupancySnapshot) {
        occupancyLayer.removeAllChildren()
        guard case let .available(tiles) = snapshot else { return }
        for occupancy in tiles.values where !occupancy.items.isEmpty {
            let rect = mapper.sceneRect(forTile: occupancy.coordinate, on: screen).insetBy(dx: 2, dy: 2)
            let node = SKShapeNode(rect: rect)
            let color: NSColor = occupancy.items.count == 1 ? .systemGreen : .systemRed
            node.fillColor = color.withAlphaComponent(0.3)
            node.strokeColor = color
            node.lineWidth = 2
            occupancyLayer.addChild(node)
        }
    }

    func updateWorld(_ world: World, poweredTiles: Set<WorldCoordinate> = []) {
        renderedWorld = world
        renderedPower = poweredTiles
        tileLayer.removeAllChildren()
        circuitLayer.removeAllChildren()
        let viewport = CGRect(origin: .zero, size: size)
        for (coordinate, tile) in world.tiles.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen)
            guard rect.intersects(viewport) else { continue }
            let node = SKShapeNode(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            node.name = "tile:\(coordinate.x),\(coordinate.y)"
            node.fillColor = terrainColor(tile.terrain)
            node.strokeColor = .clear
            tileLayer.addChild(node)
            if let decoration = tile.decoration {
                let label = SKLabelNode(text: decoration.rawValue)
                label.fontName = "Menlo"
                label.fontSize = 9
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: rect.midX, y: rect.midY)
                tileLayer.addChild(label)
            }
        }
        for (coordinate, component) in world.circuit.components.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen)
            guard component.kind != .empty, rect.intersects(viewport) else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let powered = poweredTiles.contains(coordinate)
            if component.kind == .dust {
                let wire = CGMutablePath()
                wire.addEllipse(in: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
                for neighbor in world.circuit.occupiedCardinalNeighbors(at: coordinate) {
                    let neighborRect = mapper.sceneRect(forTile: neighbor, on: screen)
                    wire.move(to: center)
                    // Reach the neighboring component center, including buttons and outputs.
                    wire.addLine(to: CGPoint(x: neighborRect.midX, y: neighborRect.midY))
                }
                let node = SKShapeNode(path: wire)
                node.name = "dust-path"
                node.strokeColor = powered ? .systemYellow : .systemRed
                node.fillColor = node.strokeColor
                node.lineWidth = 8
                circuitLayer.addChild(node)
            } else {
                let title = component.kind == .button ? "PRESS" : component.kind.rawValue.uppercased()
                let node = SKShapeNode(rect: rect.insetBy(dx: 8, dy: 8))
                node.name = title
                node.zPosition = 0.1
                node.fillColor = powered ? .systemOrange : .darkGray
                node.strokeColor = .white
                node.lineWidth = 2
                circuitLayer.addChild(node)
                let label = SKLabelNode(text: title)
                label.fontName = "Menlo-Bold"
                label.fontSize = 10
                label.fontColor = .white
                label.zPosition = 0.2
                label.verticalAlignmentMode = .center
                label.position = center
                circuitLayer.addChild(label)
            }
        }
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
        outputFlash.removeAllActions()
        outputFlash.path = CGPath(rect: mapper.sceneRect(forTile: coordinate, on: screen).insetBy(dx: 3, dy: 3), transform: nil)
        outputFlash.alpha = 1
        outputFlash.isHidden = false
        outputFlash.run(.sequence([.fadeOut(withDuration: 0.5), .hide()]))
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
