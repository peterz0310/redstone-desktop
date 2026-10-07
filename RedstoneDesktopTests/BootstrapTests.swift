import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

final class BootstrapTests: XCTestCase {
    @MainActor
    func testEditorCanBeHostedInNativeApp() {
        let hostingView = NSHostingView(rootView: EditorView(appState: AppState()))
        let size = hostingView.fittingSize

        XCTAssertGreaterThanOrEqual(size.width, 1060)
        XCTAssertGreaterThanOrEqual(size.height, 760)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "org.redstonedesktop.RedstoneDesktop")
    }
}
