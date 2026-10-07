import SwiftUI

/// Small world selector; named area browsing and desktop reassignment are Slice 19B.
struct WorldLibraryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Saved worlds", selection: Binding(get: { appState.selectedWorldID }, set: { editor.selectWorld($0, appState: appState) })) {
                    ForEach(appState.library.worlds) { world in
                        Text("\(world.name) · seed \(world.generation.seed)\(world.id == appState.activeWorldID ? " · Desktop" : "")").tag(world.id)
                    }
                }.frame(maxWidth: 480).disabled(appState.isDesktopWorldEnabled)
                TextField("World name", text: $renameText).frame(width: 160)
                Button("Rename") { appState.renameSelectedWorld(renameText) }
                    .disabled(appState.isDesktopWorldEnabled || renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text("Desktop: \(appState.activeWorldName)").font(.caption)
            }
            Text(appState.libraryStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onAppear { renameText = appState.selectedDocument.name }
        .onChange(of: appState.selectedWorldID) { _, _ in renameText = appState.selectedDocument.name }
    }
}
