import Foundation
import CoreGraphics

/// Cached provider data, also published while the desktop renderer is stopped.
struct FinderReadSnapshot: Equatable, Sendable {
    var items: [DesktopItem] = []
    var error: String?
    var hasRead = false
}

/// Pure proposed-camera projection. Never reads Finder, advances a circuit, or opens an item.
struct EditorFinderProjection: Equatable, Sendable {
    struct Marker: Equatable, Sendable {
        let item: DesktopItem
        let worldCenter: WorldPoint
        let tile: WorldCoordinate
    }
    let worldID: UUID
    let camera: CameraState
    let markers: [Marker]
    let occupancy: DesktopOccupancySnapshot

    init(worldID: UUID, camera: CameraState, snapshot: FinderReadSnapshot,
         screen: ScreenDescriptor?, reference: ScreenDescriptor?, enabled: Bool) {
        self.worldID = worldID
        self.camera = camera
        guard enabled else {
            markers = []; occupancy = .unavailable("Show Finder Items to see projected occupancy."); return
        }
        guard snapshot.error == nil, snapshot.hasRead else {
            markers = []; occupancy = .unavailable(snapshot.error ?? "Waiting for Finder items…"); return
        }
        guard let screen, let reference, let mapper = try? CoordinateMapper(canvasFrame: screen.frame, camera: camera) else {
            markers = []; occupancy = .unavailable("Display geometry is unavailable."); return
        }
        let resolved = DesktopOccupancyResolver().resolve(items: snapshot.items, mapper: mapper,
            finderReference: reference, activeScreen: screen)
        occupancy = resolved
        guard case .available = resolved else { markers = []; return }
        markers = snapshot.items.compactMap { item in
            let mapping = mapper.finderMapping(for: item, referenceScreen: reference)
            guard screen.contains(mapping.screenCenter), let tile = mapping.tile else { return nil }
            return Marker(item: item, worldCenter: mapper.worldPoint(fromScreen: mapping.screenCenter), tile: tile)
        }.sorted { ($0.item.id, $0.item.url.path) < ($1.item.id, $1.item.url.path) }
    }

    /// A near-center hit can cross a tile edge. Equidistant centers on different tiles do not guess.
    func snappedTile(near point: CGPoint, mapper: CoordinateMapper, radius: CGFloat = 24) -> WorldCoordinate? {
        guard mapper.canvasFrame.contains(point), radius.isFinite, radius >= 0 else { return nil }
        let candidates = markers.compactMap { marker -> (WorldCoordinate, CGFloat)? in
            let center = mapper.screenPoint(fromWorld: marker.worldCenter)
            guard mapper.canvasFrame.contains(center) else { return nil }
            let distance = hypot(center.x - point.x, center.y - point.y)
            return distance <= radius ? (marker.tile, distance) : nil
        }.sorted { $0.1 < $1.1 }
        guard let first = candidates.first else { return nil }
        guard !candidates.contains(where: { abs($0.1 - first.1) < 0.000001 && $0.0 != first.0 }) else { return nil }
        return first.0
    }
}
