import Foundation

/// A snapshot of display geometry. Frames use global macOS logical points.
struct ScreenDescriptor: Equatable, Sendable {
    let id: String
    let frame: CGRect
    let backingScale: Double

    /// Half-open edges give a shared boundary to only one adjacent display.
    func contains(_ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.minY && point.y < frame.maxY
    }
}
