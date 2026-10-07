import Foundation

/// A calibration hypothesis, not confirmed Finder icon geometry.
struct FinderItemMapping: Identifiable, Equatable, Sendable {
    let item: DesktopItem
    let provisionalCenter: CGPoint
    let tile: WorldCoordinate?
    var id: String { item.id }
}
