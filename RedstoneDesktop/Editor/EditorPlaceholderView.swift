import SwiftUI

struct EditorPlaceholderView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Redstone Desktop")
                .font(.largeTitle)
            Text("Experimental macOS desktop world")
                .font(.title3)
                .foregroundStyle(.secondary)
            Divider()
            Text("Editor placeholder")
                .font(.headline)
            Text("Enable Desktop World and read Finder items. Place a harmless file or folder on OUTPUT, then click the desktop PRESS button. PRESS pulses for one second; LEVER stays on until clicked again. Each output opens its current occupant once when power rises.")
                .fixedSize(horizontal: false, vertical: true)
            Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                appState.toggleDesktopWorld()
            }
            Button("Finder Diagnostics…") {
                openWindow(id: "finder-diagnostics")
            }
            Text("PRESS: (2, 3) → OUTPUT: (7, 3) · Input clicks: \(appState.observedPressCount)")
                .font(.caption.monospaced())
            Text("LEVER: (2, 5) → OUTPUT: (7, 5) · Simulation: 20 Hz")
                .font(.caption.monospaced())
            Text("Delayed PRESS: (2, 7) → REPEATER: (5, 7), 4 ticks → OUTPUT: (7, 7)")
                .font(.caption.monospaced())
            Text("OUTPUT badges: EMPTY · ITEM · MANY · N/A (Finder unavailable)")
                .font(.caption)
            Text("Repeater power: \(appState.simulator.power(at: DemoCircuit.repeater).rawValue) · Output power: \(appState.simulator.power(at: DemoCircuit.repeaterOutput).rawValue)")
                .font(.caption.monospaced())
            Text("Button-row dust power: " + DemoCircuit.dust.map { String(appState.simulator.power(at: $0).rawValue) }.joined(separator: ", "))
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
            Spacer()
            Text("Slice 13 · Circuit renderer")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 480)
    }
}
