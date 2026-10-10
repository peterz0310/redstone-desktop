import Foundation

/// Configuration only. Matching reads Finder metadata, never file contents or executable code.
enum FileSensorMatch: String, CaseIterable, Codable, Sendable {
    case anyItem, fileExtension, exactName
    var title: String {
        switch self { case .anyItem: "Any item"; case .fileExtension: "File extension"; case .exactName: "Item name" }
    }
}
struct FileSensorFilter: Codable, Equatable, Sendable {
    var match: FileSensorMatch = .anyItem
    var value = ""
    var isValid: Bool {
        value.utf8.count <= 255 && !value.unicodeScalars.contains(where: { $0.value < 32 }) &&
        (match == .anyItem || !value.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty)
    }
    func matches(_ item: DesktopItem) -> Bool {
        guard isValid else { return false }
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch match {
        case .anyItem: return true
        case .exactName: return item.url.lastPathComponent.caseInsensitiveCompare(query) == .orderedSame
        case .fileExtension:
            guard item.kind == .file else { return false }
            return item.url.pathExtension.caseInsensitiveCompare(query.trimmingCharacters(in: CharacterSet(charactersIn: "."))) == .orderedSame
        }
    }
}

/// Converts an already mapped Finder snapshot into plain simulator inputs.
enum DesktopSensorInputs {
    static func isFresh(lastRead: Date?, now: Date = Date()) -> Bool {
        guard let lastRead else { return false }
        let age = now.timeIntervalSince(lastRead)
        return age >= 0 && age <= 2
    }
    static func active(in world: CircuitWorld, occupancy: DesktopOccupancySnapshot) -> Set<WorldCoordinate> {
        Set(world.components.compactMap { tile, component in
            guard component.kind.isDesktopSensor else { return nil }
            let items: [DesktopItem]
            switch occupancy.state(at: tile) {
            case .occupied(let item): items = [item]
            case .ambiguous(let group): items = group
            case .empty, .unavailable: return nil
            }
            return items.contains(where: { component.kind == .pressurePlate || component.sensorFilter.matches($0) }) ? tile : nil
        })
    }
}
