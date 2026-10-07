import Foundation
import XCTest
@testable import RedstoneDesktop

@MainActor
final class ManualCircuitTickScheduler: CircuitTickScheduling {
    var callback: (@MainActor () -> Void)?
    func start(onTick: @escaping @MainActor () -> Void) { callback = onTick }
    func stop() { callback = nil }
    func fire() { callback?() }
}

final class CircuitTickSchedulerTests: XCTestCase {
    @MainActor
    func testTwentyHzDuplicateStartStopAndRestart() {
        var registered: [Timer] = []
        var ticks = 0
        let scheduler = CircuitTickScheduler(schedule: { registered.append($0) })
        defer { scheduler.stop() }
        scheduler.start { ticks += 1 }
        scheduler.start { ticks += 100 }
        XCTAssertEqual(registered.count, 1)
        XCTAssertEqual(registered[0].timeInterval, 0.05, accuracy: 0.00001)
        registered[0].fire()
        XCTAssertEqual(ticks, 1)
        scheduler.stop()
        scheduler.stop()
        registered[0].fire()
        XCTAssertEqual(ticks, 1)
        scheduler.start { ticks += 1 }
        XCTAssertEqual(registered.count, 2)
        registered[0].fire()
        registered[1].fire()
        XCTAssertEqual(ticks, 2)
    }
}
