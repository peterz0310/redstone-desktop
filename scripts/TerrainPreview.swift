import AppKit

/// Standalone developer artifact using real fallback pixels; never opens the app.
@main
struct TerrainPreview {
    static func main() throws {
        let seeds: [UInt64] = [42, 2026, 7]
        let image = NSImage(size: NSSize(width: 1232, height: 860))
        image.lockFocus()
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1232, height: 860).fill()
        func label(_ text: String, x: Int, y: Int) {
            (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
        }
        for (index, seed) in seeds.enumerated() {
            let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: seed))
            let offset = 16 + index * 408
            label("Generation 3 · Seed \(seed)", x: offset, y: 834)
            var biomes: [String: Int] = [:]
            for y in 0..<192 { for x in 0..<192 {
                let point = WorldCoordinate(x: (x - 96) * 4, y: (y - 96) * 4)
                let sample = generator.sample(at: point)
                biomes[sample.biome.rawValue, default: 0] += 1
                let p = OriginalTerrainPixels.pixel(Tile(terrain: sample.tile.terrain), x: 1, y: 1)
                NSColor(red: Double(p.0)/255, green: Double(p.1)/255, blue: Double(p.2)/255, alpha: 1).setFill()
                NSRect(x: offset + x * 2, y: 442 + y * 2, width: 2, height: 2).fill()
            } }
            label("Overview: −384…380 · 4 tiles/sample", x: offset, y: 419)
            label("Ground detail: −24…23 · original art", x: offset, y: 394)
            for y in 0..<48 { for x in 0..<48 {
                let point = WorldCoordinate(x: x - 24, y: y - 24), tile = generator.tile(at: point)
                let appearance = tile.decoration.map { DecorationAppearance.choose($0, at: point, seed: seed, terrain: tile.terrain) }
                for py in 0..<8 { for px in 0..<8 {
                    let p = OriginalTerrainPixels.pixel(tile, x: px, y: py, appearance: appearance)
                    NSColor(red: Double(p.0)/255, green: Double(p.1)/255, blue: Double(p.2)/255, alpha: 1).setFill()
                    NSRect(x: offset + x * 8 + px, y: 8 + y * 8 + py, width: 1, height: 1).fill()
                } }
            } }
            print("Seed \(seed) biome samples: \(biomes.sorted { $0.key < $1.key })")
        }
        image.unlockFocus()
        let destination = CommandLine.arguments.dropFirst().first ?? "build/terrain-preview.png"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: destination).deletingLastPathComponent(), withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
        print("Terrain comparison written to \(destination)")
    }
}
