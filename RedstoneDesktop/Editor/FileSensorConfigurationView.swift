import SwiftUI

/// Editing remains a draft until Save or Return; invalid drafts never replace the stored filter.
struct FileSensorConfigurationView: View {
    let filter: FileSensorFilter
    let save: (FileSensorFilter) -> Void
    @State private var draft: FileSensorFilter
    init(filter: FileSensorFilter, initialMatch: FileSensorMatch? = nil, save: @escaping (FileSensorFilter) -> Void) {
        self.filter = filter; self.save = save
        var initial = filter
        if let initialMatch { initial.match = initialMatch }
        _draft = State(initialValue: initial)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Detect", selection: $draft.match) {
                ForEach(FileSensorMatch.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if draft.match != .anyItem {
                TextField(draft.match == .fileExtension ? "Extensions, e.g. pdf, png, jpg" : "Full name, e.g. Notes.txt", text: $draft.value)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveDraft() }
                if draft.match == .fileExtension {
                    Text("Separate extensions with commas. Any listed type matches.").font(.caption).foregroundStyle(.secondary)
                }
                if !draft.isValid {
                    Text(draft.value.utf8.count > 255 ? "This filter is too long." : draft.match == .fileExtension ? "Enter an extension between each comma." : "Enter an item name to save.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Save") { saveDraft() }.disabled(!draft.isValid || draft == filter)
                Text(draft == filter ? "Saved" : "Unsaved changes").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: filter) { _, value in if draft != value { draft = value } }
    }
    private func saveDraft() {
        guard draft.isValid, draft != filter else { return }
        save(draft)
    }
}
