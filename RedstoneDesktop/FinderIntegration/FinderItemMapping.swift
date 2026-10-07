import Foundation
import CoreGraphics

/// Finder center mapping using the owner-validated calibration.
struct FinderItemMapping: Identifiable, Equatable, Sendable {
    let item: DesktopItem
    let screenCenter: CGPoint
    let tile: WorldCoordinate?
    var id: String { item.id }
}
