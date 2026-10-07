import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var desktopStatus = "Desktop checker is disabled."
    @Published private(set) var pointer: PointerSnapshot?
    let desktopCamera = CameraState(worldOrigin: WorldPoint(x: 0, y: 0), pointsPerTile: 64)
    private var desktopController: DesktopWindowController?
    private var pointerMonitor: PointerMonitor?
    private let screenProviding: () -> ScreenDescriptor?

    init(screenProviding: @escaping () -> ScreenDescriptor? = {
        NSScreen.main.map { ScreenDescriptor(screen: $0) }
    }) {
        self.screenProviding = screenProviding
    }

    func toggleDesktopWorld() {
        if isDesktopWorldEnabled {
            pointerMonitor?.stop()
            pointerMonitor = nil
            pointer = nil
            desktopController?.disable()
            desktopController?.close()
            desktopController = nil
            isDesktopWorldEnabled = false
            desktopStatus = "Desktop checker is disabled."
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
                controller.enable()
                monitor.start()
                isDesktopWorldEnabled = true
                desktopStatus = "Desktop checker is enabled. Move the pointer to highlight a tile."
            } catch {
                desktopStatus = "Display geometry cannot be mapped. Desktop checker remains disabled."
            }
        }
    }
}
