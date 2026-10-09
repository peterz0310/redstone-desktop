import Foundation

struct MaintenanceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A recoverable directory transaction. Source packs/Desktop/TCC are never reset targets.
struct LibraryMaintenanceStore {
    let root: URL
    let backups: URL
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    static func applicationDefault() -> Self {
        Self(root: URL.applicationSupportDirectory.appendingPathComponent("RedstoneDesktop"),
             backups: URL.applicationSupportDirectory.appendingPathComponent("RedstoneDesktopBackups"))
    }

    private var journal: URL { backups.appendingPathComponent("reset-in-progress.json") }

    /// A crash between directory renames rolls back at next launch before any migration/save.
    func recoverInterruptedReset(restorePreferences: ([String: Any]) throws -> Void) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: journal.path) else { return }
        guard journal.standardizedFileURL == journal.resolvingSymlinksInPath().standardizedFileURL else {
            throw MaintenanceError(message: "Reset recovery journal is linked; automatic recovery refused.")
        }
        let data = try Data(contentsOf: journal)
        guard data.count <= 4096,
              let record = try JSONSerialization.jsonObject(with: data) as? [String: String],
              record["root"] == root.standardizedFileURL.path,
              let name = record["backup"], !name.contains("/"), !name.contains(".."),
              let id = record["id"], UUID(uuidString: id) != nil else {
            throw MaintenanceError(message: "Invalid reset recovery journal. Preserve backups and repair before reopening.")
        }
        let backup = backups.appendingPathComponent(name), support = backup.appendingPathComponent("Support")
        guard backup.standardizedFileURL == backup.resolvingSymlinksInPath().standardizedFileURL,
              root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
            throw MaintenanceError(message: "Linked reset recovery paths; automatic recovery refused.")
        }
        let saved = try Data(contentsOf: backup.appendingPathComponent("preferences.plist"))
        guard saved.count <= 16 * 1024 * 1024,
              let preferences = try PropertyListSerialization.propertyList(from: saved, format: nil) as? [String: Any] else {
            throw MaintenanceError(message: "Reset preferences backup is invalid. Original data retained at \(backup.path).")
        }
        if manager.fileExists(atPath: support.path) {
            let store = WorldLibraryStore(fileURL: support.appendingPathComponent("library.json"), legacyFileURL: support.appendingPathComponent("world.json"))
            guard try store.load() != nil else { throw MaintenanceError(message: "Interrupted reset backup has no library. Recovery required.") }
            if manager.fileExists(atPath: root.path) { try move(root, backup.appendingPathComponent("InterruptedFreshSupport-" + UUID().uuidString)) }
            try move(support, root)
        } else {
            // There may have been no original directory on a first-launch reset.
            // The validated standalone snapshot still restores the pre-reset library.
            let snapshotStore = WorldLibraryStore(fileURL: backup.appendingPathComponent("library.json"), legacyFileURL: backup.appendingPathComponent("unused-legacy.json"))
            guard let snapshot = try snapshotStore.load() else { throw MaintenanceError(message: "Reset snapshot is missing. Recovery required.") }
            let currentStore = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("world.json"))
            if (try? currentStore.load()) != snapshot {
                if manager.fileExists(atPath: root.path) { try move(root, backup.appendingPathComponent("InterruptedFreshSupport-" + UUID().uuidString)) }
                try currentStore.save(snapshot)
            }
        }
        try restorePreferences(preferences)
        let staging = root.deletingLastPathComponent().appendingPathComponent(".RedstoneDesktop-reset-" + id)
        if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        try manager.removeItem(at: journal)
    }

    func reset(library: WorldLibraryDocument, preferences: [String: Any],
               clearPreferences: () throws -> Void, restorePreferences: () -> Void) throws -> URL {
        try library.validate()
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw MaintenanceError(message: "An interrupted reset needs startup recovery first.") }
        let manager = FileManager.default
        let canonicalRoot = root.standardizedFileURL, canonicalBackups = backups.standardizedFileURL
        guard canonicalRoot == root.resolvingSymlinksInPath().standardizedFileURL,
              canonicalBackups == backups.resolvingSymlinksInPath().standardizedFileURL,
              canonicalRoot != canonicalBackups,
              !canonicalBackups.path.hasPrefix(canonicalRoot.path + "/"),
              !canonicalRoot.path.hasPrefix(canonicalBackups.path + "/") else {
            throw MaintenanceError(message: "Reset paths are linked or overlap. Nothing replaced.")
        }
        for name in ["library.json", "world.json", "ImportedTextures"] {
            let url = root.appendingPathComponent(name)
            if manager.fileExists(atPath: url.path) {
                guard url.resolvingSymlinksInPath().standardizedFileURL == url.standardizedFileURL else {
                    throw MaintenanceError(message: "App-owned reset target is a symbolic link: \(name). Nothing replaced.")
                }
            }
        }
        let currentStore = WorldLibraryStore(fileURL: root.appendingPathComponent("library.json"), legacyFileURL: root.appendingPathComponent("world.json"))
        if manager.fileExists(atPath: currentStore.fileURL.path) {
            guard try currentStore.load() == library else { throw MaintenanceError(message: "Saved library differs from the prepared snapshot. Save Now and retry.") }
        }
        if manager.fileExists(atPath: currentStore.legacyFileURL.path) { _ = try WorldStore(fileURL: currentStore.legacyFileURL).load() }
        let imports = root.appendingPathComponent("ImportedTextures")
        if manager.fileExists(atPath: imports.path) {
            for folder in try manager.contentsOfDirectory(at: imports, includingPropertiesForKeys: nil) {
                _ = try JavaTextureImporter.record(in: folder, cacheRoot: imports)
            }
        }
        let prefData = try PropertyListSerialization.data(fromPropertyList: preferences, format: .xml, options: 0)
        guard prefData.count <= 16 * 1024 * 1024 else { throw MaintenanceError(message: "Preferences backup is too large. Nothing replaced.") }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let id = UUID().uuidString
        let backup = backups.appendingPathComponent("\(stamp)-\(id)")
        let staging = root.deletingLastPathComponent().appendingPathComponent(".RedstoneDesktop-reset-\(id)")
        try manager.createDirectory(at: backup, withIntermediateDirectories: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        let backupLibrary = WorldLibraryStore(fileURL: backup.appendingPathComponent("library.json"), legacyFileURL: backup.appendingPathComponent("unused-legacy.json"))
        try backupLibrary.save(library)
        try prefData.write(to: backup.appendingPathComponent("preferences.plist"), options: .atomic)
        let validatedPreferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: backup.appendingPathComponent("preferences.plist")), format: nil) as? [String: Any]
        guard try backupLibrary.load() == library, let validatedPreferences,
              NSDictionary(dictionary: validatedPreferences) == NSDictionary(dictionary: preferences) else {
            throw MaintenanceError(message: "Backup validation failed. Nothing replaced.")
        }
        let fresh = WorldLibraryDocument()
        let stagedStore = WorldLibraryStore(fileURL: staging.appendingPathComponent("library.json"), legacyFileURL: staging.appendingPathComponent("world.json"))
        try stagedStore.save(fresh)
        guard try stagedStore.load() == fresh else { throw MaintenanceError(message: "Fresh library staging failed. Nothing replaced.") }
        let manifest: [String: Any] = ["formatVersion": 1, "createdAt": stamp, "worldCount": library.worlds.count,
            "areaCount": library.areas.count, "activeAreaID": library.activeAreaID.uuidString,
            "recovery": "Quit the app. Restore Support as RedstoneDesktop and restore preferences.plist into the app's preference domain. See docs/RECOVERY.md."]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: backup.appendingPathComponent("backup.json"), options: .atomic)
        let record = ["root": root.standardizedFileURL.path, "backup": backup.lastPathComponent, "id": id]
        try JSONSerialization.data(withJSONObject: record).write(to: journal, options: .atomic)
        let support = backup.appendingPathComponent("Support")
        var movedOld = false, installedFresh = false
        do {
            if manager.fileExists(atPath: root.path) { try move(root, support); movedOld = true }
            try move(staging, root); installedFresh = true
            try clearPreferences()
            try manager.removeItem(at: journal)
        } catch {
            restorePreferences()
            do {
                if installedFresh { try move(root, backup.appendingPathComponent("FailedFreshSupport")) }
                if movedOld { try move(support, root) }
                if manager.fileExists(atPath: journal.path) { try manager.removeItem(at: journal) }
            } catch {
                throw MaintenanceError(message: "Reset rollback needs recovery. Original data is preserved at \(backup.path). Quit and follow docs/RECOVERY.md. \(error.localizedDescription)")
            }
            throw MaintenanceError(message: "Reset aborted and previous data restored. Backup: \(backup.path). \(error.localizedDescription)")
        }
        return backup
    }
}
