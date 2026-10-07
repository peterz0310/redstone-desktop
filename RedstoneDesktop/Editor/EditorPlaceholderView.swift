import SwiftUI

struct EditorPlaceholderView: View {
    @ObservedObject var appState: AppState

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
            Text("Enable the desktop checker and move the pointer to highlight a world tile. Finder integration and circuits will be added in roadmap order.")
                .fixedSize(horizontal: false, vertical: true)
            Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                appState.toggleDesktopWorld()
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
            Text("Slice 4 · Cursor highlight")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 480)
    }
}
