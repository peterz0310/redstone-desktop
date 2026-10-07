import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

final class BootstrapTests: XCTestCase {
    @MainActor
    func testEditorPlaceholderCanBeHostedInNativeApp() {
        let hostingView = NSHostingView(rootView: EditorPlaceholderView())
        let size = hostingView.fittingSize

        XCTAssertGreaterThanOrEqual(size.width, 480)
        XCTAssertGreaterThanOrEqual(size.height, 320)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "org.redstonedesktop.RedstoneDesktop")
    }
}
