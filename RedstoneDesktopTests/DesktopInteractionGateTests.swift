import AppKit
import XCTest
@testable import RedstoneDesktop

final class DesktopInteractionGateTests: XCTestCase {
    @MainActor
    func testFinderDesktopRecipientAcceptedWithoutExaminingUnrelatedDockBounds() {
        // This Finder layer and window ID were read from real window metadata on this Mac.
        let identity = MouseEventIdentity(windowNumber: 107, handlingWindowID: 107, targetProcessID: 123)
        XCTAssertNil(DesktopInteractionGate.rejectionReason(identity, recipientOwnerPID: 123,
            recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
        // A full-screen Dock window never enters this decision: only the event recipient does.
    }

    @MainActor
    func testFinderFolderOtherApplicationsAndDockRecipientsRejected() {
        let identity = MouseEventIdentity(windowNumber: 42, handlingWindowID: 42, targetProcessID: 123)
        XCTAssertTrue(DesktopInteractionGate.rejectionReason(identity, recipientOwnerPID: 123,
            recipientBundleID: "com.apple.finder", recipientLayer: 0)?.contains("Finder window") == true)
        for bundle in ["com.apple.dock", "com.brave.Browser"] {
            XCTAssertNotNil(DesktopInteractionGate.rejectionReason(identity, recipientOwnerPID: 123,
                recipientBundleID: bundle, recipientLayer: 20))
        }
    }

    @MainActor
    func testMissingAndConflictingIdentityFailClosed() {
        XCTAssertNotNil(DesktopInteractionGate.rejectionReason(MouseEventIdentity()))
        let identity = MouseEventIdentity(windowNumber: 42, targetProcessID: 321)
        XCTAssertNotNil(DesktopInteractionGate.rejectionReason(identity, recipientOwnerPID: 123,
            recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
        let noPID = MouseEventIdentity(windowNumber: 42)
        XCTAssertNil(DesktopInteractionGate.rejectionReason(noPID, recipientOwnerPID: 123,
            recipientBundleID: "com.apple.finder", recipientLayer: Int(CGWindowLevelForKey(.desktopIconWindow))))
    }
}
