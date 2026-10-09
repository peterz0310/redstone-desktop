import SwiftUI

struct DesktopDetailsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Desktop Diagnostics")
                    .font(.largeTitle)
                Text("Experimental macOS desktop world")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                DiagnosticSummaryView(appState: appState)
                Divider()
                SettingsLink { Text("Sound, Appearance, Scale and Setup Settings…") }
                Divider()
                Text("Desktop controls and diagnostics")
                    .font(.headline)
                Text("Finder refreshes automatically while the desktop runs. This window shows input rejection details, camera mapping and the last action for troubleshooting.")
                    .fixedSize(horizontal: false, vertical: true)
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                    appState.setDesktopRunning(!appState.isDesktopWorldEnabled)
                }
                .disabled(appState.isDesktopBuildMode)
                Button("Finder Diagnostics…") {
                    openWindow(id: "finder-diagnostics")
                }
                Text("Desktop: \(appState.activeWorldName) / \(appState.library.activeArea!.name)")
                    .font(.headline)
                Text("Input attempts: \(appState.observedPressCount) · Simulation target: 20 Hz")
                    .font(.caption.monospaced())
                Text(appState.lastActionResult)
                    .font(.callout)
                    .textSelection(.enabled)
                if let result = appState.lastScriptResult {
                    DisclosureGroup("Last script result · exit \(result.exitCode)") {
                        Text(result.path).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Duration: \(result.duration, specifier: "%.2f") s\(result.truncated ? " · output truncated" : "")").font(.caption)
                        Text("stdout").font(.headline)
                        Text(result.stdout.isEmpty ? "(empty)" : result.stdout).font(.caption.monospaced()).textSelection(.enabled)
                        Text("stderr").font(.headline)
                        Text(result.stderr.isEmpty ? "(empty)" : result.stderr).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                SettingsLink { Text("Script settings…") }
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

            }
            .padding(32)
            .frame(minWidth: 480, maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 480)
    }
}
