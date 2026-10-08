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
                .disabled(!tracker.isPolling && (!(appState.isDesktopWorldEnabled || appState.editorFinderItemsVisible) || model.permission != .allowed || model.isReading))
                Text(tracker.isPolling ? "Live updates enabled" : "Polling paused")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(model.viewSettings.map { "Finder icon size: \($0.iconSize)" } ?? "Finder icon size: unavailable (center tracking still works)")
                Spacer()
                Text(model.baselineViewSettings.map { "Session baseline: \($0.iconSize) · independent world scale" } ?? "Independent world scale")
            }.font(.caption).foregroundStyle(.secondary)
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
            Table(model.items) {
                TableColumn("Name") { item in Text(item.displayName) }
                TableColumn("Path") { item in Text(item.url.path).textSelection(.enabled) }
                TableColumn("Raw Finder position") { item in
                    Text("(\(item.position.x, specifier: "%.1f"), \(item.position.y, specifier: "%.1f"))")
                        .monospacedDigit()
                }
                TableColumn("Mapped screen / center") { item in
                    if let mapping = appState.finderMappings.first(where: { $0.id == item.id }) {
                        Text("(\(mapping.screenCenter.x, specifier: "%.1f"), \(mapping.screenCenter.y, specifier: "%.1f"))")
                    } else { Text("Enable Desktop World") }
                }
                TableColumn("World tile") { item in
                    if let tile = appState.finderMappings.first(where: { $0.id == item.id })?.tile {
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
            Text("Green: one icon center in the tile. Red: multiple centers; no item is chosen. Pink crosshairs show centers. Calibration was confirmed on your Mac; report any later misalignment.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 1000, minHeight: 450)
    }
}
