import Foundation
import CoreGraphics

/// One logical canvas; gaps between physical displays are never interaction/action targets.
struct DesktopCanvas: Equatable, Sendable {
    let screens: [ScreenDescriptor]
    let frame: CGRect

    init(screens: [ScreenDescriptor]) throws {
        guard !screens.isEmpty, screens.count <= 16, Set(screens.map(\.id)).count == screens.count else {
            throw CoordinateMapper.ValidationError.invalidCanvas
        }
        var physical: [ScreenDescriptor] = []
        for screen in screens {
            _ = try CoordinateMapper(canvasFrame: screen.frame, camera: SavedArea.homeCamera)
            guard screen.backingScale.isFinite, screen.backingScale > 0 else { throw CoordinateMapper.ValidationError.invalidCanvas }
            // Mirrored descriptors share a viewport; do not stack duplicate windows.
            if !physical.contains(where: { $0.frame == screen.frame }) { physical.append(screen) }
        }
        self.screens = physical
        frame = physical.dropFirst().reduce(physical[0].frame) { $0.union($1.frame) }
        _ = try CoordinateMapper(canvasFrame: frame, camera: SavedArea.homeCamera)
    }

    func screen(at point: CGPoint) -> ScreenDescriptor? { screens.first { $0.contains(point) } }
    var descriptor: ScreenDescriptor {
        screens.count == 1 ? screens[0] : ScreenDescriptor(id: "virtual-desktop", frame: frame, backingScale: 1)
    }
}
