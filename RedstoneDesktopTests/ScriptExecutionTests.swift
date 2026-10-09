import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class ScriptFixtureAuthorizer: ScriptAuthorizing {
    var targets: [ScriptTarget] = []
    var approval: ScriptApproval = .once
    var operation: (@MainActor (ScriptTarget) async -> ScriptApproval)?
    func approve(_ target: ScriptTarget) async -> ScriptApproval {
        targets.append(target)
        if let operation { return await operation(target) }
        return approval
    }
}
@MainActor
private final class ScriptFixtureExecutor: ScriptExecuting {
    var targets: [ScriptTarget] = []
    func execute(_ target: ScriptTarget) async throws -> ScriptExecutionResult {
        targets.append(target)
        return ScriptExecutionResult(path: target.url.path, stdout: "fixture", stderr: "", exitCode: 0, duration: 0.1, truncated: false)
    }
}
@MainActor
private final class ScriptFinderFixture: DesktopItemProviding {
    var items: [DesktopItem] = []
    func currentDesktopItems() async throws -> [DesktopItem] { items }
}

@MainActor
private final class ScriptAccessFixture: DesktopScriptAccessChecking {
    var calls = 0
    var error: (any Error)?
    var operation: (@MainActor () async throws -> Void)?
    func checkAccess() async throws {
        calls += 1
        if let operation { try await operation() }
        if let error { throw error }
    }
}

final class ScriptExecutionTests: XCTestCase {
    private func fixture(_ body: String = "printf 'hello\\n'", ext: String = "sh") throws -> (URL, DesktopItem) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("redstone-script-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("space ' quote $() 雪.\(ext)")
        try Data(body.utf8).write(to: url)
        return (root, DesktopItem(id: "fixture", url: url, displayName: url.lastPathComponent, position: .zero, estimatedIconSize: nil, kind: .file))
    }

    func testBackwardCompatibleActionDecodingAndWorldRoundTrip() throws {
        let old = Data(#"{"kind":"output","direction":"north"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CircuitComponent.self, from: old).outputAction, .openOccupant)
        for mode in OutputActionMode.allCases {
            var document = try WorldDocument(legacy: LegacyWorldDocument())
            document.circuit.components[DemoCircuit.output]?.outputAction = mode
            let restored = try JSONDecoder().decode(WorldDocument.self, from: JSONEncoder().encode(document))
            XCTAssertEqual(try restored.restoredWorld().circuit.components[DemoCircuit.output]?.outputAction, mode)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitComponent.self, from: Data(#"{"kind":"output","direction":"north","outputAction":"arbitraryCode"}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(CircuitComponent.self, from: Data(#"{"kind":"output","direction":"north","outputAction":null}"#.utf8)))
    }

    func testTargetValidationInterpreterResolutionAndFingerprint() throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try ScriptTarget.resolve(item)
        XCTAssertEqual(target.interpreter.path, "/bin/sh")
        XCTAssertEqual(target.arguments, ["--", item.url.path])
        XCTAssertEqual(target, try ScriptTarget.resolve(item))
        let link = root.appendingPathComponent("link.zsh")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: item.url)
        let linked = DesktopItem(id: "link", url: link, displayName: "link", position: .zero, estimatedIconSize: nil, kind: .file)
        XCTAssertEqual(try ScriptTarget.resolve(linked), target, "Interpreter comes from resolved file extension")
        try Data("printf changed".utf8).write(to: item.url)
        XCTAssertNotEqual(try ScriptTarget.resolve(item), target)
        for kind in [DesktopItemKind.folder, .application, .alias, .unknown] {
            XCTAssertThrowsError(try ScriptTarget.resolve(DesktopItem(id: "bad", url: item.url, displayName: "bad", position: .zero, estimatedIconSize: nil, kind: kind)))
        }
        let (otherRoot, unsupported) = try fixture(ext: "py")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        XCTAssertThrowsError(try ScriptTarget.resolve(unsupported))
        try Data(repeating: 65, count: 1024 * 1024 + 1).write(to: item.url)
        XCTAssertThrowsError(try ScriptTarget.resolve(item))
        try FileManager.default.removeItem(at: item.url)
        XCTAssertThrowsError(try ScriptTarget.resolve(item))
    }

    @MainActor
    func testRealProcessCapturesOutputExitDurationAndTreatsPathAsSingleArgument() async throws {
        let (root, item) = try fixture("printf 'hello 雪\\n'; printf 'warning\\n' >&2; printf '%s\\n' \"$0\"; pwd; exit 7")
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await ScriptProcess().execute(ScriptTarget.resolve(item))
        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stdout.contains("hello 雪\n"))
        XCTAssertTrue(result.stdout.contains(item.url.path))
        XCTAssertTrue(result.stdout.contains(root.path))
        XCTAssertEqual(result.stderr, "warning\n")
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertFalse(result.truncated)
        for ext in ["command", "zsh"] {
            let (root, item) = try fixture("printf ok", ext: ext)
            defer { try? FileManager.default.removeItem(at: root) }
            let output = try await ScriptProcess().execute(ScriptTarget.resolve(item))
            XCTAssertEqual(output.stdout, "ok")
            XCTAssertEqual(output.exitCode, 0)
        }
    }

    @MainActor
    func testLargeBothStreamsDrainWithBoundedCapture() async throws {
        let (root, item) = try fixture("i=0; while [ \"$i\" -lt 10000 ]; do printf '01234567890123456789'; printf 'abcdefghijklmnopqrst' >&2; i=$((i+1)); done")
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await ScriptProcess(captureLimit: 1024).execute(ScriptTarget.resolve(item))
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertEqual(output.stdout.utf8.count, 1024)
        XCTAssertEqual(output.stderr.utf8.count, 1024)
        XCTAssertTrue(output.truncated)
    }

    @MainActor
    func testPendingProcessDoesNotBlockUIAndCancellationTimeoutRecover() async throws {
        let (root, item) = try fixture("sleep 10")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try ScriptTarget.resolve(item)
        var done = false
        let task = Task { @MainActor in
            defer { done = true }
            return try await ScriptProcess().execute(target)
        }
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(25))
            XCTAssertFalse(done)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must not succeed") } catch is CancellationError {} catch { XCTFail("\(error)") }
        do { _ = try await ScriptProcess(timeout: .milliseconds(80)).execute(target); XCTFail("Timeout must not succeed") } catch ScriptError.timeout {} catch { XCTFail("\(error)") }
        try Data("printf recovered".utf8).write(to: item.url)
        let recovered = try await ScriptProcess().execute(ScriptTarget.resolve(item))
        XCTAssertEqual(recovered.stdout, "recovered")
    }

    @MainActor
    func testTimeoutEscalatesWhenScriptIgnoresTermination() async throws {
        let (root, item) = try fixture("trap '' TERM; while :; do sleep 0.02; done")
        defer { try? FileManager.default.removeItem(at: root) }
        let start = ContinuousClock.now
        do {
            _ = try await ScriptProcess(timeout: .milliseconds(200)).execute(ScriptTarget.resolve(item))
            XCTFail("Ignoring TERM must not bypass the timeout")
        } catch ScriptError.timeout {} catch { XCTFail("\(error)") }
        XCTAssertLessThan(start.duration(to: .now), .seconds(5))
    }

    @MainActor
    func testAuthorizationOnceAlwaysDenialAndRevocation() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let suite = "redstone-script-test-\(UUID())"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let store = ActionAuthorizationStore(preferences: prefs)
        let action = ExecuteScriptAction(executor: executor, authorizer: authorizer, store: store)
        func perform() async -> ScriptActionOutcome { await action.perform(occupancy: .occupied(item), isCurrent: { true }, refresh: { .occupied(item) }) }
        authorizer.approval = .deny
        let denied = await perform()
        XCTAssertNil(denied.result)
        XCTAssertTrue(executor.targets.isEmpty)
        authorizer.approval = .once
        _ = await perform(); _ = await perform()
        XCTAssertEqual(authorizer.targets.count, 3)
        XCTAssertEqual(executor.targets.count, 2)
        authorizer.approval = .always
        _ = await perform(); _ = await perform()
        XCTAssertEqual(authorizer.targets.count, 4)
        let target = try ScriptTarget.resolve(item)
        XCTAssertTrue(ActionAuthorizationStore(preferences: prefs).contains(target))
        try Data("printf changed".utf8).write(to: item.url)
        _ = await perform()
        XCTAssertEqual(authorizer.targets.count, 5, "Edited script needs new approval")
        store.revokeAll()
        XCTAssertFalse(ActionAuthorizationStore(preferences: prefs).contains(target))
    }

    @MainActor
    func testMissingAmbiguousMovedChangedAndStaleTargetsNeverExecute() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let action = ExecuteScriptAction(executor: executor, authorizer: authorizer, store: ActionAuthorizationStore())
        for occupancy in [DesktopOccupancyState.empty, .ambiguous([item, item]), .unavailable("Denied")] {
            let result = await action.perform(occupancy: occupancy, isCurrent: { true }, refresh: { .occupied(item) })
            XCTAssertNil(result.result)
        }
        XCTAssertTrue(authorizer.targets.isEmpty)
        let moved = await action.perform(occupancy: .occupied(item), isCurrent: { true }, refresh: { .empty })
        XCTAssertTrue(moved.message.contains("changed"))
        let edited = await action.perform(occupancy: .occupied(item), isCurrent: { true }, refresh: {
            try? Data("printf replaced".utf8).write(to: item.url)
            return .occupied(item)
        })
        XCTAssertTrue(edited.message.contains("changed"))
        var current = true
        authorizer.operation = { _ in current = false; return .always }
        let stale = await action.perform(occupancy: .occupied(item), isCurrent: { current }, refresh: { .occupied(item) })
        XCTAssertNil(stale.result)
        XCTAssertTrue(executor.targets.isEmpty)
    }

    @MainActor
    func testNativePromptCancellationClosesWithoutApproval() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = try ScriptTarget.resolve(item)
        let presenter = ScriptAuthorizationPresenter()
        let task = Task { await presenter.approve(target) }
        // Cancel before presentation; no visible owner window or app activation in automated tests.
        task.cancel()
        let approval = await task.value
        XCTAssertEqual(approval, .deny)
        let host = NSHostingView(rootView: ScriptConfirmationView(target: target, complete: { _ in }))
        host.frame = CGRect(x: 0, y: 0, width: 560, height: 310)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 560)
    }

    @MainActor
    func testAppOutputConfigurationPersistenceLocksAndActualActionDispatch() async throws {
        let (root, fixtureItem) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 640), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor(), opener = FixtureItemOpener()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        XCTAssertTrue(state.configureOutput(at: DemoCircuit.repeaterOutput, mode: .executeOccupant))
        XCTAssertEqual(state.library.world(id: state.selectedWorldID)?.circuit.components[DemoCircuit.repeaterOutput]?.outputAction, .executeOccupant)
        XCTAssertFalse(state.configureOutput(at: DemoCircuit.button, mode: .executeOccupant))
        provider.items = [DesktopItem(id: fixtureItem.id, url: fixtureItem.url, displayName: fixtureItem.displayName,
            position: CGPoint(x: 480, y: 160), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        state.toggleDesktopWorld()
        XCTAssertFalse(state.configureOutput(at: DemoCircuit.repeaterOutput, mode: .none))
        state.handleCircuitClick(DemoCircuit.repeaterButton)
        await state.activationTask?.value
        for _ in 0..<8 { state.advanceCircuitTick(); XCTAssertTrue(executor.targets.isEmpty) }
        state.advanceCircuitTick()
        await state.activationTask?.value
        XCTAssertEqual(executor.targets.count, 1)
        XCTAssertTrue(opener.urls.isEmpty)
        XCTAssertEqual(state.lastScriptResult?.stdout, "fixture")
        for _ in 0..<30 { state.advanceCircuitTick() }
        XCTAssertEqual(executor.targets.count, 1)
        XCTAssertTrue(state.finderMappings.count == 1)
        XCTAssertTrue(state.desktopController?.scene.childNode(withName: "finder-markers")?.children.isEmpty == true)
    }
    @MainActor
    func testStopDesktopInvalidatesPendingAuthorizationAndDoesNotRememberApproval() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        XCTAssertTrue(state.configureOutput(at: DemoCircuit.output, mode: .executeOccupant))
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        let requested = expectation(description: "Approval pending")
        var reply: CheckedContinuation<ScriptApproval, Never>?
        authorizer.operation = { _ in await withCheckedContinuation { reply = $0; requested.fulfill() } }
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [requested], timeout: 2)
        state.toggleDesktopWorld() // Stop while the authorizer is still suspended.
        state.toggleDesktopWorld() // A fresh runtime at the same coordinates.
        reply?.resume(returning: .always)
        await pending?.value
        XCTAssertTrue(executor.targets.isEmpty)
        XCTAssertFalse(state.actionAuthorizations.contains(try ScriptTarget.resolve(item)))
        XCTAssertNil(state.lastScriptResult)
    }

    @MainActor
    func testMenuAssignmentInvalidatesPendingAuthorizationAndDoesNotRememberApproval() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        XCTAssertTrue(state.configureOutput(at: DemoCircuit.output, mode: .executeOccupant))
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        let requested = expectation(description: "Approval pending")
        var reply: CheckedContinuation<ScriptApproval, Never>?
        authorizer.operation = { _ in await withCheckedContinuation { reply = $0; requested.fulfill() } }
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [requested], timeout: 2)
        XCTAssertTrue(state.assignDesktopAreaFromMenu(state.library.activeAreaID))
        XCTAssertFalse(state.isDesktopWorldEnabled)
        state.setDesktopRunning(true) // A fresh runtime at the same coordinates.
        reply?.resume(returning: .always)
        await pending?.value
        XCTAssertTrue(executor.targets.isEmpty)
        XCTAssertFalse(state.actionAuthorizations.contains(try ScriptTarget.resolve(item)))
        XCTAssertNil(state.lastScriptResult)
    }

    @MainActor
    func testPauseSimulationInvalidatesPendingAuthorizationWithoutApprovalReplay() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        XCTAssertTrue(state.configureOutput(at: DemoCircuit.output, mode: .executeOccupant))
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        let requested = expectation(description: "Approval pending")
        var reply: CheckedContinuation<ScriptApproval, Never>?
        authorizer.operation = { _ in await withCheckedContinuation { reply = $0; requested.fulfill() } }
        state.toggleDesktopWorld()
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [requested], timeout: 2)
        state.setSimulationPaused(true)
        state.setSimulationPaused(false)
        reply?.resume(returning: .always)
        await pending?.value
        XCTAssertTrue(executor.targets.isEmpty)
        XCTAssertFalse(state.actionAuthorizations.contains(try ScriptTarget.resolve(item)))
        XCTAssertNil(state.lastScriptResult)
        state.advanceCircuitTick()
        XCTAssertNil(state.activationTask)
        XCTAssertTrue(state.isDesktopWorldEnabled)
    }

    func testAutomaticRoutingHonorsSupportedExtensionsKindsAndExplicitModes() {
        func item(_ name: String, kind: DesktopItemKind = .file, remote: Bool = false) -> DesktopItem {
            DesktopItem(id: name, url: remote ? URL(string: "https://example.com/\(name)")! : URL(fileURLWithPath: "/tmp/\(name)"),
                displayName: name, position: .zero, estimatedIconSize: nil, kind: kind)
        }
        let automatic = ScriptOutputSettings(runScriptsOpenOtherItems: true)
        for name in ["hello.sh", "hello.command", "hello.zsh", "UPPER.SH"] {
            let occupancy = DesktopOccupancyState.occupied(item(name))
            XCTAssertEqual(automatic.action(configured: .openOccupant, occupancy: occupancy), .executeOccupant)
            XCTAssertEqual(ScriptOutputSettings().action(configured: .openOccupant, occupancy: occupancy), .openOccupant)
            XCTAssertEqual(automatic.action(configured: .none, occupancy: occupancy), .none)
        }
        for occupancy in [DesktopOccupancyState.empty, .unavailable("Denied"), .ambiguous([item("a.sh"), item("b.sh")]),
                          .occupied(item("readme.txt")), .occupied(item("hello.py")), .occupied(item("remote.sh", remote: true)),
                          .occupied(item("folder.sh", kind: .folder)), .occupied(item("app.sh", kind: .application)),
                          .occupied(item("alias.sh", kind: .alias)), .occupied(item("unknown.sh", kind: .unknown))] {
            XCTAssertEqual(automatic.action(configured: .openOccupant, occupancy: occupancy), .openOccupant)
            XCTAssertEqual(automatic.action(configured: .executeOccupant, occupancy: occupancy), .executeOccupant)
        }
    }

    func testNativeDirectoryAccessCheckUsesTemporaryFolderWithoutReadingOrWritingFiles() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try Data(contentsOf: item.url)
        try await DesktopScriptAccess(directory: root).checkAccess()
        XCTAssertEqual(try Data(contentsOf: item.url), before)
        for directory in [root.appendingPathComponent("missing"), item.url] {
            do { try await DesktopScriptAccess(directory: directory).checkAccess(); XCTFail("Invalid directory must fail") }
            catch { /* Reported to settings; never a successful permission check. */ }
        }
    }

    @MainActor
    func testPermissionRequestsAreExplicitSerializedAndRetryableAfterDenial() async throws {
        let access = ScriptAccessFixture()
        let state = AppState(desktopScriptAccess: access)
        defer { state.shutdown() }
        XCTAssertEqual(access.calls, 0, "Startup must not ask for Desktop-folder access")
        let started = expectation(description: "Access suspended")
        var reply: CheckedContinuation<Void, any Error>?
        access.operation = { try await withCheckedThrowingContinuation { reply = $0; started.fulfill() } }
        XCTAssertTrue(state.configureOutput(at: DemoCircuit.output, mode: .executeOccupant))
        await fulfillment(of: [started], timeout: 2)
        state.requestDesktopScriptAccess(retry: true)
        state.setRunScriptsOpenOtherItems(true)
        XCTAssertEqual(access.calls, 1, "Inspector/settings share one access attempt")
        reply?.resume(throwing: CocoaError(.fileReadNoPermission))
        await state.desktopScriptAccessTask?.value
        XCTAssertTrue(state.desktopScriptAccessStatus.contains("failed"))
        state.setRunScriptsOpenOtherItems(false); state.setRunScriptsOpenOtherItems(true)
        await state.desktopScriptAccessTask?.value
        XCTAssertEqual(access.calls, 1, "Automatic retries must not repeatedly prompt after denial")
        access.operation = nil
        state.requestDesktopScriptAccess(retry: true)
        await state.desktopScriptAccessTask?.value
        XCTAssertEqual(access.calls, 2)
        XCTAssertTrue(state.desktopScriptAccessStatus.contains("succeeded"))
    }

    @MainActor
    func testRoutingPreferencePersistsSeparatelyWithReadFreeRestorationAndInvalidDataFallback() throws {
        let suite = "redstone-routing-test-\(UUID())"
        let prefs = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { prefs.removePersistentDomain(forName: suite) }
        let access = ScriptAccessFixture()
        let first = AppState(desktopScriptAccess: access, preferences: prefs)
        let library = first.library
        first.setRunScriptsOpenOtherItems(true)
        XCTAssertEqual(first.library, library, "Global policy must not rewrite worlds or their actions")
        first.shutdown()
        let restored = AppState(desktopScriptAccess: access, preferences: prefs)
        defer { restored.shutdown() }
        XCTAssertTrue(restored.scriptOutputSettings.runScriptsOpenOtherItems)
        XCTAssertFalse(restored.isDesktopWorldEnabled)
        XCTAssertEqual(access.calls, 0, "Restoring an opt-in preference must not read Desktop")
        prefs.set(Data("{\"runScriptsOpenOtherItems\":\"bad\"}".utf8), forKey: "scriptOutputSettings")
        let invalid = AppState(desktopScriptAccess: access, preferences: prefs)
        defer { invalid.shutdown() }
        XCTAssertFalse(invalid.scriptOutputSettings.runScriptsOpenOtherItems)
        XCTAssertEqual(access.calls, 0)
        let host = NSHostingView(rootView: AppSettingsView(appState: invalid))
        host.frame = CGRect(x: 0, y: 0, width: 560, height: 400)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 560)
    }

    @MainActor
    func testDefaultOutputAutomaticallyExecutesScriptAndOpensReplacementFolder() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor(), opener = FixtureItemOpener()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), itemOpener: opener, scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        state.setRunScriptsOpenOtherItems(true)
        state.toggleDesktopWorld()
        func press() async {
            state.handleCircuitClick(DemoCircuit.button)
            await state.activationTask?.value
            state.advanceCircuitTick()
            await state.activationTask?.value
        }
        await press()
        XCTAssertEqual(executor.targets.count, 1)
        XCTAssertEqual(authorizer.targets.count, 1, "Automatic routing still requires script approval")
        XCTAssertTrue(opener.urls.isEmpty)
        for _ in 0..<21 { state.advanceCircuitTick() }
        let folder = root.appendingPathComponent("harmless folder")
        provider.items = [DesktopItem(id: "folder", url: folder, displayName: "folder", position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .folder)]
        await press()
        XCTAssertEqual(opener.urls, [folder])
        XCTAssertEqual(executor.targets.count, 1)
        let power = state.simulator.power
        state.setRunScriptsOpenOtherItems(false)
        XCTAssertEqual(state.simulator.power, power, "Policy changes must not reset power or replay a held Output")
        XCTAssertEqual(opener.urls.count, 1)
    }

    @MainActor
    func testChangingAutomaticPolicyCancelsPendingApprovalWithoutRunningOrRemembering() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        state.setRunScriptsOpenOtherItems(true)
        state.toggleDesktopWorld()
        let requested = expectation(description: "Approval pending")
        var reply: CheckedContinuation<ScriptApproval, Never>?
        authorizer.operation = { _ in await withCheckedContinuation { reply = $0; requested.fulfill() } }
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [requested], timeout: 2)
        state.setRunScriptsOpenOtherItems(false)
        XCTAssertNotNil(state.activationTask, "Keep the slot until the old task returns")
        reply?.resume(returning: .always)
        await pending?.value
        XCTAssertTrue(executor.targets.isEmpty)
        XCTAssertFalse(state.actionAuthorizations.contains(try ScriptTarget.resolve(item)))
        XCTAssertNil(state.lastScriptResult)
        XCTAssertNil(state.activationTask)
    }

    @MainActor
    func testInputDuringScriptApprovalDoesNotReplayAfterApproval() async throws {
        let (root, item) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let screen = ScreenDescriptor(id: "fixture", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let provider = ScriptFinderFixture(), authorizer = ScriptFixtureAuthorizer(), executor = ScriptFixtureExecutor()
        let state = AppState(screenProviding: { screen }, clickEventMonitoring: FakeGlobalMouseEventMonitor(),
            finderDiagnostics: FinderDiagnosticsModel(provider: provider),
            desktopInteractionAssessment: { _ in DesktopInteractionAssessment(rejectionReason: nil, details: "fixture") },
            tickScheduler: ManualCircuitTickScheduler(), scriptExecutor: executor, scriptAuthorizer: authorizer,
            finderReferenceProviding: { screen })
        defer { state.shutdown() }
        provider.items = [DesktopItem(id: item.id, url: item.url, displayName: item.displayName,
            position: CGPoint(x: 480, y: 256), estimatedIconSize: nil, kind: .file)]
        await state.finderDiagnostics.readItems()
        state.setRunScriptsOpenOtherItems(true)
        state.toggleDesktopWorld()
        let requested = expectation(description: "Approval pending")
        var reply: CheckedContinuation<ScriptApproval, Never>?
        authorizer.operation = { _ in await withCheckedContinuation { reply = $0; requested.fulfill() } }
        state.handleCircuitClick(DemoCircuit.button)
        await state.activationTask?.value
        state.advanceCircuitTick()
        let pending = state.activationTask
        await fulfillment(of: [requested], timeout: 2)
        for _ in 0..<10 { state.handleCircuitClick(DemoCircuit.lever) }
        XCTAssertTrue(state.lastActionResult.contains("approval or execution is busy"))
        reply?.resume(returning: .always)
        await pending?.value
        XCTAssertEqual(executor.targets.count, 1)
        for _ in 0..<25 { state.advanceCircuitTick() }
        await state.activationTask?.value
        XCTAssertFalse(state.simulator.activeLevers.contains(DemoCircuit.lever))
        XCTAssertEqual(executor.targets.count, 1)
        XCTAssertNil(state.activationTask)
    }

    @MainActor
    func testShutdownRejectsLateAccessResultAndCancelledCheckDoesNotStart() async {
        let access = ScriptAccessFixture(), neverStarted = ScriptAccessFixture()
        let state = AppState(desktopScriptAccess: neverStarted)
        state.requestDesktopScriptAccess()
        let notStarted = state.desktopScriptAccessTask
        state.shutdown()
        await notStarted?.value
        XCTAssertEqual(neverStarted.calls, 0)
        XCTAssertEqual(state.desktopScriptAccessStatus, "Desktop access check cancelled.")
        let pendingState = AppState(desktopScriptAccess: access)
        let requested = expectation(description: "Folder access pending")
        var reply: CheckedContinuation<Void, any Error>?
        access.operation = { try await withCheckedThrowingContinuation { reply = $0; requested.fulfill() } }
        pendingState.requestDesktopScriptAccess()
        let pending = pendingState.desktopScriptAccessTask
        await fulfillment(of: [requested], timeout: 2)
        pendingState.shutdown()
        reply?.resume()
        await pending?.value
        XCTAssertEqual(pendingState.desktopScriptAccessStatus, "Desktop access check cancelled.")
        XCTAssertNil(pendingState.desktopScriptAccessTask)
    }

}
