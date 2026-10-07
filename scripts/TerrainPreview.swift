import Foundation

/// Standalone developer artifact, not the application renderer or a world editor.
@main
struct TerrainPreview {
    static func main() throws {
        let seeds: [UInt64] = [42, 2026]
        let palette: [TerrainID: String] = [.grass: "#69a653", .dirt: "#997347", .stone: "#92999d",
                                           .sand: "#dfcd87", .shallowWater: "#61b8ce", .deepWater: "#32678e"]
        var svg = "<svg xmlns='http://www.w3.org/2000/svg' width='850' height='500' viewBox='0 0 850 500'><rect width='850' height='500' fill='#f8f8f6'/>"
        for (index, seed) in seeds.enumerated() {
            let generator = try WorldGenerator(settings: WorldGenerationSettings(seed: seed))
            let offset = 25 + index * 420
            svg += "<text x='\(offset)' y='25' font-family='sans-serif' font-size='17'>Generation 1 · Seed \(seed)</text>"
            for y in -64..<64 {
                for x in -64..<64 {
                    let tile = generator.tile(at: WorldCoordinate(x: x, y: y))
                    let px = offset + (x + 64) * 3, py = 40 + (63 - y) * 3
                    svg += "<rect x='\(px)' y='\(py)' width='3' height='3' fill='\(palette[tile.terrain]!)'/>"
                    if tile.decoration != nil { svg += "<circle cx='\(px + 1)' cy='\(py + 1)' r='0.65' fill='#26322b'/>" }
                }
            }
            for step in stride(from: 0, through: 128, by: 32) {
                let p = step * 3
                svg += "<path d='M\(offset + p) 40v384 M\(offset) \(40 + p)h384' fill='none' stroke='#000' stroke-opacity='.15'/>"
            }
            svg += "<text x='\(offset)' y='445' font-family='sans-serif' font-size='12'>x, y = −64…63 · lines every 32 tiles · dots = decorations</text>"
        }
        for (index, terrain) in TerrainID.allCases.enumerated() {
            let x = 25 + index * 135
            svg += "<rect x='\(x)' y='465' width='12' height='12' fill='\(palette[terrain]!)'/><text x='\(x + 17)' y='476' font-family='sans-serif' font-size='12'>\(terrain.rawValue)</text>"
        }
        svg += "</svg>"
        let destination = CommandLine.arguments.dropFirst().first ?? "build/terrain-preview.svg"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: destination).deletingLastPathComponent(), withIntermediateDirectories: true)
        try svg.write(toFile: destination, atomically: true, encoding: .utf8)
        print("Terrain comparison written to \(destination)")
    }
}
