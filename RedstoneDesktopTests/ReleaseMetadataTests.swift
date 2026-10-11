import XCTest
import AppKit
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
    @MainActor
    func testCatalogContainsOnlyOwnerIdentityAndAllNativeToolSymbolsExist() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalog = source.appendingPathComponent("RedstoneDesktop/Resources/Assets.xcassets")
        let folders = Set(try FileManager.default.contentsOfDirectory(atPath: catalog.path).filter { $0.hasSuffix(".imageset") || $0.hasSuffix(".appiconset") })
        XCTAssertEqual(folders, ["Logo.imageset", "MenuLogo.imageset", "AppIcon.appiconset"])
        XCTAssertNotNil(NSImage(named: "Logo")); XCTAssertNotNil(NSImage(named: "MenuLogo"))
        for tool in EditorSession.Tool.allCases where tool != .dust {
            XCTAssertNotNil(NSImage(systemSymbolName: ToolIcon.symbol(for: tool.rawValue), accessibilityDescription: nil), tool.rawValue)
        }
        for name in ["RedstoneDust", "MenuDust", "ToolDust", "ToolButton", "ToolLever", "ToolRepeater", "ToolOutput", "ToolTorch"] {
            XCTAssertNil(NSImage(named: name), "Retired game-derived icon must not be compiled into the app")
        }
    }
    func testBuiltApplicationKeepsOwnerLogoNoticeWithoutGameArtworkPacksOrOwnerSaves() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL)
        let license = try String(contentsOf: root.appendingPathComponent("LICENSE"), encoding: .utf8)
        let notice = try String(contentsOf: root.appendingPathComponent("THIRD_PARTY_NOTICES.md"), encoding: .utf8)
        XCTAssertTrue(license.contains("MIT License"))
        XCTAssertTrue(notice.contains("No Minecraft artwork")); XCTAssertTrue(notice.contains("2e2cc646437e3d992546e5b32df44ac12d1908875c1d10a15e847febf321f533"))
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator {
            XCTAssertFalse(["jar", "zip", "sh", "command", "zsh", "class", "lua"].contains(url.pathExtension.lowercased()))
            XCTAssertFalse(["library.json", "blueprints.json", "world.json", "import.json", "pack.json", "preferences.plist"].contains(url.lastPathComponent))
            XCTAssertFalse(url.pathComponents.contains("ImportedTextures"))
        }
    }
}
