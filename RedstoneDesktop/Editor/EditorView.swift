import SwiftUI

struct EditorView: View {
    @ObservedObject var appState: AppState
    @StateObject private var editor = EditorSession()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Redstone Desktop").font(.headline)
                Spacer()
                Button(appState.isDesktopWorldEnabled ? "Disable Desktop World" : "Enable Desktop World") { appState.toggleDesktopWorld() }
                Button("Finder Diagnostics…") { openWindow(id: "finder-diagnostics") }
                Button("Save Now") { appState.saveWorldNow() }.disabled(!appState.canSaveWorld)
                Button("Desktop Controls…") { openWindow(id: "desktop-controls") }
            }.padding(12)
            Divider()
            HStack {
                Text("Seed")
                TextField("Unsigned whole number", text: $editor.seedText).frame(width: 200)
                    .onSubmit { editor.previewSeed() }
                Button("Preview") { editor.previewSeed() }
                Button("Random") { editor.randomSeed() }
                Button("Cancel Preview") { editor.cancelPreview(appState) }
                    .disabled(editor.previewGeneration == nil)
                Spacer()
                Button("Use This Area") { editor.useThisArea(appState) }
                    .disabled(appState.desktopScreen == nil)
            }.padding(.horizontal, 12).padding(.vertical, 8)
            Text("Orange: chosen desktop area · Blue: current desktop area · Zoom out to see the full outline.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tools").font(.headline)
                    ForEach(EditorSession.Tool.allCases, id: \.self) { tool in
                        Button { editor.tool = tool } label: {
                            HStack { Text(tool.rawValue); Spacer(); if editor.tool == tool { Image(systemName: "checkmark") } }
                        }
                        .disabled((appState.isDesktopWorldEnabled || editor.isPreviewing(appState)) && tool.editsWorld)
                    }
                    Divider()
                    HStack {
                        Button("−") { editor.zoom(by: 0.8) }
                        Button("+") { editor.zoom(by: 1.25) }
                    }
                    Text("\(editor.camera.pointsPerTile, specifier: "%.0f") pt/tile").font(.caption)
                    Button("Show desktop area") { editor.showDesktopArea(appState) }
                    Button("Reset view") { editor.resetCamera() }
                    Text("Pan: drag canvas\nZoom: scroll or +/−").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Developer Placement…") { openWindow(id: "developer-placement") }
                }.padding(12).frame(width: 165)
                Divider()
                EditorCanvasView(appState: appState, editor: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                inspector.frame(width: 245)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.isDesktopWorldEnabled ? "Desktop running — disable it to edit. Select and Pan still work." : "Editing enabled. Green preview: allowed; red: blocked. Use the grass area to the right (x=10–25, y=7–11).")
                if editor.isPreviewing(appState), let generation = editor.previewGeneration {
                    let invalid = appState.invalidCircuitTiles(for: generation)
                    Text("Seed preview — circuit editing paused. \(invalid.count) circuit tile(s) invalid in this seed.").foregroundStyle(invalid.isEmpty ? Color.secondary : Color.red)
                }
                Text(editor.status).foregroundStyle(.secondary)
                Text(appState.persistenceStatus).foregroundStyle(.secondary).textSelection(.enabled)
                if let error = appState.finderDiagnostics.error {
                    Text("Finder unavailable: \(error) — open Finder Diagnostics to retry.").foregroundStyle(.red).font(.caption)
                }
                Text("Terrain: \(editor.terrainMetrics.retainedChunks) cached chunks · \(editor.terrainMetrics.chunkNodes) chunk nodes · \(editor.terrainMetrics.generatedChunks) generated · \(editor.terrainMetrics.textureBuilds) textures").font(.caption)
                Text("Slice 19 · Seed browser")
                    .font(.caption)
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }
        .frame(minWidth: 900, minHeight: 720)
        .onAppear { editor.cancelPreview(appState) }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inspector").font(.headline)
                if let coordinate = editor.selectedTile {
                    Text("Tile (\(coordinate.x), \(coordinate.y))").font(.body.monospaced())
                    Text("Terrain: \(editor.browsingWorld(appState).tile(at: coordinate)?.terrain.rawValue ?? "unspecified")")
                    Text("Decoration: \(editor.browsingWorld(appState).tile(at: coordinate)?.decoration?.rawValue ?? "none")")
                    Text("Component: \(appState.desktopWorld.circuit.components[coordinate]?.kind.rawValue ?? "none")")
                    Text("Power: \(appState.simulator.power(at: coordinate).rawValue)")
                    if appState.desktopWorld.circuit.components[coordinate]?.kind == .repeater {
                        Text("Stored: \(appState.desktopWorld.circuit.components[coordinate]!.direction.rawValue), \(appState.desktopWorld.circuit.components[coordinate]!.repeaterDelay.rawValue)t")
                    }
                    Button("Erase selected component") { appState.eraseCircuitComponent(at: coordinate) }
                        .disabled(appState.isDesktopWorldEnabled || editor.isPreviewing(appState) || appState.desktopWorld.circuit.components[coordinate] == nil)
                } else { Text("Use Select, then click a tile.").foregroundStyle(.secondary) }
                Divider()
                if editor.tool == .repeater || editor.selectedTile.flatMap({ appState.desktopWorld.circuit.components[$0]?.kind }) == .repeater {
                    Picker("Direction", selection: $editor.direction) {
                        ForEach(Direction.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Delay", selection: $editor.delay) {
                        ForEach(RepeaterDelay.allCases, id: \.self) { Text("\($0.rawValue) redstone tick(s)").tag($0) }
                    }
                }
                if let coordinate = editor.selectedTile, appState.desktopWorld.circuit.components[coordinate]?.kind == .repeater {
                    Button("Apply direction/delay") {
                        appState.configureRepeater(at: coordinate, direction: editor.direction, delay: editor.delay)
                    }.disabled(appState.isDesktopWorldEnabled || editor.isPreviewing(appState))
                }
                if let tile = editor.hoveredTile {
                    Text("Hover (\(tile.x), \(tile.y))").font(.caption.monospaced())
                    if let component = editor.proposedComponent {
                        let result = appState.developerPlacementPreview(component, at: tile)
                        Text(editor.isPreviewing(appState) ? "Apply or cancel the seed preview to edit." : (appState.isDesktopWorldEnabled ? "Disable Desktop World to edit." : result.message))
                            .foregroundStyle(result.isAllowed ? Color.green : Color.red)
                    }
                }
                Text(appState.developerPlacementStatus).font(.caption).textSelection(.enabled)
                Divider()
                Text("To run a circuit, enable Desktop World and press its input on the real desktop. Editor clicks select/place; they do not open files.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
