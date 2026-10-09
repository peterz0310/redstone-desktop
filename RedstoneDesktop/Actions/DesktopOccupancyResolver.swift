import Foundation

enum DesktopOccupancyState: Equatable, Sendable {
    case empty
    case occupied(DesktopItem)
    case ambiguous([DesktopItem])
    case unavailable(String)
}

struct DesktopOccupancy: Equatable, Sendable, Identifiable {
    let coordinate: WorldCoordinate
    let items: [DesktopItem]
    var id: WorldCoordinate { coordinate }

    var state: DesktopOccupancyState {
        switch items.count {
        case 0: return .empty
        case 1: return .occupied(items[0])
        default: return .ambiguous(items)
        }
    }
}

enum DesktopOccupancySnapshot: Equatable, Sendable {
    case available([WorldCoordinate: DesktopOccupancy])
    case unavailable(String)

    func state(at coordinate: WorldCoordinate) -> DesktopOccupancyState {
        switch self {
        case let .available(tiles): return tiles[coordinate]?.state ?? .empty
        case let .unavailable(reason): return .unavailable(reason)
        }
    }

    var ambiguousTiles: [DesktopOccupancy] {
        guard case let .available(tiles) = self else { return [] }
        return tiles.values.filter { $0.items.count > 1 }.sorted {
            ($0.coordinate.x, $0.coordinate.y) < ($1.coordinate.x, $1.coordinate.y)
        }
    }
}

/// Pure occupancy math. No Finder querying, rendering, or action execution.
struct DesktopOccupancyResolver {
    func resolve(
        items: [DesktopItem],
        mapper: CoordinateMapper,
        finderReference: ScreenDescriptor,
        activeScreen: ScreenDescriptor
    ) -> DesktopOccupancySnapshot {
        resolve(items: items, mapper: mapper, finderReference: finderReference, activeScreens: [activeScreen])
    }

    func resolve(items: [DesktopItem], mapper: CoordinateMapper, finderReference: ScreenDescriptor,
                 activeScreens: [ScreenDescriptor]) -> DesktopOccupancySnapshot {
        var groups: [WorldCoordinate: [DesktopItem]] = [:]
        for item in items {
            let mapping = mapper.finderMapping(for: item, referenceScreen: finderReference)
            guard activeScreens.contains(where: { $0.contains(mapping.screenCenter) }) else { continue }
            guard let tile = mapping.tile else {
                return .unavailable("A Finder item center could not be mapped to a valid world tile.")
            }
            groups[tile, default: []].append(item)
        }
        return .available(Dictionary(uniqueKeysWithValues: groups.map { coordinate, items in
            let sorted = items.sorted { ($0.id, $0.url.path, $0.displayName) < ($1.id, $1.url.path, $1.displayName) }
            return (coordinate, DesktopOccupancy(coordinate: coordinate, items: sorted))
        }))
    }
}
