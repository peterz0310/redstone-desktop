import SwiftUI

struct FinderDiagnosticsView: View {
    @ObservedObject var model: FinderDiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Finder Automation: \(model.permission.rawValue)")
                Spacer()
                Button(model.isReading ? "Reading…" : "Read Finder Items") {
                    Task { await model.readItems() }
                }
                .disabled(model.isReading)
            }
            Text("Read-only: asks Finder for desktop item names, paths, and raw positions. The first read may show macOS's Automation permission prompt.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error = model.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if model.hasRead {
                Text("\(model.items.count) desktop items")
            }
            Table(model.items) {
                TableColumn("Name") { item in Text(item.displayName) }
                TableColumn("Path") { item in Text(item.url.path).textSelection(.enabled) }
                TableColumn("Raw Finder position") { item in
                    Text("(\(item.position.x, specifier: "%.1f"), \(item.position.y, specifier: "%.1f"))")
                        .monospacedDigit()
                }
            }
            Text("Positions are not calibrated yet. Move a desktop item and read again to compare. No automatic polling in this slice.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 700, minHeight: 400)
    }
}
