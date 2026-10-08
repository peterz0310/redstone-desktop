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
                .disabled(!tracker.isPolling && (!(appState.isDesktopWorldEnabled || appState.editorFinderItemsVisible) || model.permission != .allowed || model.isReading || appState.isFinderPollingFrozen))
                Text(tracker.isPolling ? "Live updates enabled" : "Polling paused")
                    .foregroundStyle(.secondary)
            }
            Text("Attempts: \(model.readAttempts) · Last duration: \(model.lastReadDuration.map { String(format: "%.0f ms", $0 * 1000) } ?? "not measured")")
                .font(.caption.monospaced())
            if appState.isFinderPollingFrozen { Text("Automatic polling is frozen. Explicit Read and action refreshes still work.").font(.caption) }
            HStack {
                Text(model.viewSettings.map { "Finder icon size: \($0.iconSize)" } ?? "Finder icon size: unavailable (center tracking still works)")
                Spacer()
                Text(appState.finderScaleStatus)
            }.font(.caption).foregroundStyle(.secondary)
            if let baseline = model.baselineViewSettings {
                Text("Read session baseline: \(baseline.iconSize)").font(.caption).foregroundStyle(.secondary)
            }
            if model.isLayoutSettling {
                Text("Finder layout is settling; positions and actions wait for a fresh read.").font(.caption)
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
            let mappings = appState.diagnosticFinderMappings
            Table(model.items) {
                TableColumn("Name") { item in Text(item.displayName) }
                TableColumn("Path") { item in Text(item.url.path).textSelection(.enabled) }
                TableColumn("Raw Finder position") { item in
                    Text("(\(item.position.x, specifier: "%.1f"), \(item.position.y, specifier: "%.1f"))")
                        .monospacedDigit()
                }
                TableColumn("Mapped screen / center") { item in
                    if let mapping = mappings.first(where: { $0.id == item.id }) {
                        Text("(\(mapping.screenCenter.x, specifier: "%.1f"), \(mapping.screenCenter.y, specifier: "%.1f"))")
                    } else { Text("Mapping unavailable") }
                }
                TableColumn("World tile") { item in
                    if let tile = mappings.first(where: { $0.id == item.id })?.tile {
                        Text("(\(tile.x), \(tile.y))")
                    } else { Text("—") }
                }
            }
            if case let .unavailable(reason) = appState.desktopOccupancy {
                Text("Occupancy unavailable: \(reason)").foregroundStyle(.secondary)
            }
            if !appState.desktopOccupancy.ambiguousTiles.isEmpty {
                DisclosureGroup("Ambiguous tiles (red) — all occupants") {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(appState.desktopOccupancy.ambiguousTiles) { occupancy in
                                Text("Tile (\(occupancy.coordinate.x), \(occupancy.coordinate.y))")
                                    .font(.headline)
                                ForEach(occupancy.items) { item in
                                    Text("\(item.displayName) — \(item.url.path)")
                                        .textSelection(.enabled)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 100)
                }
            }
            Text("Positions use the primary Finder reference display in logical points, with Y flipped by CoordinateMapper. A tile with multiple centers is ambiguous; no occupant is chosen. Diagnostic raw-point labels and mapped-center rings are opt-in in Desktop Details. Raw dots and mapped rings share the same assumed center; they do not establish exact Finder icon/label hit regions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 450)
    }
}
