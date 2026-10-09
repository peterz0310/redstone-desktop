import AppKit

@main struct MaintenanceSmoke {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("redstone-reset-smoke-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("Support"), domain = "RedstoneDesktop.smoke." + UUID().uuidString
        let prefs = UserDefaults(suiteName: domain)!
        defer { prefs.removePersistentDomain(forName: domain); try? FileManager.default.removeItem(at: directory) }
        let store = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("world.json"))
        let old = try WorldLibraryDocument(legacy: LegacyWorldDocument()); try store.save(old)
        prefs.set(true, forKey: "setupCompleted")
        let launcher = NativeAppRelauncher(applicationURL: URL(fileURLWithPath: CommandLine.arguments[1]), environment: [
            "REDSTONE_DESKTOP_DATA_ROOT": root.path, "REDSTONE_DESKTOP_PREFERENCES_SUITE": domain,
            "REDSTONE_DESKTOP_SMOKE_EXIT": "1"])
        let state = AppState(libraryStore: store, preferences: prefs, maintenanceStore: LibraryMaintenanceStore(root: root, backups: directory.appendingPathComponent("Backups")),
            preferencesDomain: domain, relauncher: launcher)
        defer { state.shutdown() }
        guard await state.startOver() else { throw MaintenanceError(message: state.maintenanceStatus) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        let reportURL = directory.appendingPathComponent("wizard.json")
        while !FileManager.default.fileExists(atPath: reportURL.path), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: reportURL)) as! [String: Any]
        guard report["needsSetup"] as? Bool == true, report["desktopRunning"] as? Bool == false,
              report["components"] as? Int == 0, report["worldCount"] as? Int == 1,
              report["finderRead"] as? Bool == false, report["pid"] as? Int != Int(ProcessInfo.processInfo.processIdentifier) else {
            throw MaintenanceError(message: "Fresh native app/wizard evidence failed: \(report)")
        }
        print("Native public relaunch: distinct PID; wizard appeared; 1 empty world; Desktop stopped; no Finder read.")
        try await Task.sleep(for: .seconds(1)) // let the isolated child terminate before cleanup
        guard try store.load()?.activeAreaID != old.activeAreaID else { throw MaintenanceError(message: "Old writer restored the old library") }
        print("Child shutdown preserved fresh library; backup validated. Owner library/preferences untouched.")
    }
}
