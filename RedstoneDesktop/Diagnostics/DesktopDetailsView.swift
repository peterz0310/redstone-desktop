import SwiftUI

struct DesktopDetailsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Redstone Desktop")
                    .font(.largeTitle)
                Text("Experimental macOS desktop world")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Divider()
                Text("Desktop controls and diagnostics")
                    .font(.headline)
                Text("Finder refreshes automatically while the desktop runs. This window shows input rejection details, camera mapping and the last action for troubleshooting.")
                    .fixedSize(horizontal: false, vertical: true)
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.toggleDesktopWorld()
                }
                Button("Finder Diagnostics…") {
                    openWindow(id: "finder-diagnostics")
                }
                Text("Desktop: \(appState.activeWorldName) / \(appState.library.activeArea!.name)")
                    .font(.headline)
                Text("Input attempts: \(appState.observedPressCount) · Simulation: 20 Hz")
                    .font(.caption.monospaced())
                Text(appState.lastActionResult)
                    .font(.callout)
                    .textSelection(.enabled)
                if !appState.lastPressMetadata.isEmpty {
                    Text(appState.lastPressMetadata)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                if let click = appState.lastClick {
                    Text("Clicks observed: \(appState.observedClickCount) · Last tile: (\(click.tile.x), \(click.tile.y))")
                        .font(.caption.monospaced())
                }
                Text(appState.desktopStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let pointer = appState.pointer {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen: (\(pointer.screenPoint.x, specifier: "%.1f"), \(pointer.screenPoint.y, specifier: "%.1f")) pt")
                        if let world = pointer.worldPoint, let tile = pointer.tile {
                            Text("World: (\(world.x, specifier: "%.2f"), \(world.y, specifier: "%.2f")) · Tile: (\(tile.x), \(tile.y))")
                            Text("Display: \(pointer.screenID ?? "—")")
                        } else {
                            Text("Pointer is outside the active display.")
                        }
                        Text("Camera origin: (\(appState.desktopCamera.worldOrigin.x, specifier: "%.1f"), \(appState.desktopCamera.worldOrigin.y, specifier: "%.1f")) · \(appState.desktopCamera.pointsPerTile, specifier: "%.0f") pt/tile")
                    }
                    .font(.caption.monospaced())
                }
                Divider()
                Text("Library and selection").font(.headline)
                Text("Editing: \(appState.selectedDocument.name) / \(appState.selectedArea.name)")
                Text("Assigned camera: (\(appState.desktopCamera.worldOrigin.x, specifier: "%.1f"), \(appState.desktopCamera.worldOrigin.y, specifier: "%.1f")) · \(appState.desktopCamera.pointsPerTile, specifier: "%.0f") pt/tile")
                Text(appState.persistenceStatus).textSelection(.enabled)
                Text(appState.libraryStatus).textSelection(.enabled)
                Text(appState.areaStatus).textSelection(.enabled)
                Text("Desktop runtime details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .frame(minWidth: 480, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 480)
    }
}
