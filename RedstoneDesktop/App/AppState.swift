import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var isDesktopWorldEnabled = false
    @Published private(set) var desktopStatus = "Desktop checker is disabled."
    private var desktopController: DesktopWindowController?
    private let screenFrame: () -> CGRect?

    init(screenFrame: @escaping () -> CGRect? = { NSScreen.main?.frame }) {
        self.screenFrame = screenFrame
    }

    func toggleDesktopWorld() {
        if isDesktopWorldEnabled {
            desktopController?.disable()
            desktopController?.close()
            desktopController = nil
            isDesktopWorldEnabled = false
            desktopStatus = "Desktop checker is disabled."
        } else {
            guard let frame = screenFrame() else {
                desktopStatus = "No main display is available."
                return
            }
            let controller = DesktopWindowController(frame: frame)
            controller.enable()
            desktopController = controller
            isDesktopWorldEnabled = true
            desktopStatus = "Desktop checker is enabled. Verify Finder icons and clicks."
        }
    }
}
