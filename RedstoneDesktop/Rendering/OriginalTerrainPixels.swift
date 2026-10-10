/// Semantic, project-owned placeholder art; no files/assets from another game.
enum OriginalTerrainPixels {
    static func pixel(_ tile: Tile, x: Int, y: Int, appearance: DecorationAppearance? = nil) -> (UInt8, UInt8, UInt8, UInt8) {
        let base: (UInt8, UInt8, UInt8)
        switch tile.terrain {
        case .dryGrass: base = (173, 160, 75)
        case .snow: base = (228, 237, 243)
        case .gravel: base = (119, 122, 121)
        case .grass: base = (77, 128, 77)
        case .dirt: base = (135, 95, 59)
        case .stone: base = (139, 148, 154)
        case .sand: base = (214, 197, 132)
        case .shallowWater: base = (85, 177, 196)
        case .lava: base = (230, 104, 22)
        case .deepWater: base = (43, 97, 143)
        }
        if let decoration = tile.decoration {
            let style = appearance ?? DecorationAppearance.choose(decoration, at: WorldCoordinate(x: 0, y: 0), seed: 0, terrain: tile.terrain)
            switch style {
            case .pine, .pineLeaves, .tree, .treeLeaves:
                let pine = style == .pine || style == .pineLeaves
                if let leaf = leafPixel(x: x, y: y, pine: pine) { return leaf }
                if style == .tree || style == .pine { return logPixel(x: x, y: y, pine: pine) }
            case .shrub:
                if (2...5).contains(x) && (2...4).contains(y) { return (104, 111, 43, 255) }
                if x == 4 && y == 1 { return (111, 77, 42, 255) }
            case .mushroom:
                if x == 4 && (1...3).contains(y) { return (221, 209, 180, 255) }
                if (2...6).contains(x) && (4...5).contains(y) { return (x + y) % 3 == 0 ? (245, 233, 207, 255) : (185, 45, 36, 255) }
            case .poppy, .dandelion, .blueOrchid, .allium, .oxeyeDaisy:
                if x == 4 && (1...3).contains(y) { return (43, 100, 42, 255) }
                if x == 4 && y == 5 { return (242, 213, 66, 255) }
                if abs(x - 4) + abs(y - 5) == 1 {
                    switch style {
                    case .poppy: return (225, 40, 54, 255)
                    case .dandelion: return (247, 205, 48, 255)
                    case .blueOrchid: return (86, 179, 238, 255)
                    case .allium: return (190, 120, 216, 255)
                    default: return (236, 237, 226, 255)
                    }
                }
            case .coal, .iron:
                if (1...6).contains(x) && (1...6).contains(y) {
                    if (x * 3 + y * 5) % 7 < 2 { return style == .coal ? (32, 34, 39, 255) : (205, 160, 126, 255) }
                    return (128, 135, 142, 255)
                }
            case .reed:
                if (x == 2 || x == 4 || x == 6) && (2...5).contains(y) { return (71, 116, 48, 255) }
            case .cactus:
                if (2...5).contains(x) && (2...5).contains(y) {
                    return (x + y) % 3 == 0 ? (26, 82, 30, 255) : (57, 137, 52, 255)
                }
            }
        }
        let shade: UInt8 = tile.terrain == .gravel ? UInt8((x * 7 + y * 3) % 4 * 9) : ((x + y) % 5 == 0 ? 8 : 0)
        return (base.0 - shade, base.1 - shade, base.2 - shade, 255)
    }

    /// Whole leaf-block top, with holes that reveal ground or the central log.
    static func leafPixel(x: Int, y: Int, pine: Bool) -> (UInt8, UInt8, UInt8, UInt8)? {
        if (x * 5 + y * 3) % 11 < 3 { return nil }
        let shade = UInt8((x * 3 + y * 7) % 3 * 12)
        return pine ? (38 + shade, 85 + shade, 65 + shade, 255) : (40 + shade, 103 + shade, 43 + shade, 255)
    }

    static func logPixel(x: Int, y: Int, pine: Bool) -> (UInt8, UInt8, UInt8, UInt8) {
        let ring = max(abs(x - 3), abs(y - 3))
        if x == 0 || y == 0 || x == 7 || y == 7 { return pine ? (67, 47, 32, 255) : (94, 67, 38, 255) }
        let shade: UInt8 = ring % 2 == 0 ? 16 : 0
        return pine ? (127 - shade, 89 - shade, 56 - shade, 255) : (185 - shade, 145 - shade, 87 - shade, 255)
    }

}
