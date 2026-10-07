import Foundation
import Combine

enum PermissionStatus: String {
    case notRequested = "Not requested"
    case unknown = "Unknown after failed read"
    case allowed = "Allowed on last successful read"
    case denied = "Denied"
}

@MainActor
final class FinderDiagnosticsModel: ObservableObject {
    @Published private(set) var items: [DesktopItem] = []
    @Published private(set) var permission: PermissionStatus = .notRequested
    @Published private(set) var isReading = false
    @Published private(set) var hasRead = false
    @Published private(set) var error: String?
    private let provider: any DesktopItemProviding

    init(provider: any DesktopItemProviding = FinderDesktopItemProvider()) {
        self.provider = provider
    }

    func readItems() async {
        guard !isReading else { return }
        isReading = true
        error = nil
        defer { isReading = false }
        // Give SwiftUI a chance to display the reading state before NSAppleScript runs.
        await Task.yield()
        do {
            let result = try await provider.currentDesktopItems()
            items = result.sorted { ($0.displayName, $0.url.path) < ($1.displayName, $1.url.path) }
            permission = .allowed
            hasRead = true
        } catch {
            items = []
            if error as? FinderReadError == .permissionDenied {
                permission = .denied
            } else if permission == .notRequested {
                permission = .unknown
            }
            self.error = error.localizedDescription
        }
    }
}
