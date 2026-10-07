import Foundation

@MainActor
protocol CircuitTickScheduling {
    func start(onTick: @escaping @MainActor () -> Void)
    func stop()
}

/// UI-independent scheduling adapter. Main-run-loop delays do not create catch-up bursts.
@MainActor
final class CircuitTickScheduler: CircuitTickScheduling {
    static let ticksPerSecond = 20
    static let interval: TimeInterval = 1.0 / Double(ticksPerSecond)
    private var timer: Timer?
    private var registrationID: UUID?
    private let schedule: (Timer) -> Void

    init(schedule: @escaping (Timer) -> Void = { RunLoop.main.add($0, forMode: .common) }) {
        self.schedule = schedule
    }

    func start(onTick: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let id = UUID()
        registrationID = id
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.registrationID == id else { return }
                onTick()
            }
        }
        timer.tolerance = 0.005
        self.timer = timer
        schedule(timer)
    }

    func stop() {
        registrationID = nil
        timer?.invalidate()
        timer = nil
    }
}
