import SwiftUI

struct WorldLibraryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession
    @State private var worldName = ""
    @State private var areaName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Saved areas", selection: Binding(get: { appState.selectedAreaID }, set: { editor.selectArea($0, appState: appState) })) {
                    ForEach(appState.library.worlds) { world in
                        Section("\(world.name) · seed \(world.generation.seed)") {
                            ForEach(appState.library.areas.filter { $0.worldID == world.id }) { area in
                                Text("\(world.name) / \(area.name)\(area.id == appState.library.activeAreaID ? " · Active" : "")").tag(area.id)
                            }
                        }
                    }
                }.frame(maxWidth: 480)
                TextField("World name", text: $worldName).frame(width: 140)
                Button("Rename World") { appState.renameSelectedWorld(worldName) }
                    .disabled(appState.isEditorConfigurationLocked || worldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                TextField("Area name", text: $areaName).frame(width: 140)
                Button("Rename Area") { appState.renameSelectedArea(areaName) }
                    .disabled(areaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Desktop: \(appState.activeWorldName) / \(appState.library.activeArea!.name) · \(appState.libraryStatus)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onAppear { syncNames() }
        .onChange(of: appState.selectedAreaID) { _, _ in syncNames() }
    }

    private func syncNames() {
        worldName = appState.selectedDocument.name
        areaName = appState.selectedArea.name
    }
}
