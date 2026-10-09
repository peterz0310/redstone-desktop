import AppKit
import Combine

/// Public AppKit notification adapter; geometry is re-read, never taken from userInfo.
@MainActor
final class DisplayChangeMonitor {
    private let center: NotificationCenter
    private let onChange: () -> Void
    private var observation: AnyCancellable?

    init(center: NotificationCenter = .default, onChange: @escaping () -> Void) {
        self.center = center
        self.onChange = onChange
    }

    func start() {
        guard observation == nil else { return }
        observation = center.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            // AppKit delivers this notification on the main actor.
            MainActor.assumeIsolated { self?.onChange() }
        }
    }

    func stop() { observation = nil }
}

struct DisplayGeometry: Equatable, Sendable {
    let target: ScreenDescriptor?
    let finderReference: ScreenDescriptor?
    var screens: [ScreenDescriptor] = []
}
