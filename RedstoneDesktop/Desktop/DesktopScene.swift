import SpriteKit

/// A window-local diagnostic checker, not a world-space renderer.
/// World/screen mapping will be introduced through CoordinateMapper in Slice 3.
final class DesktopScene: SKScene {
    static let checkerSize: CGFloat = 64

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
        rebuildChecker()
    }

    required init?(coder: NSCoder) {
        fatalError("DesktopScene is created programmatically")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildChecker()
    }

    private func rebuildChecker() {
        removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        let paths = [CGMutablePath(), CGMutablePath()]
        let columns = Int(ceil(size.width / Self.checkerSize))
        let rows = Int(ceil(size.height / Self.checkerSize))

        for row in 0..<rows {
            for column in 0..<columns {
                paths[(row + column) % 2].addRect(CGRect(
                    x: CGFloat(column) * Self.checkerSize,
                    y: CGFloat(row) * Self.checkerSize,
                    width: Self.checkerSize,
                    height: Self.checkerSize
                ))
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
