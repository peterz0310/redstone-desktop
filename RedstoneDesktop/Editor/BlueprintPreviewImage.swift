import AppKit

/// Cached, action-free thumbnails. Layout conversion uses the same mapper as the world.
@MainActor enum BlueprintPreviewImage {
    private static var cache: [UUID: (CircuitWorld, NSImage)] = [:]
    static func image(for blueprint: CircuitBlueprint) -> NSImage {
        if let entry = cache[blueprint.id], entry.0 == blueprint.circuit { return entry.1 }
        let size = CGSize(width: 192, height: 100)
        let scale = min(size.width / CGFloat(blueprint.width + 1), size.height / CGFloat(blueprint.height + 1))
        let camera = CameraState(worldOrigin: WorldPoint(x: -Double((size.width / scale - CGFloat(blueprint.width)) / 2),
            y: -Double((size.height / scale - CGFloat(blueprint.height)) / 2)), pointsPerTile: Double(scale))
        let mapper = try? CoordinateMapper(canvasFrame: CGRect(origin: .zero, size: size), camera: camera)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let mapper else { return false }
            NSGraphicsContext.current?.imageInterpolation = .none
            NSColor(calibratedWhite: 0.10, alpha: 1).setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            for (tile, component) in blueprint.circuit.components {
                let rect = mapper.screenRect(forTile: tile), center = CGPoint(x: rect.midX, y: rect.midY)
                NSColor(calibratedWhite: 0.18, alpha: 1).setFill(); NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
                if component.kind == .dust {
                    NSColor(calibratedRed: 0.65, green: 0.10, blue: 0.13, alpha: 1).setFill()
                    let path = NSBezierPath(); path.lineWidth = max(1, scale / 5)
                    for neighbor in blueprint.circuit.occupiedCardinalNeighbors(at: tile) {
                        guard let other = blueprint.circuit.components[neighbor], other.kind != .lightTorch else { continue }
                        if other.kind == .repeater, other.direction.neighbor(of: neighbor) != tile, other.direction.opposite.neighbor(of: neighbor) != tile { continue }
                        let next = mapper.screenRect(forTile: neighbor)
                        path.move(to: center); path.line(to: CGPoint(x: (center.x + next.midX) / 2, y: (center.y + next.midY) / 2))
                    }
                    NSColor(calibratedRed: 0.65, green: 0.10, blue: 0.13, alpha: 1).setStroke(); path.stroke()
                    NSBezierPath(rect: rect.insetBy(dx: scale * 0.38, dy: scale * 0.38)).fill()
                } else if let id = CircuitTextureID.id(for: component.kind, powered: false) {
                    NSGraphicsContext.saveGraphicsState()
                    let transform = NSAffineTransform(); transform.translateX(by: center.x, yBy: center.y)
                    if component.kind == .repeater {
                        let angle: CGFloat = switch component.direction { case .east: 0; case .north: 90; case .west: 180; case .south: 270 }
                        transform.rotate(byDegrees: angle)
                    }
                    transform.concat()
                    CircuitTextures.image(for: id).draw(in: CGRect(x: -scale * 0.42, y: -scale * 0.42, width: scale * 0.84, height: scale * 0.84))
                    NSGraphicsContext.restoreGraphicsState()
                    if component.kind == .torch {
                        let arrow = switch component.direction { case .east: "→"; case .north: "↑"; case .west: "←"; case .south: "↓" }
                        (arrow as NSString).draw(at: CGPoint(x: rect.maxX - scale * 0.35, y: rect.minY), withAttributes: [.font: NSFont.boldSystemFont(ofSize: max(5, scale * 0.35)), .foregroundColor: NSColor.white])
                    }
                }
            }
            return true
        }
        if cache.count >= 160 { cache.removeAll() }
        cache[blueprint.id] = (blueprint.circuit, image)
        return image
    }
}
