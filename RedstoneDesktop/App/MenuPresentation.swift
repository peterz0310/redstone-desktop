import Combine
import Foundation

/// Only menu-relevant changes publish. Live pointer/power/FPS updates never rebuild submenus.
@MainActor
final class MenuPresentation: ObservableObject {
    struct Snapshot: Equatable {
        let menu: DesktopMenuSnapshot
        let running: Bool, building: Bool, paused: Bool, muted: Bool, locked: Bool, canAssign: Bool, hasDisplay: Bool
        let maintenance: String
        @MainActor init(_ app: AppState) {
            menu = app.desktopMenu
            running = app.isDesktopWorldEnabled; building = app.isDesktopBuildMode; paused = app.isSimulationPaused
            muted = app.audioSettings.muted; locked = app.isMaintenanceLocked
            canAssign = app.canAssignDesktopArea; hasDisplay = app.desktopScreen != nil
            maintenance = locked ? app.maintenanceStatus : ""
        }
    }
    @Published private(set) var snapshot: Snapshot
    private weak var app: AppState?
    private var subscription: AnyCancellable?
    private var refresh: Task<Void, Never>?
    init(_ app: AppState) {
        self.app = app; snapshot = Snapshot(app)
        subscription = app.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
    }
    private func scheduleRefresh() {
        guard refresh == nil else { return }
        refresh = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.refresh = nil
            refreshNow()
        }
    }
    func refreshNow() {
        guard let app else { return }
        let next = Snapshot(app)
        if next != snapshot { snapshot = next }
    }
}
