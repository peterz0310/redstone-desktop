import Foundation
import XCTest
@testable import RedstoneDesktop

@MainActor
final class FixtureItemOpener: ItemOpening {
    var urls: [URL] = []
    var succeeds = true
    func open(_ url: URL) -> Bool { urls.append(url); return succeeds }
}

final class OpenItemActionTests: XCTestCase {
    @MainActor
    func testOpensOnlySingleLocalOccupantAndReportsFailure() {
        let opener = FixtureItemOpener()
        let action = OpenItemAction(opener: opener)
        let item = DesktopItem(id: "a", url: URL(fileURLWithPath: "/tmp/harmless folder"), displayName: "Fixture", position: .zero, estimatedIconSize: nil, kind: .folder)
        XCTAssertTrue(action.perform(occupancy: .empty).contains("empty"))
        XCTAssertTrue(action.perform(occupancy: .unavailable("Denied")).contains("Denied"))
        XCTAssertTrue(action.perform(occupancy: .ambiguous([item, item])).contains("ambiguous"))
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertTrue(action.perform(occupancy: .occupied(item)).contains("accepted"))
        XCTAssertEqual(opener.urls, [item.url])
        opener.succeeds = false
        XCTAssertTrue(action.perform(occupancy: .occupied(item)).contains("could not open"))
    }
}
