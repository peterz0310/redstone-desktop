import AppKit
import SpriteKit

private struct ProfileStore: WorldLibraryStoring {
    func load() throws -> WorldLibraryDocument? { WorldLibraryDocument() }
    func save(_ document: WorldLibraryDocument) throws {}
}
/// Isolated unoptimized native benchmark. No owner preferences, saves or Finder actions.
@main struct PanProfile {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let assets = AssetLibrary()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("redstone-pan-profile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try JavaTextureImporter.importTextures(from: URL(fileURLWithPath: CommandLine.arguments[1]), cacheRoot: root)
        assets.apply(imported.pack)
        let app = AppState(libraryStore: ProfileStore(), assets: assets)
        defer { app.shutdown() }
        let editor = EditorSession(), renderer = EditorCanvasRenderer(), size = CGSize(width: 1100, height: 700)
        let start = CFAbsoluteTimeGetCurrent()
        _ = renderer.update(appState: app, editor: editor, size: size)
        print("initial_ms=\((CFAbsoluteTimeGetCurrent()-start)*1000)")
        for step in 0..<8 {
            editor.pan(by: CGSize(width: -320, height: 0), size: size)
            let t = CFAbsoluteTimeGetCurrent()
            let scene = renderer.update(appState: app, editor: editor, size: size)!
            print("step=\(step) ms=\((CFAbsoluteTimeGetCurrent()-t)*1000) textures=\(scene.terrainMetrics.textureBuilds)")
        }
    }
}
