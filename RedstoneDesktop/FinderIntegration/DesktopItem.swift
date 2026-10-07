import Foundation

enum DesktopItemKind: String, Sendable {
    case file, folder, application, alias, unknown
}

struct DesktopItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String
    /// Raw Finder desktop position. Its icon-center semantics are not calibrated yet.
    let position: CGPoint
    let estimatedIconSize: CGSize?
    let kind: DesktopItemKind
}
