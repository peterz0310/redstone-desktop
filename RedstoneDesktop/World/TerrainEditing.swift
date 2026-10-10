import Foundation

enum TerrainBrush: String, CaseIterable, Sendable {
    case grass = "Grass", dirt = "Dirt", stone = "Stone", sand = "Sand"
    case dryGrass = "Dry grass", snow = "Snow", gravel = "Gravel"
    case shallowWater = "Shallow water", deepWater = "Deep water"
    case clearDecorations = "Clear decorations", restore = "Restore original"
    var terrain: TerrainID? {
        switch self {
        case .grass: .grass; case .dirt: .dirt; case .stone: .stone; case .sand: .sand
        case .dryGrass: .dryGrass; case .snow: .snow; case .gravel: .gravel
        case .shallowWater: .shallowWater; case .deepWater: .deepWater
        case .clearDecorations, .restore: nil
        }
    }
}
struct TerrainEditPlan {
    let overrides: [WorldCoordinate: Tile]
    let world: World
    let changed: Set<WorldCoordinate>
    let protected: Set<WorldCoordinate>
}
enum TerrainEditing {
    static let maximumStrokeTiles = 4096
    static let maximumSavedTiles = 8192
    static func footprint(center: WorldCoordinate, size: Int) throws -> Set<WorldCoordinate> {
        guard [1, 3, 5].contains(size) else { throw BlueprintError("Choose a 1, 3 or 5 tile brush.") }
        var tiles: Set<WorldCoordinate> = []
        for dx in -(size / 2)...(size / 2) { for dy in -(size / 2)...(size / 2) {
            let (x, ox) = center.x.addingReportingOverflow(dx), (y, oy) = center.y.addingReportingOverflow(dy)
            guard !ox, !oy else { throw BlueprintError("Brush is outside the supported map.") }
            tiles.insert(WorldCoordinate(x: x, y: y))
        } }
        return tiles
    }
    /// Bounded Bresenham interpolation prevents gaps without allocating an unbounded path.
    static func line(from start: WorldCoordinate, to end: WorldCoordinate) throws -> [WorldCoordinate] {
        let (deltaX, ox) = end.x.subtractingReportingOverflow(start.x), (deltaY, oy) = end.y.subtractingReportingOverflow(start.y)
        guard !ox, !oy, deltaX > -maximumStrokeTiles, deltaX < maximumStrokeTiles,
              deltaY > -maximumStrokeTiles, deltaY < maximumStrokeTiles else { throw BlueprintError("Stroke is too long. Release and paint another stroke.") }
        let dx = abs(deltaX), dy = -abs(deltaY), sx = deltaX >= 0 ? 1 : -1, sy = deltaY >= 0 ? 1 : -1
        var point = start, error = dx + dy, result: [WorldCoordinate] = []
        while true {
            result.append(point)
            if point == end { return result }
            let twice = 2 * error
            if twice >= dy { error += dy; point.x += sx }
            if twice <= dx { error += dx; point.y += sy }
        }
    }
    static func plan(document: WorldDocument, brush: TerrainBrush, tiles: Set<WorldCoordinate>) throws -> TerrainEditPlan {
        guard tiles.count <= maximumStrokeTiles else { throw BlueprintError("A stroke can cover up to 4096 tiles. Release and paint another stroke.") }
        let original = try document.restoredWorld(), base = document.unmodifiedWorld()
        var overrides = document.terrainOverrides
        var changed: Set<WorldCoordinate> = [], protected: Set<WorldCoordinate> = []
        for coordinate in tiles {
            let replacement: Tile?
            switch brush {
            case .restore: replacement = base.tile(at: coordinate)
            case .clearDecorations:
                guard var tile = original.tile(at: coordinate), tile.decoration != nil else { continue }
                tile = TerrainAppearance.tile(tile, generated: original.tiles[coordinate] == nil)
                tile.decoration = nil; replacement = tile
            default: replacement = Tile(terrain: brush.terrain!)
            }
            if let component = original.circuit.components[coordinate] {
                let candidate = World(tiles: replacement.map { [coordinate: $0] } ?? [:])
                guard PlacementRules().canPlace(component: component, at: coordinate, in: candidate).isAllowed else {
                    protected.insert(coordinate); continue
                }
            }
            if brush == .restore { overrides.removeValue(forKey: coordinate) }
            else if let replacement { overrides[coordinate] = replacement }
            if overrides[coordinate] != document.terrainOverrides[coordinate] { changed.insert(coordinate) }
        }
        guard overrides.count <= maximumSavedTiles else { throw BlueprintError("This world has reached its 8192 edited tile limit. Restore some original terrain first.") }
        var next = document; next.terrainOverrides = overrides
        return TerrainEditPlan(overrides: overrides, world: try next.restoredWorld(), changed: changed, protected: protected)
    }
}

struct TerrainStroke {
    let document: WorldDocument
    let brush: TerrainBrush
    let size: Int
    private(set) var tiles: Set<WorldCoordinate> = []
    private(set) var last: WorldCoordinate?
    private(set) var plan: TerrainEditPlan?
    mutating func extend(to center: WorldCoordinate) throws {
        var candidate = tiles
        for point in try TerrainEditing.line(from: last ?? center, to: center) {
            candidate.formUnion(try TerrainEditing.footprint(center: point, size: size))
            guard candidate.count <= TerrainEditing.maximumStrokeTiles else { throw BlueprintError("Stroke is too large. Release and paint another stroke.") }
        }
        let next = try TerrainEditing.plan(document: document, brush: brush, tiles: candidate)
        tiles = candidate; last = center; plan = next
    }
}
enum TerrainStrokePhase { case begin, drag, end, cancel }
