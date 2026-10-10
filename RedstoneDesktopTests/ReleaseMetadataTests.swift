import XCTest
@testable import RedstoneDesktop

final class ReleaseMetadataTests: XCTestCase {
    func testBuiltApplicationDeclaresDeploymentTargetAndSpecificPermissionUse() throws {
        let bundle = Bundle.main
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleIdentifier") as? String, "org.redstonedesktop.RedstoneDesktop")
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String, "14.0")
        XCTAssertTrue(try XCTUnwrap(bundle.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String).contains("Finder"))
        XCTAssertTrue(try XCTUnwrap(bundle.object(forInfoDictionaryKey: "NSDesktopFolderUsageDescription") as? String).lowercased().contains("script"))
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
    }
    func testBuiltApplicationKeepsLicenseAndGameIconNoticeWithoutLocalPacksOrOwnerSaves() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL)
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let notice = try String(contentsOf: root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        XCTAssertTrue(license.contains("MIT License")); XCTAssertTrue(license.contains("Third-party artwork is excluded"))
        XCTAssertTrue(notice.contains("Mojang/Microsoft")); XCTAssertTrue(notice.contains("6d0e6a1fd54142cd3de649e1100c428733512b322a0b0a530f62eae9f86881ec"))
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator {
            XCTAssertFalse(["jar", "zip", "sh", "command", "zsh", "class", "lua"].contains(url.pathExtension.lowercased()))
            XCTAssertFalse(["library.json", "blueprints.json", "world.json", "import.json", "pack.json", "preferences.plist"].contains(url.lastPathComponent))
            XCTAssertFalse(url.pathComponents.contains("ImportedTextures"))
        }
    }
}
