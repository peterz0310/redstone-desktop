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
    @Published private(set) var readAttempts = 0
    @Published private(set) var lastReadDuration: TimeInterval?
    @Published private(set) var lastSuccessfulRead: Date?
    @Published private(set) var items: [DesktopItem] = []
    @Published private(set) var permission: PermissionStatus = .notRequested
    @Published private(set) var isReading = false
    @Published private(set) var hasRead = false
    @Published private(set) var error: String?
    @Published private(set) var viewSettings: FinderViewSettings?
    @Published private(set) var baselineViewSettings: FinderViewSettings?
    @Published private(set) var isLayoutSettling = false
    private(set) var layoutGeneration = UUID()
    private let layoutSettleDelay: Duration
    private var geometryGeneration = UUID()
    private var readTask: Task<FinderDesktopSnapshot, Error>?
    private var readsSuspended = false
    private let provider: any DesktopItemProviding

    init(provider: any DesktopItemProviding = FinderDesktopItemProvider(), layoutSettleDelay: Duration = .milliseconds(500)) {
        self.provider = provider
        self.layoutSettleDelay = layoutSettleDelay
    }

    /// Old in-flight results cannot repopulate positions measured before a display change.
    func invalidateDisplayPositions() {
        geometryGeneration = UUID()
        hasRead = false
        items = []
        // Preserve permission and its error; this does not send an Apple Event or prompt again.
    }

    private func readSnapshot() async throws -> FinderDesktopSnapshot {
        let task = Task { try await provider.currentDesktopSnapshot() }
        readTask = task
        defer { readTask = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func suspendReads() async {
        readsSuspended = true
        invalidateDisplayPositions()
        let task = readTask
        task?.cancel()
        _ = try? await task?.value
    }
    func resumeReads() { readsSuspended = false }

    @discardableResult
    func readItems() async -> Bool {
        guard !isReading, !readsSuspended else { return false }
        let generation = geometryGeneration
        let started = ProcessInfo.processInfo.systemUptime
        readAttempts += 1
        isReading = true
        defer {
            lastReadDuration = ProcessInfo.processInfo.systemUptime - started
            isLayoutSettling = false; isReading = false
        }
        // Publish the reading state before awaiting the shared asynchronous provider.
        await Task.yield()
        guard !Task.isCancelled, generation == geometryGeneration else { return false }
        do {
            var snapshot = try await readSnapshot()
            guard !Task.isCancelled, generation == geometryGeneration else { return false }
            let changedSize = viewSettings != nil && snapshot.viewSettings != nil && viewSettings != snapshot.viewSettings
            if !snapshot.layoutIsStable || changedSize {
                layoutGeneration = UUID()
                isLayoutSettling = true
                hasRead = false
                items = []
                var candidate = snapshot.viewSettings
                repeat {
                    try await Task.sleep(for: layoutSettleDelay)
                    guard !Task.isCancelled, generation == geometryGeneration else { return false }
                    snapshot = try await readSnapshot()
                    guard !Task.isCancelled, generation == geometryGeneration else { return false }
                    if snapshot.layoutIsStable && (snapshot.viewSettings == nil || snapshot.viewSettings == candidate) { break }
                    candidate = snapshot.viewSettings
                } while true
            }
            if viewSettings != snapshot.viewSettings { viewSettings = snapshot.viewSettings }
            if baselineViewSettings == nil, let settings = snapshot.viewSettings { baselineViewSettings = settings }
            let sorted = snapshot.items.sorted { ($0.displayName, $0.url.path) < ($1.displayName, $1.url.path) }
            if items != sorted { items = sorted }
            error = nil
            permission = .allowed
            hasRead = true
            lastSuccessfulRead = Date()
            return true
        } catch {
            guard !Task.isCancelled, generation == geometryGeneration else { return false }
            self.error = error.localizedDescription
            if !items.isEmpty { items = [] }
            if error as? FinderReadError == .permissionDenied {
                permission = .denied
            } else if permission == .notRequested {
                permission = .unknown
            }
            return false
        }
    }
}
