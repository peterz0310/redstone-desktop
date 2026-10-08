import SpriteKit

/// Receives snapshots only. No Finder provider, simulation mutation, or action executor.
@MainActor
final class CircuitRenderer {
    let textures = CircuitTextures()

    func render(_ world: CircuitWorld, poweredTiles: Set<WorldCoordinate>, occupancy: DesktopOccupancySnapshot,
                mapper: CoordinateMapper, screen: ScreenDescriptor, viewport: CGRect, into layer: SKNode, leverPositions: Set<WorldCoordinate>? = nil,
                powerLevels: [WorldCoordinate: PowerLevel]? = nil) {
        layer.removeAllChildren()
        for (coordinate, component) in world.components.sorted(by: { ($0.key.y, $0.key.x) < ($1.key.y, $1.key.x) }) {
            let rect = mapper.sceneRect(forTile: coordinate, on: screen)
            guard component.kind != .empty, rect.intersects(viewport) else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let level = powerLevels?[coordinate] ?? (powerLevels == nil && poweredTiles.contains(coordinate) ? .full : .off)
            let powered = level > .off
            let brightness: CGFloat = powered ? 0.45 + 0.55 * CGFloat(level.rawValue) / 15 : 1
            guard let textureID = CircuitTextureID.id(for: component.kind, powered: component.kind == .lever ? (leverPositions?.contains(coordinate) ?? powered) : powered) else { continue }
            if component.kind == .output {
                let node = SKShapeNode(rect: rect)
                node.name = "OUTPUT"
                node.fillColor = .clear; node.strokeColor = .clear; node.lineWidth = 0
                let icon = SKSpriteNode(texture: textures.texture(for: textureID))
                icon.name = "component-icon:\(coordinate.x),\(coordinate.y)"
                icon.size = rect.size; icon.position = center
                node.addChild(icon)
                let glow = SKShapeNode(rect: rect.insetBy(dx: 1, dy: 1))
                glow.name = "output-occupancy:\(coordinate.x),\(coordinate.y)"
                glow.fillColor = .clear; glow.lineWidth = 1.5; glow.glowWidth = 6
                glow.zPosition = 0.1
                switch occupancy.state(at: coordinate) {
                case .occupied: glow.strokeColor = .systemGreen; glow.alpha = 0.55
                case .empty: glow.strokeColor = .systemRed; glow.alpha = 0.30
                case .ambiguous: glow.strokeColor = .systemOrange; glow.alpha = 0.45
                case .unavailable: glow.strokeColor = .gray; glow.alpha = 0.25
                }
                node.addChild(glow)
                layer.addChild(node)
                continue
            }
            if component.kind == .dust {
                let wire = CGMutablePath()
                let radius = rect.width / 10
                wire.addRect(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
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
                    // Keep subpaths disjoint: SpriteKit's fill rule can turn overlapping rectangles into holes.
                    if endpoint.x == center.x {
                        let start = endpoint.y < center.y ? endpoint.y : center.y + radius
                        let end = endpoint.y < center.y ? center.y - radius : endpoint.y
                        wire.addRect(CGRect(x: center.x - radius, y: start, width: radius * 2, height: end - start))
                    } else {
                        let start = endpoint.x < center.x ? endpoint.x : center.x + radius
                        let end = endpoint.x < center.x ? center.x - radius : endpoint.x
                        wire.addRect(CGRect(x: start, y: center.y - radius, width: end - start, height: radius * 2))
                    }
                }
                let node = SKShapeNode(path: wire)
                node.name = "dust-path"
                node.strokeColor = powered ? .red : NSColor(calibratedRed: 0.42, green: 0.05, blue: 0.07, alpha: 1)
                node.fillColor = NSColor(white: brightness, alpha: 1) // Neutral intensity preserves the pack's hue.
                node.fillTexture = textures.texture(for: textureID)
                node.lineWidth = 0
                node.isAntialiased = false
                layer.addChild(node)
                continue
            }
            if component.kind == .repeater {
                for port in [component.direction, component.direction.opposite] {
                    guard let neighbor = port.neighbor(of: coordinate), let other = world.components[neighbor] else { continue }
                    let outgoing = port == component.direction
                    let connects: Bool
                    switch other.kind {
                    case .dust: connects = true
                    case .repeater:
                        connects = (outgoing ? other.direction.opposite : other.direction).neighbor(of: neighbor) == coordinate
                    case .torch:
                        connects = outgoing
                            ? other.direction.opposite.neighbor(of: neighbor) == coordinate
                            : other.emitsPower(from: neighbor, to: coordinate)
                    case .output:
                        connects = outgoing || other.emitsPower(from: neighbor, to: coordinate, receiver: component)
                    case .button, .lever: connects = !outgoing
                    case .empty: connects = false
                    }
                    guard connects else { continue }
                    let tip = mapper.sceneRect(forTile: neighbor, on: screen)
                    let horizontal = port == .east || port == .west
                    let towardPositive = horizontal ? tip.midX > center.x : tip.midY > center.y
                    let inner = rect.width * 0.40, outer = rect.width / 2, radius = rect.width / 10
                    let start = towardPositive ? inner : -outer
                    let pathRect = horizontal
                        ? CGRect(x: center.x + start, y: center.y - radius, width: outer - inner, height: 2 * radius)
                        : CGRect(x: center.x - radius, y: center.y + start, width: 2 * radius, height: outer - inner)
                    let trace = SKShapeNode(rect: pathRect)
                    trace.name = "repeater-port:\(coordinate.x),\(coordinate.y):\(port.rawValue)"
                    trace.fillTexture = textures.texture(for: powered ? .dustOn : .dustOff)
                    trace.fillColor = NSColor(white: brightness, alpha: 1)
                    trace.lineWidth = 0
                    trace.isAntialiased = false
                    layer.addChild(trace)
                }
            }
            let title = component.kind == .button ? "PRESS" : component.kind.rawValue.uppercased()
            let inset = component.kind == .repeater ? rect.width * 0.05 : rect.width / 8
            let node = SKShapeNode(rect: rect.insetBy(dx: inset, dy: inset))
            node.name = title
            node.zPosition = 0.1
            node.fillColor = .clear
            node.strokeColor = powered ? .red : NSColor.white.withAlphaComponent(0.35)
            node.lineWidth = 2
            layer.addChild(node)
            let icon = SKSpriteNode(texture: textures.texture(for: textureID))
            icon.name = "component-icon:\(coordinate.x),\(coordinate.y)"
            let iconScale = component.kind == .repeater ? 0.86 : 0.62
            icon.size = CGSize(width: rect.width * iconScale, height: rect.height * iconScale)
            icon.position = CGPoint(x: center.x, y: center.y + (component.kind == .repeater ? 0 : rect.height * 0.09))
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
            case .repeater, .torch:
                let arrow: String
                switch component.direction {
                case .north: arrow = "↑"
                case .east: arrow = "→"
                case .south: arrow = "↓"
                case .west: arrow = "←"
                }
                labelText = component.kind == .torch ? "\(arrow) NOT" : "\(arrow) \(component.repeaterDelay.rawValue)t"
            default: labelText = title
            }
            let label = makeLabel(labelText, at: CGPoint(x: center.x, y: center.y - rect.height * 0.23), size: rect.width * 0.14)
            label.name = component.kind == .repeater ? "repeater-label:\(coordinate.x),\(coordinate.y)" : "state-label:\(coordinate.x),\(coordinate.y)"
            layer.addChild(label)
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
