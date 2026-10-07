@MainActor
protocol DesktopItemProviding {
    func currentDesktopItems() async throws -> [DesktopItem]
}
