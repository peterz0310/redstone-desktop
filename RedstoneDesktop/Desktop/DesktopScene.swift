import SpriteKit

/// Diagnostic world tiles and cursor outline, using CoordinateMapper exclusively.
final class DesktopScene: SKScene {
    let screen: ScreenDescriptor
    let mapper: CoordinateMapper
    private let highlight = SKShapeNode()
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
        rebuildChecker()
    }

    required init?(coder: NSCoder) {
        fatalError("DesktopScene is created programmatically")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildChecker()
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

    private func rebuildChecker() {
        removeAllChildren()
        addChild(highlight)
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
