import AppKit
import XCTest
@testable import RedstoneDesktop

final class DesktopInteractionGateTests: XCTestCase {
    @MainActor
    func testWindowBoundsBlockCircuitAndMissingInformationFailsClosed() {
        let screen = ScreenDescriptor(id: "primary", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 2)
        let bounds = CGRect(x: 100, y: 100, width: 200, height: 200)
        let window: [String: Any] = [kCGWindowLayer as String: 0, kCGWindowAlpha as String: 1,
                                    kCGWindowBounds as String: bounds.dictionaryRepresentation]
        XCTAssertEqual(CoordinateMapper.screenRect(fromTopLeft: bounds, referenceScreen: screen), CGRect(x: 100, y: 180, width: 200, height: 200))
        XCTAssertFalse(DesktopInteractionGate.allows(CGPoint(x: 150, y: 200), finderIsFrontmost: true, windows: [window], reference: screen))
        XCTAssertTrue(DesktopInteractionGate.allows(CGPoint(x: 50, y: 50), finderIsFrontmost: true, windows: [window], reference: screen))
        XCTAssertFalse(DesktopInteractionGate.allows(.zero, finderIsFrontmost: false, windows: [], reference: screen))
        XCTAssertFalse(DesktopInteractionGate.allows(.zero, finderIsFrontmost: true, windows: nil, reference: screen))
        XCTAssertFalse(DesktopInteractionGate.allows(.zero, finderIsFrontmost: true, windows: [[:]], reference: screen))
        var desktop = window
        desktop[kCGWindowLayer as String] = -1
        XCTAssertTrue(DesktopInteractionGate.allows(CGPoint(x: 150, y: 200), finderIsFrontmost: true, windows: [desktop], reference: screen))
    }
    @MainActor
    func testFullDisplayDockWindowExplainsKnownFeasibilityBlocker() {
        // Reproduces real metadata observed on this Mac, not a claim of click ownership.
        let screen = ScreenDescriptor(id: "primary", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), backingScale: 2)
        let dock: [String: Any] = [kCGWindowLayer as String: 20, kCGWindowAlpha as String: 1,
                                  kCGWindowOwnerName as String: "Dock",
                                  kCGWindowBounds as String: screen.frame.dictionaryRepresentation]
        let reason = DesktopInteractionGate.rejectionReason(CGPoint(x: 160, y: 224), finderIsFrontmost: true, windows: [dock], reference: screen)
        XCTAssertTrue(reason?.contains("Dock") == true)
        XCTAssertTrue(reason?.contains("layer 20") == true)
        XCTAssertTrue(reason?.contains("awaiting correction") == true)
    }

}
