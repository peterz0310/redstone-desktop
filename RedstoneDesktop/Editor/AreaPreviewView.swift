import SwiftUI

/// Disposable schematic snapshots; no Finder access, simulator or saved image files.
struct AreaPreviewSnapshot: Equatable {
    let document: WorldDocument
    let camera: CameraState
    let displaySize: CGSize
}

@MainActor
enum AreaPreviewRenderer {
    static let imageSize = CGSize(width: 144, height: 88)

    static func image(for snapshot: AreaPreviewSnapshot) -> NSImage? {
        guard snapshot.displaySize.width.isFinite, snapshot.displaySize.height.isFinite,
              snapshot.displaySize.width > 0, snapshot.displaySize.height > 0,
              let world = try? snapshot.document.restoredWorld() else { return nil }
        let scale = min(imageSize.width / snapshot.displaySize.width, imageSize.height / snapshot.displaySize.height)
        let size = CGSize(width: snapshot.displaySize.width * scale, height: snapshot.displaySize.height * scale)
        guard size.height >= 1,
              let mapper = try? CoordinateMapper(canvasFrame: CGRect(origin: .zero, size: size),
                  camera: CameraState(worldOrigin: snapshot.camera.worldOrigin,
                    pointsPerTile: snapshot.camera.pointsPerTile * size.width / snapshot.displaySize.width)) else { return nil }
        // Sample a fixed 48 x 30 grid even for huge/high-resolution displays.
        let columns = 48, rows = 30
        var cells: [(CGRect, NSColor)] = []
        for y in 0..<rows {
            for x in 0..<columns {
                let rect = CGRect(x: Double(x) * size.width / Double(columns), y: Double(y) * size.height / Double(rows),
                    width: size.width / Double(columns), height: size.height / Double(rows))
                guard let tile = mapper.tile(atScreen: CGPoint(x: rect.midX, y: rect.midY)) else { continue }
                let terrain = world.tile(at: tile).map { TerrainAppearance.tile($0, generated: world.generation != nil && world.tiles[tile] == nil) }
                let color: NSColor
                switch terrain?.terrain {
                case .dryGrass: color = NSColor(red: 0.68, green: 0.63, blue: 0.29, alpha: 1)
                case .snow: color = NSColor(red: 0.89, green: 0.93, blue: 0.95, alpha: 1)
                case .gravel: color = NSColor(red: 0.47, green: 0.48, blue: 0.47, alpha: 1)
                case .grass: color = NSColor(red: 0.28, green: 0.5, blue: 0.35, alpha: 1)
                case .dirt: color = .brown
                case .stone: color = .gray
                case .sand: color = NSColor(red: 0.8, green: 0.72, blue: 0.45, alpha: 1)
                case .shallowWater: color = .systemTeal
                case .deepWater: color = .systemBlue
                case nil: color = .darkGray
                }
                cells.append((rect, terrain?.decoration == nil ? color : color.blended(withFraction: 0.4, of: .black) ?? color))
            }
        }
        let components = world.circuit.components.compactMap { coordinate, component -> (CGRect, NSColor)? in
            let rect = mapper.screenRect(forTile: coordinate)
            guard component.kind != .empty, rect.intersects(mapper.canvasFrame) else { return nil }
            return (rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15), component.kind == .dust ? .systemRed : .white)
        }
        // Force rasterization once; view updates reuse this bitmap rather than rerun sampling.
        let image = NSImage(size: size)
        image.lockFocus()
        for (rect, color) in cells + components { color.setFill(); rect.fill() }
        image.unlockFocus()
        return image
    }
}

struct AreaPreviewView: View {
    let snapshot: AreaPreviewSnapshot
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.none).scaledToFit() }
            else { Image(systemName: "map").foregroundStyle(.secondary) }
        }
        .frame(width: 144, height: 88)
        .background(Color.black.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: snapshot, initial: true) { _, value in image = AreaPreviewRenderer.image(for: value) }
        .accessibilityLabel("Terrain and circuit preview")
    }
}
