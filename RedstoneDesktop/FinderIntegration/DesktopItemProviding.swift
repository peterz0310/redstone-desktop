@MainActor
protocol DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem]
    func currentDesktopSnapshot() async throws -> FinderDesktopSnapshot
}

extension DesktopItemProviding {
    /// Providers without public view settings retain ordinary center-based tracking.
    func currentDesktopSnapshot() async throws -> FinderDesktopSnapshot {
        FinderDesktopSnapshot(items: try await currentDesktopItems())
    }
}
