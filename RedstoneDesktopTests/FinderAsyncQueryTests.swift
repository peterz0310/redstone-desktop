import Foundation
import XCTest
@testable import RedstoneDesktop

final class FinderAsyncQueryTests: XCTestCase {
    @MainActor
    func testSystemScriptOutputPreservesEscapesUnicodeControlsPositionsAndSize() async throws {
        // Only a constant, harmless fixture; no real Finder, permissions or file mutations.
        let source = #"return {64, 64, {{"Quotes \" slash \\ 雪" & tab & linefeed & "end", "/tmp/redstone-async-fixture", -120, 8.5}}}"#
        let data = try await FinderScriptProcess.execute(source: source)
        let snapshot = try FinderDesktopItemProvider.parseSnapshot(FinderScriptOutput.descriptor(from: data))
        XCTAssertEqual(snapshot.viewSettings?.iconSize, 64)
        XCTAssertTrue(snapshot.layoutIsStable)
        XCTAssertEqual(snapshot.items.first?.displayName, "Quotes \" slash \\ 雪\t\nend")
        XCTAssertEqual(snapshot.items.first?.url.path, "/tmp/redstone-async-fixture")
        XCTAssertEqual(snapshot.items.first?.position.x, -120)
        XCTAssertEqual(snapshot.items.first?.position.y, 8.5)
        let missing = try FinderScriptOutput.descriptor(from: Data("{missing value, missing value, {}}".utf8))
        XCTAssertNil(try FinderDesktopItemProvider.parseSnapshot(missing).viewSettings)
    }

    func testQueryOutputIsStrictlyBoundedDataRatherThanExecutableText() throws {
        for text in ["return {}", "do shell script \"anything\"", "{1,}", "{1} trailing", "{nan}", "{1e999}", "{\"bad\\q\"}", String(repeating: "{", count: 12) + String(repeating: "}", count: 12)] {
            XCTAssertThrowsError(try FinderScriptOutput.descriptor(from: Data(text.utf8)))
        }
        XCTAssertThrowsError(try FinderScriptOutput.descriptor(from: Data([255])))
        XCTAssertThrowsError(try FinderScriptOutput.descriptor(from: Data(repeating: 32, count: 4 * 1024 * 1024 + 1)))
        let numeric = try FinderScriptOutput.descriptor(from: Data("{-1.25E+2, 6e-1}".utf8))
        XCTAssertEqual(numeric.atIndex(1)?.doubleValue, -125)
        XCTAssertEqual(numeric.atIndex(2)?.doubleValue, 0.6)
    }

    @MainActor
    func testRealScriptDelayLeavesMainActorFreeToProcessPointerAndUITasks() async throws {
        var completed = false
        let query = Task { @MainActor in
            defer { completed = true }
            return try await FinderScriptProcess.execute(source: "delay 0.4\nreturn {missing value, missing value, {}}")
        }
        var updatesWhilePending = 0
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(25))
            XCTAssertFalse(completed, "UI work must run while the real script is still pending")
            updatesWhilePending += 1
        }
        XCTAssertEqual(updatesWhilePending, 6)
        let data = try await query.value
        XCTAssertTrue(try FinderDesktopItemProvider.parseSnapshot(FinderScriptOutput.descriptor(from: data)).items.isEmpty)
    }

    @MainActor
    func testNativeErrorsAndPermissionDenialRemainDistinct() async throws {
        do {
            _ = try await FinderScriptProcess.execute(source: #"error "Fixture failure" number -1700"#)
            XCTFail("Expected fixture error")
        } catch let error as FinderReadError {
            guard case .scriptFailure(code: -1700, message: _) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        do {
            _ = try await FinderScriptProcess.execute(source: #"error "Fixture denial" number -1743"#)
            XCTFail("Expected denial")
        } catch let error as FinderReadError { XCTAssertEqual(error, .permissionDenied) }
    }

    @MainActor
    func testCancellationAndTimeoutEndPendingSystemQueryWithoutPublishingResult() async throws {
        let query = Task { @MainActor in try await FinderScriptProcess.execute(source: "delay 10\nreturn {}") }
        try await Task.sleep(for: .milliseconds(80))
        query.cancel()
        do { _ = try await query.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            _ = try await FinderScriptProcess.execute(source: "delay 10\nreturn {}", timeout: .milliseconds(80))
            XCTFail("Expected timeout")
        } catch let error as FinderReadError {
            guard case .scriptFailure(code: -1712, message: _) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        // A cancelled/expired process must not poison the next query.
        let result = try await FinderScriptProcess.execute(source: "return {}")
        XCTAssertEqual(try FinderScriptOutput.descriptor(from: result).numberOfItems, 0)
    }

    @MainActor
    func testExcessiveSystemOutputIsRefusedWithoutPipeDeadlock() async throws {
        do {
            _ = try await FinderScriptProcess.execute(source: "return \"" + String(repeating: "x", count: 32_000) + "\"", outputLimit: 128)
            XCTFail("Expected output bound refusal")
        } catch let error as FinderReadError {
            guard case .malformedResponse = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}
