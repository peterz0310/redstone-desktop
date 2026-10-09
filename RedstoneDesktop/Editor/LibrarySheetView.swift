import SwiftUI

struct LibrarySheetView: View {
    let kind: LibrarySheet
    @ObservedObject var appState: AppState
    @ObservedObject var editor: EditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var seed: String
    @State private var error = ""
    private let worldID: UUID
    private let areaID: UUID
    private let originalName: String

    init(kind: LibrarySheet, appState: AppState, editor: EditorSession, targetID: UUID? = nil) {
        self.kind = kind; self.appState = appState; self.editor = editor
        let isWorld = kind == .renameWorld || kind == .deleteWorld
        let requestedWorldID = isWorld ? targetID ?? appState.selectedWorldID : appState.selectedWorldID
        let requestedAreaID = !isWorld ? targetID ?? appState.selectedAreaID : appState.selectedAreaID
        let label = isWorld ? appState.library.world(id: requestedWorldID)?.name ?? "Missing world"
            : appState.library.areas.first { $0.id == requestedAreaID }?.name ?? "Missing area"
        worldID = requestedWorldID; areaID = requestedAreaID; originalName = label
        _name = State(initialValue: kind == .newWorld ? "New World" : kind == .saveArea ? "New Area" : originalName)
        _seed = State(initialValue: editor.seedText)
    }

    private var title: String {
        switch kind {
        case .newWorld: "New World"
        case .saveArea: "Save Current View"
        case .renameWorld: "Rename World"
        case .renameArea: "Rename Area"
        case .deleteWorld: "Delete World?"
        case .deleteArea: "Delete Area?"
        }
    }
    private var deletes: Bool { kind == .deleteWorld || kind == .deleteArea }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            if deletes {
                Text(kind == .deleteWorld
                    ? "Delete “\(originalName)” and all its areas, circuit components and saved lever settings? This cannot be undone."
                    : "Remove “\(originalName)” from this world’s saved areas? Its circuit components stay on the map and can be seen from other views.")
                Text("Your Finder files are unaffected.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                if kind == .newWorld {
                    Text("Start a fresh map for new builds. Your other worlds stay in the sidebar.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        TextField("Seed", text: $seed).textFieldStyle(.roundedBorder)
                        Button("Preview") { preview() }
                        Button("Random") { seed = String(UInt64.random(in: .min ... .max)); preview() }
                    }
                    if let generation = editor.previewGeneration {
                        AreaPreviewView(snapshot: AreaPreviewSnapshot(document: WorldDocument(name: "Preview", generation: generation),
                            camera: SavedArea.homeCamera, displaySize: appState.desktopScreen?.frame.size ?? CGSize(width: 1440, height: 900)))
                        Text("Seed \(String(generation.seed)) · Home view").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("The seed chooses the landscape. Your new world will open in the editor; your desktop keeps its current area.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if kind == .saveArea {
                    Text("Bookmark the current view in \(appState.selectedDocument.name). You can return to this spot later. Your builds and current desktop stay as they are.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if deletes {
                    Button("Delete", role: .destructive) { submit() }
                } else {
                    Button(kind == .newWorld ? "Create World" : kind == .saveArea ? "Save Area" : "Rename") { submit() }
                        .keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(24).frame(width: 420)
    }

    private func preview() {
        editor.seedText = seed
        if !editor.previewSeed() { error = editor.status } else { error = "" }
    }

    private func submit() {
        let succeeded: Bool
        let previousArea = appState.selectedAreaID
        switch kind {
        case .newWorld:
            editor.seedText = seed; editor.newWorldName = name
            succeeded = editor.createWorld(appState)
            error = editor.status
        case .saveArea:
            editor.areaName = name; succeeded = editor.saveArea(appState); error = editor.status
        case .renameWorld: succeeded = appState.renameWorld(worldID, name: name); error = appState.libraryStatus
        case .renameArea: succeeded = appState.renameArea(areaID, name: name); error = appState.areaStatus
        case .deleteWorld:
            succeeded = appState.deleteWorld(worldID); error = appState.libraryStatus
            if succeeded && appState.selectedAreaID != previousArea { editor.syncSelectedWorld(appState) }
        case .deleteArea:
            succeeded = appState.deleteArea(areaID); error = appState.libraryStatus
            if succeeded && appState.selectedAreaID != previousArea { editor.syncSelectedWorld(appState) }
        }
        if succeeded { dismiss() }
    }
}
