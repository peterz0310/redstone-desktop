import SwiftUI

/// Valid drafts save immediately. An unfinished name never replaces the stored filter.
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
                TextField(draft.match == .fileExtension ? "Extension, e.g. pdf" : "Full name, e.g. Notes.txt", text: $draft.value)
                    .textFieldStyle(.roundedBorder)
                if !draft.isValid { Text("Enter a name or extension to save this filter.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: draft) { _, value in if value.isValid, value != filter { save(value) } }
        .onChange(of: filter) { _, value in if draft != value { draft = value } }
    }
}
