/// Stable scenery variants, independent of rendering or load order.
/// The legacy `rock` slot is displayed as an ore deposit; it is never rewritten in saves.
enum DecorationAppearance: String, CaseIterable, Sendable {
    case tree, poppy, dandelion, blueOrchid, allium, oxeyeDaisy, coal, iron, reed, cactus, pine, shrub, mushroom

    static func choose(_ decoration: DecorationID, at coordinate: WorldCoordinate, seed: UInt64, terrain: TerrainID? = nil) -> Self {
        let roll = SeededNoise.hash(seed: seed, x: coordinate.x, y: coordinate.y, channel: 0xDEC0)
        switch decoration {
        case .tree: return .tree
        case .pine: return .pine
        case .shrub: return .shrub
        case .mushroom: return .mushroom
        case .reed: return .reed
        case .rock: return terrain == .sand ? .cactus : (roll & 1 == 0 ? .coal : .iron)
        case .flower: return [.poppy, .dandelion, .blueOrchid, .allium, .oxeyeDaisy][Int(roll % 5)]
        }
    }

    var name: String {
        switch self {
        case .blueOrchid: "blue orchid"
        case .oxeyeDaisy: "oxeye daisy"
        case .coal: "coal deposit"
        case .iron: "iron deposit"
        default: rawValue
        }
    }
}
