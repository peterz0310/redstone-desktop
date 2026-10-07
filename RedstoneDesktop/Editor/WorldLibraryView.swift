import SwiftUI

enum LibrarySheet: String, Identifiable {
    case newWorld, saveArea, renameWorld, renameArea, deleteWorld, deleteArea
    var id: String { rawValue }
}

struct WorldLibraryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession
    @Binding var sheet: LibrarySheet?

    private func areaCount(for world: WorldDocument) -> String {
        let count = appState.library.areas.filter { $0.worldID == world.id }.count
        return "\(count) \(count == 1 ? "area" : "areas")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Worlds").font(.headline)
                Spacer()
                Button { sheet = .newWorld } label: { Image(systemName: "plus") }
                    .help("Create a new independent world")
            }
            Text("Each world has its own builds.\nAreas bookmark views within it.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(appState.library.worlds) { world in
                        Button {
                            editor.selectWorld(world.id, appState: appState)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                if let area = appState.library.areas.first(where: { $0.worldID == world.id }) {
                                    AreaPreviewView(snapshot: AreaPreviewSnapshot(document: world, camera: area.camera,
                                        displaySize: appState.desktopScreen?.frame.size ?? CGSize(width: 1440, height: 900)))
                                }
                                Text(world.name).font(.headline).lineLimit(2)
                                Text("Seed \(String(world.generation.seed))").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text(areaCount(for: world))
                                    if world.id == appState.activeWorldID { Label("Desktop", systemImage: "desktopcomputer") }
                                }.font(.caption2)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .background(world.id == appState.selectedWorldID ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(world.id == appState.selectedWorldID ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Menu("Manage World") {
                Button("Rename…") { sheet = .renameWorld }.disabled(appState.isEditorConfigurationLocked)
                Button("Delete World…", role: .destructive) { sheet = .deleteWorld }
                    .disabled(appState.library.deletionRestriction(worldID: appState.selectedWorldID) != nil)
            }
            .help(appState.library.deletionRestriction(worldID: appState.selectedWorldID) ?? "Manage the selected world")
        }.padding(12).frame(width: 190)
    }
}

struct AreaShelfView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession
    @Binding var sheet: LibrarySheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Areas in \(appState.selectedDocument.name)").font(.headline)
                Text("Saved views of this world").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Save Current View…") { sheet = .saveArea }.disabled(editor.isPreviewing(appState))
                Menu {
                    Button("Rename Area…") { sheet = .renameArea }
                    Button("Delete Bookmark…", role: .destructive) { sheet = .deleteArea }
                        .disabled(appState.library.deletionRestriction(areaID: appState.selectedAreaID) != nil)
                } label: { Image(systemName: "ellipsis") }
                .help(appState.library.deletionRestriction(areaID: appState.selectedAreaID) ?? "Manage the selected area")
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(appState.library.areas.filter { $0.worldID == appState.selectedWorldID }) { area in
                        Button { editor.selectArea(area.id, appState: appState) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                AreaPreviewView(snapshot: AreaPreviewSnapshot(document: appState.selectedDocument, camera: area.camera,
                                    displaySize: appState.desktopScreen?.frame.size ?? CGSize(width: 1440, height: 900)))
                                HStack {
                                    Text(area.name).lineLimit(1)
                                    Spacer()
                                    if area.id == appState.library.activeAreaID { Image(systemName: "desktopcomputer").help("Active desktop area") }
                                }.font(.caption).frame(width: 144)
                            }.padding(6)
                            .background(area.id == appState.selectedAreaID ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(area.id == appState.selectedAreaID ? Color.accentColor : .clear, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }.padding(2)
            }.frame(height: 128)
        }.padding(12)
    }
}
