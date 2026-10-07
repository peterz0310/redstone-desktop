import AppKit

struct PointerSnapshot: Equatable, Sendable {
    let screenPoint: CGPoint
    let screenID: String?
    let worldPoint: WorldPoint?
    let tile: WorldCoordinate?
}

/// Samples position without receiving, consuming, or monitoring mouse events.
@MainActor
final class PointerMonitor {
    private let screen: ScreenDescriptor
    private let mapper: CoordinateMapper
    private let mouseLocation: () -> CGPoint
    private let onChange: (PointerSnapshot) -> Void
    private var timer: Timer?
    private var lastSnapshot: PointerSnapshot?
    private(set) var isRunning = false

    init(
        screen: ScreenDescriptor,
        mapper: CoordinateMapper,
        mouseLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        onChange: @escaping (PointerSnapshot) -> Void
    ) {
        self.screen = screen
        self.mapper = mapper
        self.mouseLocation = mouseLocation
        self.onChange = onChange
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer.tolerance = 0.005
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        lastSnapshot = nil
    }

    /// Also serves as a deterministic sampling entry point for fake-pointer tests.
    func sample() {
        guard isRunning else { return }
        let point = mouseLocation()
        let inside = screen.contains(point)
        let snapshot = PointerSnapshot(
            screenPoint: point,
            screenID: inside ? screen.id : nil,
            worldPoint: inside ? mapper.worldPoint(fromScreen: point) : nil,
            tile: inside ? mapper.tile(atScreen: point) : nil
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        onChange(snapshot)
    }
}
