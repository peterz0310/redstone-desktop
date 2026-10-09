import AppKit
import SwiftUI
import XCTest
@testable import RedstoneDesktop

@MainActor
private final class RelaunchSpy: AppRelaunching {
    var calls = 0
    var fails = false
    func relaunch() async throws { calls += 1; if fails { throw MaintenanceError(message: "Fixture launch failure") } }
}

final class MaintenanceTests: XCTestCase {
    private func fixture() throws -> (URL, LibraryMaintenanceStore, WorldLibraryStore, WorldLibraryDocument) {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        let maintenance = LibraryMaintenanceStore(root: directory.appendingPathComponent("Support"), backups: directory.appendingPathComponent("Backups"))
        let store = WorldLibraryStore(fileURL: maintenance.root.appendingPathComponent("library.json"), legacyFileURL: maintenance.root.appendingPathComponent("world.json"))
        let library = try WorldLibraryDocument(legacy: LegacyWorldDocument())
        try store.save(library)
        return (directory, maintenance, store, library)
    }
    @MainActor
    func testRevealCreatesMissingConfiguredFolderBeforeOpeningAndPreservesData() throws {
        let (directory, maintenance, store, library) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(libraryStore: store, maintenanceStore: maintenance)
        defer { state.shutdown() }
        let before = try Data(contentsOf: store.fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.backups.path))
        var opened: [URL] = []
        state.revealBackupsFolder { folder in
            opened.append(folder)
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
            return true
        }
        XCTAssertEqual(opened, [maintenance.backups])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: maintenance.backups.path), [])
        XCTAssertEqual(state.backupRevealStatus, "")
        XCTAssertEqual(state.library, library)
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        XCTAssertNil(state.lastBackup)
        XCTAssertFalse(state.isMaintenanceLocked)
        try Data("existing backup".utf8).write(to: maintenance.backups.appendingPathComponent("keep.txt"))
        state.revealBackupsFolder { folder in opened.append(folder); return true }
        XCTAssertEqual(opened.count, 2)
        XCTAssertEqual(try String(contentsOf: maintenance.backups.appendingPathComponent("keep.txt"), encoding: .utf8), "existing backup")
    }
    @MainActor
    func testRevealReportsFolderCreationAndFinderFailures() throws {
        let (directory, maintenance, store, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(libraryStore: store, maintenanceStore: maintenance)
        defer { state.shutdown() }
        try Data("not a directory".utf8).write(to: maintenance.backups)
        var called = false
        state.revealBackupsFolder { _ in called = true; return true }
        XCTAssertFalse(called)
        XCTAssertTrue(state.backupRevealStatus.contains("Couldn’t open the backups folder"))
        XCTAssertEqual(try String(contentsOf: maintenance.backups, encoding: .utf8), "not a directory")
        try FileManager.default.removeItem(at: maintenance.backups)
        state.revealBackupsFolder { _ in false }
        XCTAssertTrue(state.backupRevealStatus.contains("Couldn’t open Finder"))
        XCTAssertTrue(state.backupRevealStatus.contains(maintenance.backups.path))
        state.revealBackupsFolder { _ in true }
        XCTAssertEqual(state.backupRevealStatus, "")
    }

    func testResetPreservesValidatedLibraryLegacyPreferencesAndUnknownFilesAndNoMigrationReplay() throws {
        let (directory, maintenance, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try JSONEncoder().encode(LegacyWorldDocument())
        try legacy.write(to: store.legacyFileURL)
        try Data("preserved".utf8).write(to: maintenance.root.appendingPathComponent("owner-note.txt"))
        var preferences: [String: Any] = ["setupCompleted": true, "approvedScripts": ["fixture"], "audioSettings": Data([1, 2])]
        let backup = try maintenance.reset(library: library, preferences: preferences, clearPreferences: { preferences = [:] }, restorePreferences: {})
        XCTAssertTrue(preferences.isEmpty)
        let saved = WorldLibraryStore(fileURL: backup.appendingPathComponent("library.json"), legacyFileURL: backup.appendingPathComponent("unused.json"))
        XCTAssertEqual(try saved.load(), library)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Support/world.json")), legacy)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Support/owner-note.txt")), Data("preserved".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.legacyFileURL.path))
        let fresh = try XCTUnwrap(store.load())
        XCTAssertEqual(fresh.worlds.count, 1); XCTAssertEqual(fresh.areas.count, 1)
        XCTAssertTrue(fresh.worlds[0].circuit.components.isEmpty)
        XCTAssertEqual(fresh.worlds[0].terrainProfile, .procedural)
        XCTAssertNotEqual(fresh.activeAreaID, library.activeAreaID)
        XCTAssertEqual(try store.load(), fresh)
    }
    func testManagedImportCacheMovesToBackupAndExternalSourceIsUntouched() throws {
        let (directory, maintenance, _, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SyntheticJava.zip")
        let before = try Data(contentsOf: source)
        let imported = try JavaTextureImporter.importTextures(from: source, cacheRoot: maintenance.root.appendingPathComponent("ImportedTextures"))
        let backup = try maintenance.reset(library: library, preferences: ["assetPackPath": imported.folder.path], clearPreferences: {}, restorePreferences: {})
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.appendingPathComponent("Support/ImportedTextures/" + imported.record.id.uuidString + "/import.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.root.appendingPathComponent("ImportedTextures").path))
    }
    func testBackupOrValidationFailureLeavesAuthoritativeDataUntouched() throws {
        let (directory, maintenance, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try Data(contentsOf: store.fileURL)
        try Data("block".utf8).write(to: maintenance.backups)
        XCTAssertThrowsError(try maintenance.reset(library: library, preferences: [:], clearPreferences: { XCTFail("Must not clear") }, restorePreferences: {}))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }
    func testFreshInstallRenameFailureRollsBackWithoutChangingPreferences() throws {
        let (directory, base, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var maintenance = base, calls = 0
        maintenance.move = { source, destination in
            calls += 1
            if calls == 2 { throw MaintenanceError(message: "Injected staged install failure") }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        XCTAssertThrowsError(try maintenance.reset(library: library, preferences: [:], clearPreferences: { XCTFail("Must not clear") }, restorePreferences: {}))
        XCTAssertEqual(try store.load(), library)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.backups.appendingPathComponent("reset-in-progress.json").path))
    }
    func testPreferenceFailureRollsBackDirectoryAndRestoresPreferences() throws {
        let (directory, maintenance, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var restored = false
        XCTAssertThrowsError(try maintenance.reset(library: library, preferences: ["setupCompleted": true],
            clearPreferences: { throw MaintenanceError(message: "Preference fixture failure") }, restorePreferences: { restored = true }))
        XCTAssertTrue(restored); XCTAssertEqual(try store.load(), library)
    }
    func testSymbolicLinksAndUnmanagedImportDirectoriesAreRefused() throws {
        let (directory, maintenance, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let external = directory.appendingPathComponent("external.json")
        try Data("external".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: store.legacyFileURL, withDestinationURL: external)
        XCTAssertThrowsError(try maintenance.reset(library: library, preferences: [:], clearPreferences: {}, restorePreferences: {}))
        XCTAssertEqual(try Data(contentsOf: external), Data("external".utf8))
        try FileManager.default.removeItem(at: store.legacyFileURL)
        try FileManager.default.createDirectory(at: maintenance.root.appendingPathComponent("ImportedTextures/not-managed"), withIntermediateDirectories: true)
        XCTAssertThrowsError(try maintenance.reset(library: library, preferences: [:], clearPreferences: {}, restorePreferences: {}))
        XCTAssertEqual(try store.load(), library)
    }
    func testInterruptedResetJournalRestoresBeforeFreshLibraryCanLoad() throws {
        let (directory, maintenance, store, library) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID().uuidString, backup = maintenance.backups.appendingPathComponent("Interrupted-" + id)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["setupCompleted": true], format: .xml, options: 0).write(to: backup.appendingPathComponent("preferences.plist"))
        try FileManager.default.moveItem(at: maintenance.root, to: backup.appendingPathComponent("Support"))
        try store.save(WorldLibraryDocument())
        try JSONSerialization.data(withJSONObject: ["root": maintenance.root.path, "backup": backup.lastPathComponent, "id": id])
            .write(to: maintenance.backups.appendingPathComponent("reset-in-progress.json"))
        var restored: [String: Any] = [:]
        try maintenance.recoverInterruptedReset { restored = $0 }
        XCTAssertEqual(try store.load(), library)
        XCTAssertEqual(restored["setupCompleted"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: maintenance.backups.appendingPathComponent("reset-in-progress.json").path))
    }
    @MainActor
    func testAppResetDiscardsOldWriterAndFreshInstanceHasSetupEmptyWorldAndStopped() async throws {
        let (directory, maintenance, store, _) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "maintenance-test-" + UUID().uuidString, prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { prefs.removePersistentDomain(forName: domain) }
        prefs.set(true, forKey: "setupCompleted"); prefs.set(["fixture"], forKey: "approvedScripts")
        let launcher = RelaunchSpy()
        let state = AppState(clickEventMonitoring: FakeGlobalMouseEventMonitor(), tickScheduler: ManualCircuitTickScheduler(),
            libraryStore: store, preferences: prefs, maintenanceStore: maintenance, preferencesDomain: domain, relauncher: launcher)
        defer { state.shutdown() }
        XCTAssertFalse(state.needsSetup)
        state.setDesktopRunning(true)
        let result = await state.startOver()
        XCTAssertTrue(result); XCTAssertEqual(launcher.calls, 1)
        XCTAssertFalse(state.isDesktopWorldEnabled); XCTAssertTrue(state.isMaintenanceLocked)
        XCTAssertFalse(state.createWorld(name: "Old callback", generation: WorldGenerationSettings(seed: 42)))
        let fresh = try XCTUnwrap(store.load())
        state.shutdown(); state.saveWorldNow()
        XCTAssertEqual(try store.load(), fresh)
        let restored = AppState(libraryStore: store, preferences: prefs)
        defer { restored.shutdown() }
        XCTAssertTrue(restored.needsSetup)
        XCTAssertTrue(restored.editorWorld.circuit.components.isEmpty)
        XCTAssertFalse(restored.isDesktopWorldEnabled)
        XCTAssertNil(prefs.object(forKey: "approvedScripts"))
    }
    @MainActor
    func testRelaunchFailureLeavesFreshDataAndOldInstanceLockedForManualReopen() async throws {
        let (directory, maintenance, store, _) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "maintenance-test-" + UUID().uuidString, prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { prefs.removePersistentDomain(forName: domain) }
        let launcher = RelaunchSpy(); launcher.fails = true
        let state = AppState(libraryStore: store, preferences: prefs, maintenanceStore: maintenance, preferencesDomain: domain, relauncher: launcher)
        defer { state.shutdown() }
        let result = await state.startOver()
        XCTAssertFalse(result); XCTAssertTrue(state.isMaintenanceLocked)
        XCTAssertTrue(state.maintenanceStatus.contains("relaunch failed"))
        XCTAssertTrue(try XCTUnwrap(store.load()).worlds[0].circuit.components.isEmpty)
    }
    @MainActor
    func testSetupSkipCompletionRestoresWithoutPermissionReadOrStartAndNativeViewsHost() async throws {
        let domain = "setup-test-" + UUID().uuidString, prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { prefs.removePersistentDomain(forName: domain) }
        let state = AppState(preferences: prefs); defer { state.shutdown() }
        XCTAssertTrue(state.needsSetup)
        let host = NSHostingView(rootView: SetupWizardView(appState: state))
        XCTAssertGreaterThanOrEqual(host.fittingSize.width, 600)
        let settings = NSHostingView(rootView: AppSettingsView(appState: state))
        XCTAssertEqual(settings.fittingSize.width, 700)
        state.finishSetup()
        let next = AppState(preferences: prefs); defer { next.shutdown() }
        XCTAssertFalse(next.needsSetup)
        XCTAssertFalse(next.isDesktopWorldEnabled)
        XCTAssertFalse(next.finderDiagnostics.hasRead)
        XCTAssertNil(next.desktopScriptAccessTask)
    }
    func testExportRoundTripExcludesFinderPathsApprovalsAndRuntime() throws {
        let library = try WorldLibraryDocument(legacy: LegacyWorldDocument())
        let data = try LibraryExportDocument(library: library).encodedData()
        XCTAssertEqual(try JSONDecoder().decode(WorldLibraryDocument.self, from: data), library)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("approvedScripts")); XCTAssertFalse(text.contains("finderItems"))
        try library.validate()
    }
}

@MainActor
private final class MaintenanceReadProvider: DesktopItemProviding {
    var calls = 0
    var cancelled = false
    func currentDesktopItems() async throws -> [DesktopItem] {
        calls += 1
        do { try await Task.sleep(for: .seconds(30)) } catch { cancelled = true; throw error }
        return []
    }
}

extension MaintenanceTests {
    @MainActor
    func testSuspendingFinderCancelsInFlightReadAndBlocksNewReadsUntilRecovery() async {
        let provider = MaintenanceReadProvider(), finder = FinderDiagnosticsModel(provider: provider)
        let read = Task { await finder.readItems() }
        while provider.calls == 0 { await Task.yield() }
        await finder.suspendReads()
        let result = await read.value
        XCTAssertFalse(result); XCTAssertTrue(provider.cancelled); XCTAssertFalse(finder.hasRead)
        let blocked = await finder.readItems()
        XCTAssertFalse(blocked); XCTAssertEqual(provider.calls, 1)
        finder.resumeReads()
        let next = Task { await finder.readItems() }
        while provider.calls < 2 { await Task.yield() }
        next.cancel(); _ = await next.value
        XCTAssertEqual(provider.calls, 2)
    }
    @MainActor
    func testMaintenanceWaitQuiescesCancelledImportAndNeverPublishesOrRecreatesCache() async throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let assets = AssetLibrary(importCacheRoot: directory)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SyntheticJava.zip")
        let request = Task { await assets.importJava(source) }
        while !assets.isLoading { await Task.yield() }
        let stop = Task { await assets.suspendForMaintenance() }
        stop.cancel() // must still yield while the cache writer finishes
        await stop.value; await request.value
        XCTAssertNil(assets.pack); XCTAssertNil(assets.importRecord)
        XCTAssertFalse(assets.isLoading)
        let folders = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(folders.isEmpty)
        await assets.importJava(source)
        XCTAssertNil(assets.pack)
        assets.resumeAfterMaintenance(); await assets.importJava(source)
        XCTAssertNotNil(assets.pack)
    }
    @MainActor
    func testAudioIdlesAfterEffectAndRestartsWithoutSpeakerOutput() async throws {
        let engine = try AudioEngine(offline: true, idleDelay: .milliseconds(30))
        defer { engine.stop() }
        engine.play(.buttonPress)
        XCTAssertTrue(engine.isRunning)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertFalse(engine.isRunning)
        engine.play(.buttonPress)
        XCTAssertTrue(engine.isRunning)
        let buffer = try engine.renderOffline(frames: 1024)
        XCTAssertTrue((0..<Int(buffer.frameLength)).contains { abs(buffer.floatChannelData![0][$0]) > 0.001 })
        engine.stop(); XCTAssertFalse(engine.isRunning)
    }
    @MainActor
    func testReducedMotionFlashReusesBoundedNodesAndUsesCurrentPreference() throws {
        let screen = ScreenDescriptor(id: "motion", frame: CGRect(x: 0, y: 0, width: 640, height: 480), backingScale: 1)
        let scene = DesktopScene(screen: screen, mapper: try CoordinateMapper(canvasFrame: screen.frame, camera: SavedArea.homeCamera))
        var reduced = true; scene.reduceMotionProviding = { reduced }
        let coordinate = WorldCoordinate(x: 2, y: 2)
        scene.updateWorld(World(circuit: CircuitWorld(components: [coordinate: CircuitComponent(kind: .output)])))
        for _ in 0..<50 { scene.flashTile(coordinate); scene.flashOutput(at: coordinate) }
        XCTAssertTrue(scene.feedbackUsesReducedMotion)
        XCTAssertEqual(scene.childNode(withName: "output-flash")?.children.count, 1)
        reduced = false; scene.flashTile(coordinate)
        XCTAssertFalse(scene.feedbackUsesReducedMotion)
        XCTAssertEqual(scene.childNode(withName: "click-flash")?.hasActions(), true)
    }
}

extension MaintenanceTests {
    @MainActor
    func testFailedRollbackLocksOldWriterUntilStartupRecoversOriginalLibrary() async throws {
        let (directory, base, store, old) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        var maintenance = base, moves = 0
        maintenance.move = { source, destination in
            moves += 1
            if moves == 2 || moves == 3 { throw MaintenanceError(message: "Injected install/rollback failures") }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        let domain = "rollback-test-" + UUID().uuidString, prefs = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { prefs.removePersistentDomain(forName: domain) }
        let state = AppState(libraryStore: store, preferences: prefs, maintenanceStore: maintenance, preferencesDomain: domain, relauncher: RelaunchSpy())
        defer { state.shutdown() }
        let result = await state.startOver()
        XCTAssertFalse(result); XCTAssertTrue(state.isMaintenanceLocked)
        state.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), "Old instance cannot recreate a library while recovery is pending")
        let restored = AppState(libraryStore: store, preferences: prefs, maintenanceStore: base, preferencesDomain: domain)
        defer { restored.shutdown() }
        XCTAssertFalse(restored.isMaintenanceLocked)
        XCTAssertEqual(restored.library, old)
        XCTAssertEqual(try store.load(), old)
    }
}


extension MaintenanceTests {
    @MainActor
    func testEverySetupPageHostsWithBoundedWindowAndNoPermissionOrExecutionWork() throws {
        let state = AppState(); defer { state.shutdown() }
        for page in 0...3 {
            let host = NSHostingView(rootView: SetupWizardView(appState: state, initialPage: page))
            host.frame = CGRect(x: 0, y: 0, width: 600, height: 430)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize, CGSize(width: 600, height: 430))
            XCTAssertEqual(state.finderDiagnostics.readAttempts, 0)
            XCTAssertNil(state.desktopScriptAccessTask)
            XCTAssertFalse(state.isDesktopWorldEnabled)
        }
    }
}
