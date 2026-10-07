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
            Text("Enable the desktop checker to test whether it appears beneath real Finder icons. Finder integration and circuits will be added in roadmap order.")
                .fixedSize(horizontal: false, vertical: true)
            Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") {
                appState.toggleDesktopWorld()
            }
            Text(appState.desktopStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Slice 2 · Desktop renderer window spike")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 320)
    }
}
