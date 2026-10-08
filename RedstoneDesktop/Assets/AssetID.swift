import Foundation

enum TextureAssetID: String, Codable, CaseIterable, Sendable {
    case terrainGrass, terrainDirt, terrainStone, terrainSand, waterShallow, waterDeep
    case decorationTree, decorationFlower, decorationRock, decorationReed
    case redstoneDustOff, redstoneDustOn, redstoneButtonUp, redstoneButtonDown
    case redstoneLeverOff, redstoneLeverOn, redstoneRepeaterOff, redstoneRepeaterOn
    case redstoneOutputOff, redstoneOutputOn

    static func terrain(_ id: TerrainID) -> Self {
        switch id {
        case .grass: .terrainGrass
        case .dirt: .terrainDirt
        case .stone: .terrainStone
        case .sand: .terrainSand
        case .shallowWater: .waterShallow
        case .deepWater: .waterDeep
        }
    }
    static func decoration(_ id: DecorationID) -> Self {
        switch id {
        case .tree: .decorationTree
        case .flower: .decorationFlower
        case .rock: .decorationRock
        case .reed: .decorationReed
        }
    }
    var circuitID: CircuitTextureID? {
        CircuitTextureID.allCases.first { $0.assetID == self }
    }
}

struct PackManifest: Codable, Equatable, Sendable {
    var formatVersion: Int = 1
    var name: String
    var author: String?
    var assets: [String: String]
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
