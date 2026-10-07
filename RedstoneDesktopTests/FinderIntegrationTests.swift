import AppKit
import CoreServices
import XCTest
@testable import RedstoneDesktop

@MainActor
private struct FakeFinderScriptRunner: FinderScriptRunning {
    let result: NSAppleEventDescriptor
    func queryDesktopItems() throws -> NSAppleEventDescriptor { result }
}

@MainActor
private final class FakeDesktopItemProvider: DesktopItemProviding {
    var operation: @MainActor () async throws -> [DesktopItem] = { [] }
    private(set) var calls = 0
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        return try await operation()
    }
}

final class FinderIntegrationTests: XCTestCase {
    @MainActor
    func testStructuredResponsePreservesNamesPathsAndRawPositions() async throws {
        let unusual = "Quotes \" and tabs\t and newline\n雪"
        let path = "/tmp/redstone-tests/not-present/\(unusual).txt"
        let result = list([
            row(name: unusual, path: path, x: .init(int32: -120), y: .init(double: 80.5)),
            row(name: unusual, path: "/tmp/redstone-tests/other.txt", x: .init(int32: 0), y: .init(int32: 1))
        ])
        let provider = FinderDesktopItemProvider(runner: FakeFinderScriptRunner(result: result))
        let items = try await provider.currentDesktopItems()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].displayName, unusual)
        XCTAssertEqual(items[0].url.path, path)
        XCTAssertEqual(items[0].position, CGPoint(x: -120, y: 80.5))
        XCTAssertNil(items[0].estimatedIconSize)
        XCTAssertNotEqual(items[0].id, items[1].id, "Display name must not be the item identity")
        let secondRead = try await provider.currentDesktopItems()
        XCTAssertEqual(secondRead, items)
    }

    @MainActor
    func testEmptyDesktopAndMalformedResponsesAreDistinct() throws {
        XCTAssertTrue(try FinderDesktopItemProvider.parse(list([])).isEmpty)
        let malformed: [NSAppleEventDescriptor] = [
            .init(string: "not a list"),
            list([list([])]),
            list([row(name: "file", path: "relative.txt", x: .init(int32: 1), y: .init(int32: 2))]),
            list([row(name: "file", path: "/tmp/file", x: .init(string: "1"), y: .init(int32: 2))]),
            list([row(name: "file", path: "/tmp/file", x: .init(double: .infinity), y: .init(int32: 2))])
        ]
        for response in malformed {
            XCTAssertThrowsError(try FinderDesktopItemProvider.parse(response)) { error in
                guard let error = error as? FinderReadError, case .malformedResponse = error else {
                    return XCTFail("Malformed responses must not be mistaken for permission denial")
                }
            }
        }
    }

    @MainActor
    func testPermissionDenialAndOtherAppleScriptErrorsAreDistinct() {
        XCTAssertEqual(FinderReadError.fromScriptError([NSAppleScript.errorNumber: Int(errAEEventNotPermitted)]), .permissionDenied)
        XCTAssertEqual(FinderReadError.fromScriptError([NSAppleScript.errorNumber: -1712, NSAppleScript.errorMessage: "Timed out"]), .scriptFailure(code: -1712, message: "Timed out"))
        XCTAssertEqual(FinderReadError.fromScriptError(nil), .scriptFailure(code: nil, message: "No error details were returned."))
    }

    @MainActor
    func testNativeScriptRunnerExecutesHarmlessFixtureAndReportsError() throws {
        // These scripts never contact Finder, request Automation permission, or modify files.
        let result = try FinderScriptRunner.execute(source: #"return {{"Fixture", "/tmp/fixture", 12, -7}}"#)
        XCTAssertEqual(try FinderDesktopItemProvider.parse(result).first?.position, CGPoint(x: 12, y: -7))
        XCTAssertThrowsError(try FinderScriptRunner.execute(source: #"error "Fixture failure" number -1700"#)) { error in
            guard let error = error as? FinderReadError, case .scriptFailure(code: -1700, message: _) = error else {
                return XCTFail("Expected the native AppleScript error code")
            }
        }
    }

    @MainActor
    func testDiagnosticsStartsWithoutRequestAndRecoversFromDenial() async {
        let provider = FakeDesktopItemProvider()
        let model = FinderDiagnosticsModel(provider: provider)
        XCTAssertEqual(provider.calls, 0)
        XCTAssertEqual(model.permission, .notRequested)
        provider.operation = { throw FinderReadError.permissionDenied }
        await model.readItems()
        XCTAssertEqual(model.permission, .denied)
        XCTAssertNotNil(model.error)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.isReading)
        provider.operation = { [self.item(name: "Moved", x: 99)] }
        await model.readItems()
        XCTAssertEqual(model.permission, .allowed)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.items.first?.position.x, 99)
        provider.operation = { [self.item(name: "Moved", x: 199)] }
        await model.readItems()
        XCTAssertEqual(model.items.first?.position.x, 199)
        provider.operation = { throw FinderReadError.malformedResponse("bad row") }
        await model.readItems()
        XCTAssertTrue(model.items.isEmpty, "A failed refresh must not display stale item positions")
        XCTAssertNotNil(model.error)
        XCTAssertEqual(model.permission, .allowed, "Parse errors must not claim Automation was denied")
        let unknown = FinderDiagnosticsModel(provider: provider)
        await unknown.readItems()
        XCTAssertEqual(unknown.permission, .unknown)
    }

    @MainActor
    func testOverlappingReadsAreSkippedWhileProviderIsSuspended() async {
        let provider = FakeDesktopItemProvider()
        let started = expectation(description: "Provider started")
        var continuation: CheckedContinuation<[DesktopItem], any Error>?
        provider.operation = {
            try await withCheckedThrowingContinuation {
                continuation = $0
                started.fulfill()
            }
        }
        let model = FinderDiagnosticsModel(provider: provider)
        let first = Task { await model.readItems() }
        let waitResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(waitResult, .completed)
        XCTAssertTrue(model.isReading)
        await model.readItems()
        XCTAssertEqual(provider.calls, 1)
        continuation?.resume(returning: [])
        await first.value
        XCTAssertFalse(model.isReading)
        XCTAssertTrue(model.hasRead)
    }

    func testBuiltAppDeclaresAutomationUsage() {
        let description = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") as? String
        XCTAssertTrue(description?.contains("Finder") == true)
    }

    @MainActor
    private func list(_ items: [NSAppleEventDescriptor]) -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() { descriptor.insert(item, at: index + 1) }
        return descriptor
    }

    @MainActor
    private func row(name: String, path: String, x: NSAppleEventDescriptor, y: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        list([.init(string: name), .init(string: path), x, y])
    }

    private func item(name: String, x: Double) -> DesktopItem {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return DesktopItem(id: url.absoluteString, url: url, displayName: name, position: CGPoint(x: x, y: 10), estimatedIconSize: nil, kind: .file)
    }
}
