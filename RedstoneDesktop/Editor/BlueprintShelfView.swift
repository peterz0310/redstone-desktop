import SwiftUI

struct BlueprintShelfView: View {
    @ObservedObject var library: BlueprintLibrary
    @ObservedObject var editor: EditorSession
    @ObservedObject var appState: AppState
    @State private var name = "My Circuit"
    @State private var renaming: UUID?
    @State private var renameName = ""
    private var canPlace: Bool { editor.circuitTest == nil && !editor.isPreviewing(appState) && !appState.isEditorConfigurationLocked }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reusable circuits").font(.headline)
            Text("Select components on the map to save your own circuit, or choose a preview below to place one.").font(.caption).foregroundStyle(.secondary)
            Button("Save Selection as Blueprint…") { editor.isSavingBlueprint = true }
                .disabled(editor.selection(appState).isEmpty || editor.isPreviewing(appState) || editor.circuitTest != nil)
                .help("Save the selected components for use in any world.")
                .popover(isPresented: $editor.isSavingBlueprint) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save a reusable circuit").font(.headline)
                        Text("\(editor.selection(appState).count) selected components").font(.caption)
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") { editor.isSavingBlueprint = false }
                            Spacer()
                            Button("Save") { if editor.saveBlueprint(appState, name: name) { editor.isSavingBlueprint = false } }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || editor.selection(appState).isEmpty)
                        }
                        if !library.status.isEmpty { Text(library.status).font(.caption).foregroundStyle(.secondary) }
                    }.padding(20).frame(width: 300)
                }
            if let pending = editor.pendingPlacement {
                Text("Placing \(pending.blueprint.name)").font(.caption.bold())
                Text("Click clear ground · R rotates · Escape cancels").font(.caption).foregroundStyle(.secondary)
                Button("Cancel Placement") { editor.cancelPlacement() }
            }
            Text("Your blueprints").font(.headline)
            if library.saved.isEmpty { Text("Your saved circuits will appear here.").font(.caption).foregroundStyle(.secondary) }
            ForEach(library.saved) { blueprint in
                card(blueprint)
                    .contextMenu {
                        Button("Rename Blueprint…") { renaming = blueprint.id; renameName = blueprint.name }
                        Button("Delete Blueprint", role: .destructive) { library.delete(blueprint.id) }
                    }
            }
            Divider()
            Text("Examples").font(.headline)
            Text("Outputs are set to Do Nothing. Use Test Circuit to watch them work.").font(.caption).foregroundStyle(.secondary)
            ForEach(BlueprintLibrary.examples) { card($0) }
            if !library.status.isEmpty { Text(library.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
        }
        .popover(isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rename blueprint").font(.headline)
                TextField("Name", text: $renameName).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { renaming = nil }
                    Spacer()
                    Button("Save") { if let id = renaming, library.rename(id, to: renameName) { renaming = nil } }
                        .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !library.status.isEmpty { Text(library.status).font(.caption) }
            }.padding(20).frame(width: 300)
        }
    }
    private func card(_ blueprint: CircuitBlueprint) -> some View {
        Button { editor.beginPaste(appState, blueprint: blueprint) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: BlueprintPreviewImage.image(for: blueprint)).resizable().interpolation(.none).scaledToFit()
                    .frame(maxWidth: .infinity).frame(height: 100).clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)
                Text(blueprint.name).font(.subheadline.bold()).foregroundStyle(.primary)
                Text("\(blueprint.circuit.components.count) components · \(blueprint.width) × \(blueprint.height)").font(.caption).foregroundStyle(.secondary)
                if let description = BlueprintLibrary.description(for: blueprint) { Text(description).font(.caption).foregroundStyle(.secondary) }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(!canPlace).help("Place \(blueprint.name): click a destination on the map.")
    }
}
