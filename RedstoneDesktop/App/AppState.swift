import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var desktopStatus = "Desktop checker is disabled."
    @Published private(set) var pointer: PointerSnapshot?
    @Published private(set) var lastClick: DesktopClickSnapshot?
    @Published private(set) var observedClickCount = 0
    let desktopCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    let finderDiagnostics = FinderDiagnosticsModel()
    private var desktopController: DesktopWindowController?
    private var pointerMonitor: PointerMonitor?
    private var clickMonitor: DesktopClickMonitor?
    private var terminationObserver: AnyCancellable?
    private let screenProviding: () -> ScreenDescriptor?
    private let clickEventMonitoring: any GlobalMouseEventMonitoring

    init(screenProviding: @escaping () -> ScreenDescriptor? = {
        NSScreen.main.map { ScreenDescriptor(screen: $0) }
    }, clickEventMonitoring: any GlobalMouseEventMonitoring = AppKitGlobalMouseEventMonitor()) {
        self.screenProviding = screenProviding
        self.clickEventMonitoring = clickEventMonitoring
        terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.shutdown() }
            }
    }

    /// Used by both disable and the app's termination notification.
    func shutdown() {
        clickMonitor?.stop()
        clickMonitor = nil
        pointerMonitor?.stop()
        pointerMonitor = nil
        pointer = nil
        lastClick = nil
        observedClickCount = 0
        desktopController?.disable()
        desktopController?.close()
        desktopController = nil
        isDesktopWorldEnabled = false
        desktopStatus = "Desktop checker is disabled."
    }

    func toggleDesktopWorld() {
        if isDesktopWorldEnabled {
            shutdown()
        } else {
            guard let screen = screenProviding() else {
                desktopStatus = "No main display is available."
                return
            }
            do {
                let mapper = try CoordinateMapper(canvasFrame: screen.frame, camera: desktopCamera)
                let controller = DesktopWindowController(screen: screen, mapper: mapper)
                let monitor = PointerMonitor(screen: screen, mapper: mapper) { [weak self, weak controller] snapshot in
                    self?.pointer = snapshot
                    controller?.scene.updateHighlight(snapshot.tile)
                }
                desktopController = controller
                pointerMonitor = monitor
                let clicks = DesktopClickMonitor(screen: screen, mapper: mapper, eventMonitoring: clickEventMonitoring) { [weak self, weak controller] snapshot in
                    guard let self else { return }
                    self.lastClick = snapshot
                    self.observedClickCount += 1
                    controller?.scene.flashTile(snapshot.tile)
                }
                clickMonitor = clicks
                controller.enable()
                monitor.start()
                isDesktopWorldEnabled = true
                desktopStatus = clicks.start()
                    ? "Desktop checker is enabled. Click the desktop to flash a tile."
                    : "Desktop checker is enabled, but click observation could not start. Disable and re-enable to retry."
            } catch {
                desktopStatus = "Display geometry cannot be mapped. Desktop checker remains disabled."
            }
        }
    }
}
