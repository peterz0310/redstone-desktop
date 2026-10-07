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
        defer { isReading = false }
        // Give SwiftUI a chance to display the reading state before NSAppleScript runs.
        await Task.yield()
        guard !Task.isCancelled else { return }
        do {
            let result = try await provider.currentDesktopItems()
            guard !Task.isCancelled else { return }
            let sorted = result.sorted { ($0.displayName, $0.url.path) < ($1.displayName, $1.url.path) }
            if items != sorted { items = sorted }
            error = nil
            permission = .allowed
            hasRead = true
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            if !items.isEmpty { items = [] }
            if error as? FinderReadError == .permissionDenied {
                permission = .denied
            } else if permission == .notRequested {
                permission = .unknown
            }
        }
    }
}
