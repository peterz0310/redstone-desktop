import AppKit
import XCTest
@testable import RedstoneDesktop

final class DesktopInteractionGateTests: XCTestCase {
    @MainActor
    func testFinderDesktopRecipientAcceptedWithoutExaminingUnrelatedDockBounds() {
        // This Finder layer and window ID were read from real window metadata on this Mac.
        let identity = MouseEventIdentity(windowNumber: 107, handlingWindowID: 107, targetProcessID: 123)
        XCTAssertNil(DesktopInteractionGate.rejectionReason(identity, recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
        // A full-screen Dock window never enters this decision: only the event recipient does.
    }

    @MainActor
    func testFinderFolderOtherApplicationsAndDockRecipientsRejected() {
        let identity = MouseEventIdentity(windowNumber: 42, handlingWindowID: 42, targetProcessID: 123)
        XCTAssertTrue(DesktopInteractionGate.rejectionReason(identity, recipientBundleID: "com.apple.finder", recipientLayer: 0)?.contains("Finder window") == true)
        for bundle in ["com.apple.dock", "com.brave.Browser"] {
            XCTAssertNotNil(DesktopInteractionGate.rejectionReason(identity, recipientBundleID: bundle, recipientLayer: 20))
        }
    }

    @MainActor
    func testMissingIdentityFailsClosedButTargetPIDDoesNotDefineOwnership() {
        XCTAssertNotNil(DesktopInteractionGate.assess(MouseEventIdentity()).rejectionReason)
        let identity = MouseEventIdentity(windowNumber: 42, targetProcessID: 321)
        XCTAssertNil(DesktopInteractionGate.rejectionReason(identity, recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
        let noPID = MouseEventIdentity(windowNumber: 42)
        XCTAssertNil(DesktopInteractionGate.rejectionReason(noPID, recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
    }
    @MainActor
    func testAssociatedWindowPreferredAndMissingAssociatedWindowFallsBack() {
        XCTAssertEqual(DesktopInteractionGate.selectedWindowID(MouseEventIdentity(windowNumber: 107, handlingWindowID: 900)), 107)
        XCTAssertEqual(DesktopInteractionGate.selectedWindowID(MouseEventIdentity(handlingWindowID: 107)), 107)
        XCTAssertNil(DesktopInteractionGate.selectedWindowID(MouseEventIdentity(windowNumber: -1, handlingWindowID: -1)))
    }

}
