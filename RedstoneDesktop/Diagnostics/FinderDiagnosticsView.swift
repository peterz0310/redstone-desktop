import SwiftUI

struct FinderDiagnosticsView: View {
    @ObservedObject var model: FinderDiagnosticsModel
    @ObservedObject var tracker: DesktopItemTracker
    @ObservedObject var appState: AppState

    init(appState: AppState) {
        self.appState = appState
        model = appState.finderDiagnostics
        tracker = appState.desktopItemTracker
    }

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
            HStack {
                Button(tracker.isPolling ? "Stop Polling" : "Start Polling (2 Hz)") {
                    if tracker.isPolling { tracker.stop() } else { tracker.start() }
                }
                .disabled(!tracker.isPolling && (!appState.isDesktopWorldEnabled || model.permission != .allowed || model.isReading))
                Text(tracker.isPolling ? "Live updates enabled" : "Polling paused")
                    .foregroundStyle(.secondary)
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
                TableColumn("Mapped screen / assumed center") { item in
                    if let mapping = appState.finderMappings.first(where: { $0.id == item.id }) {
                        Text("(\(mapping.provisionalCenter.x, specifier: "%.1f"), \(mapping.provisionalCenter.y, specifier: "%.1f"))")
                    } else { Text("Enable Desktop World") }
                }
                TableColumn("World tile") { item in
                    if let tile = appState.finderMappings.first(where: { $0.id == item.id })?.tile {
                        Text("(\(tile.x), \(tile.y))")
                    } else { Text("—") }
                }
            }
            Text("Provisional: raw point is the icon center, measured from the primary display's upper-left. Pink rings/crosshairs must align with real icon centers. No menu-bar or icon-size offset is applied. Enable Desktop World to see markers; report any misalignment before continuing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 450)
    }
}
