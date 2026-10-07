import Foundation
import CoreGraphics

enum DesktopItemKind: String, Sendable {
    case file, folder, application, alias, unknown
}

struct DesktopItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String
    /// Raw Finder desktop position. Center interpretation was confirmed by the owner on their Mac.
    let position: CGPoint
    let estimatedIconSize: CGSize?
    let kind: DesktopItemKind
}
