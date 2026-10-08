import Foundation

/// Raw public Finder icon-size setting. It never defines world scale or center offsets.
struct FinderViewSettings: Equatable, Sendable {
    let iconSize: Int

    init?(iconSize: Double) {
        guard iconSize.isFinite, let integer = Int(exactly: iconSize), integer > 0, integer <= 4096 else { return nil }
        self.iconSize = integer
    }
}

struct FinderDesktopSnapshot: Equatable, Sendable {
    let items: [DesktopItem]
    let viewSettings: FinderViewSettings?
    /// Size is sampled before/after item positions; changing samples must settle and be reread.
    let layoutIsStable: Bool

    init(items: [DesktopItem], viewSettings: FinderViewSettings? = nil, layoutIsStable: Bool = true) {
        self.items = items
        self.viewSettings = viewSettings
        self.layoutIsStable = layoutIsStable
    }
}
