import AppKit
import SwiftUI

/// Reads cached state only. Opening this view never reads Finder or requests permission.
struct DiagnosticSummaryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var finder: FinderDiagnosticsModel
    @ObservedObject private var tracker: DesktopItemTracker
    @ObservedObject private var assets: AssetLibrary

    init(appState: AppState) {
        self.appState = appState
        finder = appState.finderDiagnostics
        tracker = appState.desktopItemTracker
        assets = appState.assets
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assignment and saves").font(.headline)
            Text("Editing: \(appState.selectedDocument.name) / \(appState.selectedArea.name)")
            Text("Editor IDs: \(appState.selectedWorldID) / \(appState.selectedAreaID)").font(.caption.monospaced())
            Text("Desktop: \(appState.activeWorldName) / \(appState.library.activeArea!.name)")
            Text("Desktop IDs: \(appState.activeWorldID) / \(appState.library.activeAreaID)").font(.caption.monospaced())
            Text(appState.isDesktopBuildMode ? "Build Mode · simulation stopped" : (appState.isDesktopWorldEnabled ? (appState.isSimulationPaused ? "Desktop running · simulation paused" : "Desktop running") : "Desktop stopped"))
            Text("Library: \(appState.libraryLocation)").font(.caption.monospaced())
            if let path = appState.legacyLibraryLocation { Text("Legacy migration source/backup: \(path)").font(.caption.monospaced()) }
            Text(appState.persistenceStatus)
            Text("Pending save: \(appState.hasPendingSave ? "yes" : "no") · \(appState.library.worlds.count) worlds / \(appState.library.areas.count) areas")
            Text(appState.libraryStatus).font(.caption)
            Text(appState.areaStatus).font(.caption)
            Button("Save Now / Retry Save") { appState.saveWorldNow() }.disabled(!appState.canSaveWorld)
            Divider()
            Text("Permissions and Finder").font(.headline)
            Text("Finder Automation: \(finder.permission.rawValue)")
            Text("Desktop folder access: \(appState.desktopScriptAccessStatus)")
            Text("Script approval: per exact file; separate from macOS permissions")
            Text("Accessibility: not used by this app; no Accessibility permission request")
            Text("Finder: \(finder.items.count) items · \(finder.isReading ? "read in flight" : "idle") · \(appState.isFinderPollingFrozen ? "automatic polling frozen" : (tracker.isPolling ? "2 Hz polling scheduled" : "polling stopped"))")
            if let date = finder.lastSuccessfulRead { Text("Last successful read: \(date.formatted(date: .omitted, time: .standard))") }
            Text("Last Finder error: \(finder.error ?? "none")")
            Text("Display settling: \(appState.isDisplaySettling ? "yes" : "no") · Finder layout settling: \(finder.isLayoutSettling ? "yes" : "no")")
            Text("Finder layout generation: \(finder.layoutGeneration)").font(.caption.monospaced())
            Divider()
            Text("Geometry and runtime").font(.headline)
            Text("App \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") · \(ProcessInfo.processInfo.operatingSystemVersionString)").font(.caption)
            if let screen = appState.desktopScreen { Text("Target \(screen.id): \(rect(screen.frame)) · scale \(screen.backingScale)") }
            else { Text("Target display unavailable") }
            if let screen = appState.diagnosticFinderReferenceScreen { Text("Finder reference \(screen.id): \(rect(screen.frame)) · scale \(screen.backingScale)") }
            else { Text("Finder reference display unavailable") }
            DisclosureGroup("Current macOS displays (logical points)") {
                ForEach(NSScreen.screens.map { ScreenDescriptor(screen: $0) }, id: \.id) { screen in
                    Text("\(screen.id): \(rect(screen.frame)) · scale \(screen.backingScale)")
                }
            }
            if let window = appState.desktopController?.window {
                Text("Desktop window: \(rect(window.frame)) · level \(window.level.rawValue) · \(window.isVisible ? "visible" : "hidden") · ignores mouse \(window.ignoresMouseEvents ? "yes" : "no")")
            }
            Text("Desktop camera: \(camera(appState.desktopCamera))")
            Text("Saved assigned camera: \(camera(appState.library.activeArea!.camera))")
            if let scene = appState.editorDiagnosticScene { Text("Last editor canvas camera: \(camera(scene.mapper.camera))") }
            Text("Pointer screen: \(appState.pointer.map { "\($0.screenPoint.x), \($0.screenPoint.y) · display \($0.screenID ?? "outside")" } ?? "not sampled (Desktop stopped)")")
            if let pointer = appState.pointer, let world = pointer.worldPoint, let tile = pointer.tile {
                Text("Pointer world: \(world.x), \(world.y) · tile \(tile.x), \(tile.y)")
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulation: \(rate(appState.simulationRate.recentRate(at: now))) ticks/s measured · target 20 · \(appState.simulationTick) ticks since Start")
                    Text("Desktop FPS (scene callbacks): \(rate(appState.desktopController?.scene.frameRate.recentRate(at: now))) · target 30")
                    Text("Last editor FPS (scene callbacks): \(rate(appState.editorDiagnosticScene?.frameRate.recentRate(at: now))) · target 30")
                }
            }
            Text("Rates use recent callback timestamps, not target values or GPU presentation counters. No recent sample means stopped/hidden/paused or still collecting the first second.").font(.caption).foregroundStyle(.secondary)
            if let scene = appState.desktopController?.scene {
                let metrics = scene.terrainMetrics
                Text("Desktop terrain: \(metrics.retainedChunks) cached chunks · \(metrics.chunkNodes) nodes · \(metrics.generatedChunks) generated · \(metrics.textureBuilds) texture builds")
            }
            Text("Pack: \(assets.name) · \(assets.isLoading ? "loading" : "ready")")
            Text(assets.status).font(.caption)
            if let source = assets.source { Text("Pack source: \(source.path)").font(.caption.monospaced()) }
            Text("Pack warnings: \(assets.warnings.count)")
            Divider()
            Text("Last Output activation").font(.headline)
            if let event = appState.lastOutputActivation {
                Text("Tile \(event.tile.x), \(event.tile.y) · signal \(event.power.rawValue) · tick \(event.tick)")
                Text("World \(event.worldID) / area \(event.areaID)").font(.caption.monospaced())
            } else { Text("No Output rising edge in this desktop session") }
            Text(appState.lastActionResult)
            Divider()
            Text("Diagnostic controls (this app session)").font(.headline)
            overlay("Tile coordinates (up to 128 visible labels)", \.tileCoordinates)
            overlay("Raw Finder labels/dots (up to 256 centers)", \.rawFinderPoints)
            overlay("Mapped Finder center rings", \.mappedFinderCenters)
            overlay("Output occupancy labels", \.outputOccupancy)
            overlay("Chunk boundaries", \.chunkBoundaries)
            Toggle("Freeze automatic Finder polling", isOn: Binding(get: { appState.isFinderPollingFrozen }, set: { appState.setFinderPollingFrozen($0) }))
            Text("Explicit Finder reads and input/Output freshness checks remain active. Freeze is not a permission bypass or a frozen action target.").font(.caption)
            Toggle("Pause simulation", isOn: Binding(get: { appState.isSimulationPaused }, set: { appState.setSimulationPaused($0) }))
                .disabled(!appState.isDesktopWorldEnabled || appState.isDesktopBuildMode)
            Text("Pause retains signal/history but cancels pending actions and refuses new input. Resume advances retained history; held Output edges are not replayed. Stop resets pause and runtime state.").font(.caption)
            Button("Hide all diagnostic overlays") { appState.setDiagnosticOverlays(DiagnosticOverlaySettings()) }
        }
        .font(.callout)
        .textSelection(.enabled)
    }

    private func overlay(_ title: String, _ keyPath: WritableKeyPath<DiagnosticOverlaySettings, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { appState.diagnosticOverlays[keyPath: keyPath] }, set: { value in
            var settings = appState.diagnosticOverlays; settings[keyPath: keyPath] = value
            appState.setDiagnosticOverlays(settings)
        }))
    }
    private func rate(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "no recent sample" }
    private func camera(_ value: CameraState) -> String { "origin \(value.worldOrigin.x), \(value.worldOrigin.y) · \(value.pointsPerTile) pt/tile" }
    private func rect(_ value: CGRect) -> String { "(\(value.minX), \(value.minY)) \(value.width) × \(value.height) pt" }
}
