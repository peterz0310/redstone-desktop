import SpriteKit

/// Receives snapshots only. No Finder provider, simulation mutation, or action executor.
@MainActor
final class CircuitRenderer {
    let textures = CircuitTextures()

    func render(_ world: CircuitWorld, poweredTiles: Set<WorldCoordinate>, occupancy: DesktopOccupancySnapshot,
                mapper: CoordinateMapper, screen: ScreenDescriptor, viewport: CGRect, into layer: SKNode, leverPositions: Set<WorldCoordinate>? = nil) {
        layer.removeAllChildren()
        for (coordinate, component) in world.components.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen)
            guard component.kind != .empty, rect.intersects(viewport) else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let powered = poweredTiles.contains(coordinate)
            guard let textureID = CircuitTextureID.id(for: component.kind, powered: powered) else { continue }
            if component.kind == .dust {
                let wire = CGMutablePath()
                let radius = rect.width / 16
                wire.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                for neighbor in world.occupiedCardinalNeighbors(at: coordinate) {
                    guard let other = world.components[neighbor] else { continue }
                    // A repeater has ports only at its rear and front, never at its sides.
                    if other.kind == .repeater,
                       other.direction.neighbor(of: neighbor) != coordinate,
                       other.direction.opposite.neighbor(of: neighbor) != coordinate { continue }
                    let neighborRect = mapper.sceneRect(forTile: neighbor, on: screen)
                    // Dust halves meet at the tile edge. For blocks, extend to their frame.
                    let fraction: CGFloat = other.kind == .dust ? 0.5 : 0.625
                    let endpoint = CGPoint(x: center.x + (neighborRect.midX - center.x) * fraction,
                                           y: center.y + (neighborRect.midY - center.y) * fraction)
                    wire.move(to: center)
                    wire.addLine(to: endpoint)
                }
                let node = SKShapeNode(path: wire)
                node.name = "dust-path"
                node.strokeColor = powered ? .systemYellow : .systemRed
                node.fillColor = node.strokeColor
                node.strokeTexture = textures.texture(for: textureID)
                node.fillTexture = node.strokeTexture
                node.lineWidth = rect.width / 8
                node.isAntialiased = false
                layer.addChild(node)
                continue
            }
            let title = component.kind == .button ? "PRESS" : component.kind.rawValue.uppercased()
            let node = SKShapeNode(rect: rect.insetBy(dx: rect.width / 8, dy: rect.height / 8))
            node.name = title
            node.zPosition = 0.1
            node.fillColor = powered ? .systemOrange : .darkGray
            node.strokeColor = .white
            node.lineWidth = 2
            layer.addChild(node)
            let icon = SKSpriteNode(texture: textures.texture(for: textureID))
            icon.name = "component-icon:\(coordinate.x),\(coordinate.y)"
            icon.size = CGSize(width: rect.width * 0.35, height: rect.height * 0.35)
            icon.position = CGPoint(x: center.x, y: center.y + rect.height * 0.13)
            icon.zPosition = 0.05
            if component.kind == .repeater {
                switch component.direction {
                case .east: icon.zRotation = 0
                case .north: icon.zRotation = .pi / 2
                case .west: icon.zRotation = .pi
                case .south: icon.zRotation = -.pi / 2
                }
            }
            node.addChild(icon)
            let labelText: String
            switch component.kind {
            case .button: labelText = powered ? "DOWN" : "PRESS"
            case .lever: labelText = (leverPositions?.contains(coordinate) ?? powered) ? "ON" : "OFF"
            case .repeater:
                let arrow: String
                switch component.direction {
                case .north: arrow = "↑"
                case .east: arrow = "→"
                case .south: arrow = "↓"
                case .west: arrow = "←"
                }
                labelText = "\(arrow) \(component.repeaterDelay.rawValue)t"
            default: labelText = title
            }
            let label = makeLabel(labelText, at: CGPoint(x: center.x, y: center.y - rect.height * 0.23), size: rect.width * 0.14)
            label.name = component.kind == .repeater ? "repeater-label:\(coordinate.x),\(coordinate.y)" : "state-label:\(coordinate.x),\(coordinate.y)"
            layer.addChild(label)
            if component.kind == .output {
                label.position.y = center.y - rect.height * 0.12
                label.fontSize = rect.width * 0.11
                let badgeText: String, color: NSColor
                switch occupancy.state(at: coordinate) {
                case .empty: (badgeText, color) = ("EMPTY", .lightGray)
                case .occupied: (badgeText, color) = ("ITEM", .systemGreen)
                case .ambiguous: (badgeText, color) = ("MANY", .systemRed)
                case .unavailable: (badgeText, color) = ("N/A", .systemPurple)
                }
                node.strokeColor = color
                let badge = makeLabel(badgeText, at: CGPoint(x: center.x, y: center.y - rect.height * 0.28), size: rect.width * 0.11)
                badge.name = "output-occupancy:\(coordinate.x),\(coordinate.y)"
                badge.fontColor = color
                node.addChild(badge)
            }
        }
    }

    private func makeLabel(_ text: String, at position: CGPoint, size: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = size
        label.fontColor = .white
        label.zPosition = 0.2
        label.verticalAlignmentMode = .center
        label.position = position
        return label
    }
}
