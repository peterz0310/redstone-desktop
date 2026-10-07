/// Capabilities are domain data, independent of terrain color or texture.
struct TerrainDefinition: Equatable, Sendable {
    let id: TerrainID
    let isLiquid: Bool
    let isSolidSurface: Bool
    let supportsCircuit: Bool
    let supportsHeavyComponent: Bool
}

extension TerrainID {
    var definition: TerrainDefinition {
        switch self {
        case .grass, .dirt, .stone, .sand:
            return TerrainDefinition(id: self, isLiquid: false, isSolidSurface: true,
                                     supportsCircuit: true, supportsHeavyComponent: true)
        case .shallowWater, .deepWater:
            return TerrainDefinition(id: self, isLiquid: true, isSolidSurface: false,
                                     supportsCircuit: false, supportsHeavyComponent: false)
        }
    }
}
