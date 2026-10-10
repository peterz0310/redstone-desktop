import Foundation

enum TextureAssetID: String, Codable, CaseIterable, Sendable {
    case terrainGrass, terrainDirt, terrainStone, terrainSand, waterShallow, waterDeep
    case lavaStill
    case terrainDryGrass, terrainSnow, terrainGravel
    case decorationOakLog, decorationSpruceLog
    case decorationPine, decorationShrub, decorationMushroom
    case decorationTree, decorationFlower, decorationRock, decorationReed
    case decorationDandelion, decorationBlueOrchid, decorationAllium, decorationOxeyeDaisy
    case decorationCoal, decorationIron, decorationCactus
    case redstoneDustOff, redstoneDustOn, redstoneButtonUp, redstoneButtonDown
    case redstoneLeverOff, redstoneLeverOn, redstoneRepeaterOff, redstoneRepeaterOn
    case redstoneOutputOff, redstoneOutputOn, redstoneTorchOff, redstoneTorchOn

    case redstonePlateOff, redstonePlateOn, redstoneSensorOff, redstoneSensorOn

    static func terrain(_ id: TerrainID) -> Self {
        switch id {
        case .dryGrass: .terrainDryGrass
        case .snow: .terrainSnow
        case .gravel: .terrainGravel
        case .grass: .terrainGrass
        case .dirt: .terrainDirt
        case .stone: .terrainStone
        case .sand: .terrainSand
        case .shallowWater: .waterShallow
        case .deepWater: .waterDeep
        case .lava: .lavaStill
        }
    }
    static func decoration(_ id: DecorationID) -> Self {
        switch id {
        case .treeLeaves: .decorationTree
        case .pineLeaves: .decorationPine
        case .pine: .decorationPine
        case .shrub: .decorationShrub
        case .mushroom: .decorationMushroom
        case .tree: .decorationTree
        case .flower: .decorationFlower
        case .rock: .decorationRock
        case .reed: .decorationReed
        }
    }
    var isAnimatedLiquid: Bool { [.waterShallow, .waterDeep, .lavaStill].contains(self) }

    var circuitID: CircuitTextureID? {
        CircuitTextureID.allCases.first { $0.assetID == self }
    }

    static func decoration(_ appearance: DecorationAppearance) -> Self {
        switch appearance {
        case .treeLeaves: .decorationTree
        case .pineLeaves: .decorationPine
        case .pine: .decorationPine
        case .shrub: .decorationShrub
        case .mushroom: .decorationMushroom
        case .tree: .decorationTree
        case .poppy: .decorationFlower
        case .dandelion: .decorationDandelion
        case .blueOrchid: .decorationBlueOrchid
        case .allium: .decorationAllium
        case .oxeyeDaisy: .decorationOxeyeDaisy
        case .coal: .decorationCoal
        case .iron: .decorationIron
        case .reed: .decorationReed
        case .cactus: .decorationCactus
        }
    }
    var decorationAppearance: DecorationAppearance? {
        DecorationAppearance.allCases.first { Self.decoration($0) == self }
            ?? (self == .decorationRock ? .coal : nil)
    }
    var decorationFallback: Self? {
        switch self {
        case .decorationCoal, .decorationIron: .decorationRock
        case .decorationDandelion, .decorationBlueOrchid, .decorationAllium, .decorationOxeyeDaisy: .decorationFlower
        default: nil
        }
    }
}

struct PackManifest: Codable, Equatable, Sendable {
    var formatVersion: Int = 1
    var name: String
    var author: String?
    var assets: [String: String]
    var animations: [String: TextureAnimationSpec]? = nil
}

struct PackError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum PackFiles {
    static func validatePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains(":"), !path.unicodeScalars.contains(where: { $0.value < 32 }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PackError("Unsafe relative asset path: \(path.prefix(100))")
        }
    }
    static func read(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= limit else { throw PackError("Not a regular file or file exceeds \(limit) bytes: \(url.lastPathComponent)") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw PackError("File grew beyond its size limit.") }
        return data
    }
}
