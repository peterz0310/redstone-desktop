import SwiftUI

struct BlueprintShelfView: View {
    @ObservedObject var library: BlueprintLibrary
    @ObservedObject var editor: EditorSession
    @ObservedObject var appState: AppState
    @State private var saving = false
    @State private var name = "My Circuit"
    private var canPlace: Bool { editor.circuitTest == nil && !editor.isPreviewing(appState) && !appState.isEditorConfigurationLocked }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Save Selection as Blueprint…") { saving = true }
                .disabled(editor.selection(appState).isEmpty || editor.isPreviewing(appState) || editor.circuitTest != nil)
                .popover(isPresented: $saving) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Save a reusable circuit").font(.headline)
                        TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Cancel") { saving = false }
                            Spacer()
                            Button("Save") { if editor.saveBlueprint(appState, name: name) { saving = false } }
                                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if !library.status.isEmpty { Text(library.status).font(.caption).foregroundStyle(.secondary) }
                    }.padding(20).frame(width: 300)
                }
            DisclosureGroup("Blueprints & Examples") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose one, then click clear ground. R rotates the preview; Escape cancels.").font(.caption).foregroundStyle(.secondary)
                    Text("Examples").font(.caption.bold())
                    ForEach(BlueprintLibrary.examples) { blueprint in
                        Button(blueprint.name) { editor.beginPaste(appState, blueprint: blueprint) }.disabled(!canPlace)
                    }
                    Text("Example Outputs are set to Do Nothing. Try Test Circuit to see them pulse.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Text("Your blueprints").font(.caption.bold())
                    if library.saved.isEmpty { Text("Save a selection to reuse it in any world.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(library.saved) { blueprint in
                        Button { editor.beginPaste(appState, blueprint: blueprint) } label: {
                            HStack { Text(blueprint.name).lineLimit(2); Spacer(); Text("\(blueprint.circuit.components.count)").font(.caption).foregroundStyle(.secondary) }
                        }.disabled(!canPlace)
                        .contextMenu { Button("Delete Blueprint", role: .destructive) { library.delete(blueprint.id) } }
                    }
                    if !library.status.isEmpty { Text(library.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                }.padding(.top, 8)
            }
        }
    }
}
