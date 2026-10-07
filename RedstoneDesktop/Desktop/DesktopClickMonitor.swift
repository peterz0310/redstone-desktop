import AppKit

@MainActor
protocol GlobalMouseEventMonitoring {
    func addLeftMouseDownMonitor(handler: @escaping @MainActor (CGPoint) -> Void) -> Any?
    func removeMonitor(_ token: Any)
}

@MainActor
struct AppKitGlobalMouseEventMonitor: GlobalMouseEventMonitoring {
    func addLeftMouseDownMonitor(handler: @escaping @MainActor (CGPoint) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            // Apple's global-monitor callbacks are delivered on the main thread.
            MainActor.assumeIsolated {
                handler(CoordinateMapper.screenPoint(for: event))
            }
        }
    }

    func removeMonitor(_ token: Any) {
        NSEvent.removeMonitor(token)
    }
}

extension CoordinateMapper {
    @MainActor
    static func screenPoint(for event: NSEvent) -> CGPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        // A mouse event without an associated window already uses screen points.
        return event.locationInWindow
    }
}

struct DesktopClickSnapshot: Equatable, Sendable {
    let screenPoint: CGPoint
    let tile: WorldCoordinate
}

@MainActor
final class DesktopClickMonitor {
    private let screen: ScreenDescriptor
    private let mapper: CoordinateMapper
    private let eventMonitoring: any GlobalMouseEventMonitoring
    private let onClick: (DesktopClickSnapshot) -> Void
    private var token: Any?
    private var registrationID: UUID?

    var isRunning: Bool { token != nil }

    init(
        screen: ScreenDescriptor,
        mapper: CoordinateMapper,
        eventMonitoring: any GlobalMouseEventMonitoring = AppKitGlobalMouseEventMonitor(),
        onClick: @escaping (DesktopClickSnapshot) -> Void
    ) {
        self.screen = screen
        self.mapper = mapper
        self.eventMonitoring = eventMonitoring
        self.onClick = onClick
    }

    @discardableResult
    func start() -> Bool {
        guard token == nil else { return true }
        let id = UUID()
        registrationID = id
        token = eventMonitoring.addLeftMouseDownMonitor { [weak self] point in
            guard let self, self.registrationID == id,
                  self.screen.contains(point), let tile = self.mapper.tile(atScreen: point) else { return }
            self.onClick(DesktopClickSnapshot(screenPoint: point, tile: tile))
        }
        if token == nil { registrationID = nil }
        return isRunning
    }

    func stop() {
        // Invalidate callbacks before removal, including callbacks from a prior start.
        registrationID = nil
        guard let token else { return }
        self.token = nil
        eventMonitoring.removeMonitor(token)
    }
}
